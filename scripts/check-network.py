#!/usr/bin/env python3
"""Real URLSession fault matrix on loopback only; synthetic headers and bodies.

Starts two HTTP origins and one untrusted TLS origin. No system certificate or
Keychain changes. Requires Python/OpenSSL/Swift only as development test tools.
"""
import contextlib
import http.server
import json
import os
import pathlib
import re
import signal
import socket
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOCK = threading.Lock()
RECORDS = []


def validate_swift_run(output, inventory):
    """Verify the complete serial Swift Testing run against actual discovery.

    The project uses unparameterized, default-named tests. Fail closed if that
    contract changes rather than treating an unknown console format as a pass.
    Suite qualification matters: a same-named test elsewhere is not evidence.
    """
    expected = set()
    for line in inventory.splitlines():
        match = re.fullmatch(r"CompareTests\.(?:(\w+)/)?(\w+)\(\)", line)
        if not match:
            raise RuntimeError("Unsupported Swift test inventory identity")
        identity = (match[1], match[2])
        if identity in expected:
            raise RuntimeError("Duplicate Swift test inventory identity")
        expected.add(identity)
    if not expected:
        raise RuntimeError("Swift test inventory is empty")
    expected_suites = {suite for suite, _ in expected if suite is not None}
    suites_started, suites_passed, tests_passed = set(), set(), set()
    active_suite = active_test = None
    started = finished = False
    passed_after = r"passed after [0-9]+(?:\.[0-9]+)? seconds\."
    for line in output.splitlines():
        if not line.startswith(("◇", "✔", "✘", "↷", "━")):
            continue
        if finished:
            raise RuntimeError("Swift test events after completion")
        if line == "◇ Test run started.":
            if started:
                raise RuntimeError("Duplicate Swift test run")
            started = True
            continue
        if not started:
            raise RuntimeError("Swift test event before run start")
        suite_start = re.fullmatch(r"◇ Suite (\w+) started\.", line)
        suite_pass = re.fullmatch(r"✔ Suite (\w+) " + passed_after, line)
        test_start = re.fullmatch(r"◇ Test (\w+)\(\) started\.", line)
        test_pass = re.fullmatch(r"✔ Test (\w+)\(\) " + passed_after, line)
        footer = re.fullmatch(r"✔ Test run with (\d+) tests? in (\d+) suites? " + passed_after, line)
        if suite_start:
            name = suite_start[1]
            if active_suite is not None or active_test is not None or name not in expected_suites or name in suites_started:
                raise RuntimeError("Unexpected or overlapping Swift suite")
            suites_started.add(name); active_suite = name
        elif suite_pass:
            if active_test is not None or active_suite != suite_pass[1]:
                raise RuntimeError("Swift suite completion mismatch")
            suites_passed.add(active_suite); active_suite = None
        elif test_start:
            identity = (active_suite, test_start[1])
            if active_test is not None or identity not in expected or identity in tests_passed:
                raise RuntimeError("Unexpected, duplicate or overlapping Swift test")
            active_test = identity
        elif test_pass:
            identity = (active_suite, test_pass[1])
            if identity != active_test:
                raise RuntimeError("Swift test completion mismatch")
            tests_passed.add(identity); active_test = None
        elif footer:
            if (active_test is not None or active_suite is not None or tests_passed != expected
                    or suites_started != expected_suites or suites_passed != expected_suites
                    or int(footer[1]) != len(expected) or int(footer[2]) != len(expected_suites)):
                raise RuntimeError("Swift full run is incomplete or counts disagree with discovery")
            finished = True
        else:
            raise RuntimeError("Failed, skipped or unsupported Swift test event")
    if not finished:
        raise RuntimeError("Swift full run has no successful completion record")
    return {"swiftTestsPassed": len(tests_passed), "swiftSuitesPassed": len(suites_passed),
            "swiftRunCompleted": True}


def http_test_inventory(inventory):
    """Read Swift Testing's actual discovery output, including trait/multiline tests."""
    prefix = "CompareTests.HTTPTransportIntegration/"
    methods = []
    for line in inventory.splitlines():
        if not line.startswith(prefix):
            continue
        match = re.fullmatch(re.escape(prefix) + r"(\w+)\(\)", line)
        if not match:
            raise RuntimeError("Unsupported HTTP test identity: " + line)
        methods.append(match[1])
    if len(methods) < 9 or len(set(methods)) != len(methods):
        raise RuntimeError("HTTP/TLS runtime inventory is missing or ambiguous")
    return set(methods)


def validate_evidence(records, output, inventory):
    """Fail closed on missing/skipped tests and real wire violations, even -O."""
    complete_run = validate_swift_run(output, inventory)
    required_tests = http_test_inventory(inventory)
    section = re.search(r"(?ms)^◇ Suite HTTPTransportIntegration started\.\n(.*?)^✔ Suite HTTPTransportIntegration passed after", output)
    if section is None:
        raise RuntimeError("HTTP/TLS suite did not complete successfully")
    passed = set(re.findall(r"(?m)^✔ Test (\w+)\(\) passed", section[1]))
    if not required_tests or not required_tests.issubset(passed):
        raise RuntimeError("HTTP/TLS tests missing or skipped: " + ", ".join(sorted(required_tests-passed)))
    required_paths = {"/redirect", "/cookie", "/echo", "/raw", "/disconnect", "/slow",
                      "/declared-large", "/chunked-large", "/cancel"}
    required_paths.update(f"/echo-id/{n}" for n in range(40))
    required_paths.update(["/v1/sys/internal/ui/mounts/kv-a", "/v1/sys/internal/ui/mounts/kv-b",
                           "/v1/kv-a/auth/uat-swim", "/v1/kv-b/data/auth/qat-other",
                           "/v1/kv-b/data/auth/deleted", "/v1/kv-b/data/auth/destroyed"])
    paths = {record["path"] for record in records}
    if not required_paths.issubset(paths):
        raise RuntimeError("Wire evidence missing: " + ", ".join(sorted(required_paths-paths)))
    if any(record["method"] != "GET" for record in records):
        raise RuntimeError("Unexpected mutation request")
    redirects = sum(record["path"] == "/sink" for record in records)
    cookies = sum(record["cookiePresent"] for record in records)
    if redirects or cookies:
        raise RuntimeError("Redirect followed or Cookie persisted")
    return {**complete_run, "httpTestsPassed": sorted(required_tests), "redirectSinkRequests": redirects,
            "cookieRequests": cookies}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def finish(self):
        with contextlib.suppress(BrokenPipeError, ConnectionResetError):
            super().finish()

    def do_GET(self):
        # Do not store credential values, even though these tests are synthetic.
        with LOCK:
            RECORDS.append({"path": self.path, "method": self.command,
                            "cookiePresent": bool(self.headers.get("Cookie")),
                            "tokenPresent": bool(self.headers.get("X-Vault-Token"))})
        try:
            if self.path.startswith("/v1/sys/internal/ui/mounts/kv-"):
                mount = self.path.rsplit("/", 1)[-1]
                if mount not in ["kv-a", "kv-b"]:
                    self.json_response({"errors": ["unknown"]}, status=404)
                else:
                    self.json_response({"data": {"path": mount + "/", "type": "kv", "options": {"version": "1" if mount == "kv-a" else "2"}}})
            elif self.path in ["/v1/kv-a/auth/uat-swim", "/v1/kv-b/data/auth/qat-other", "/v1/kv-b/data/auth/deleted", "/v1/kv-b/data/auth/destroyed"]:
                first = self.path.startswith("/v1/kv-a/")
                if self.headers.get("X-Vault-Token") != ("synthetic-token-a" if first else "synthetic-token-b") or self.headers.get("X-Vault-Namespace") != ("team-a/" if first else "team-b/"):
                    self.json_response({"errors": ["forbidden"]}, status=403)
                elif self.path.endswith("/deleted"):
                    self.json_response({"data": {"data": None, "metadata": {"version": 8, "deletion_time": "2020-01-01T00:00:00Z", "destroyed": False}}}, status=404)
                elif self.path.endswith("/destroyed"):
                    self.json_response({"data": {"data": None, "metadata": {"version": 9, "destroyed": True}}}, status=404)
                elif first:
                    self.json_response(None, raw=b'{"data":{"big":9007199254740993,"s":"\\ud800","n":1e10000}}')
                else:
                    self.json_response(None, raw=b'{"data":{"data":{"big":9007199254740993,"s":"\\ud800","n":1e10000},"metadata":{"version":7,"created_time":"2026-10-03T01:02:03.123456789Z","deletion_time":"2099-01-01T00:00:00Z","destroyed":false,"custom_metadata":{"private":"synthetic-private"}}}}')
            elif self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", self.server.other_origin + "/sink")
                self.send_header("Content-Length", "0")
                self.end_headers()
            elif self.path == "/disconnect":
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
            elif self.path in ["/slow", "/cancel"]:
                time.sleep(3)
                self.json_response({"ok": True})
            elif self.path == "/declared-large":
                self.send_response(200)
                self.send_header("Content-Length", str(21 * 1024 * 1024))
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(b"x" * 65536)
                self.wfile.flush()
                # Keep the response alive so Foundation can deliver its headers;
                # an immediate premature EOF legitimately fails as a network error.
                time.sleep(3)
                self.close_connection = True
            elif self.path == "/chunked-large":
                self.send_response(200)
                self.send_header("Transfer-Encoding", "chunked")
                self.end_headers()
                chunk = b"x" * 65536
                for _ in range(336):
                    self.wfile.write(b"10000\r\n" + chunk + b"\r\n")
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            elif self.path == "/cookie":
                self.json_response({"ok": True}, cookie=True)
            elif self.path == "/echo":
                self.json_response({"cookiePresent": bool(self.headers.get("Cookie"))})
            elif self.path == "/raw":
                self.json_response(None, raw=b'{"n":9007199254740993,"s":"\\ud800"}')
            elif self.path.startswith("/echo-id/"):
                self.json_response({"id": int(self.path.rsplit("/", 1)[-1])})
            else:
                self.json_response({"ok": True})
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass

    def json_response(self, value, cookie=False, raw=None, status=200):
        body = raw if raw is not None else json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        if cookie:
            self.send_header("Set-Cookie", "synthetic=session; Path=/")
        self.end_headers()
        self.wfile.write(body)


def serve(server):
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


def stop_owned_group(process):
    """Only the new session created for this invocation; never our caller's group."""
    with contextlib.suppress(ProcessLookupError):
        os.killpg(process.pid, signal.SIGTERM)
    deadline = time.monotonic() + 1
    while True:
        process.poll()  # Reap the group leader even when its descendants persist.
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return
        if time.monotonic() >= deadline:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            return
        time.sleep(0.01)


def captured_run(arguments, environment, log, timeout):
    """Persist output and finish owned descendants on success, timeout or interrupt."""
    process = subprocess.Popen(arguments, cwd=ROOT, env=environment, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               text=True, encoding="utf-8", errors="replace", start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        stop_owned_group(process)
        try:
            stdout, stderr = process.communicate(timeout=1)
        except subprocess.TimeoutExpired as tail:
            # An escaped process could retain a pipe without remaining in our
            # group. Preserve bytes received; do not hang or signal other groups.
            def text(value):
                return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else (value or "")
            stdout, stderr = text(tail.stdout), text(tail.stderr)
            for stream in [process.stdout, process.stderr]:
                if stream is not None:
                    stream.close()
            process.wait(timeout=1)
        log.write_text(stdout + stderr)
        raise
    stop_owned_group(process)
    log.write_text(stdout + stderr)
    return subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)


def run_swift_tests(environment, evidence=None):
    evidence = evidence if evidence is not None else {}
    # Includes a cold package build, every discovered test and optional native
    # render captures. The expanded matrix exceeded the old 180-second budget;
    # keep a bounded five-minute run without omitting tests or reducing captures.
    evidence["stage"] = "primary"
    result = captured_run(["rtk", "proxy", "swift", "test", "--no-parallel", "--package-path", "apps/macos"],
                          environment, ROOT / "build/network-check.log", 300)
    evidence["suiteExitCode"] = result.returncode
    print(result.stdout, end="")
    print(result.stderr, end="")
    if result.returncode:
        raise SystemExit(result.returncode)
    evidence["stage"] = "discovery"
    inventory = captured_run(["rtk", "proxy", "swift", "test", "--package-path", "apps/macos", "list", "--skip-build"],
                             environment, ROOT / "build/network-inventory.log", 60)
    evidence["discoveryExitCode"] = inventory.returncode
    if inventory.returncode:
        raise SystemExit(inventory.returncode)
    return result.stdout + result.stderr, inventory.stdout


def run_matrix(evidence):
    with tempfile.TemporaryDirectory(prefix="config-compare-network-test-") as temp:
        cert, key = pathlib.Path(temp) / "cert.pem", pathlib.Path(temp) / "key.pem"
        subprocess.run(["rtk", "proxy", "openssl", "req", "-x509", "-newkey", "rsa:2048",
                        "-nodes", "-keyout", str(key), "-out", str(cert), "-days", "1",
                        "-subj", "/CN=localhost"], check=True, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)
        servers = [http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) for _ in range(3)]
        origins = [f"http://127.0.0.1:{s.server_port}" for s in servers]
        for server in servers:
            server.other_origin = origins[1]
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        servers[2].socket = context.wrap_socket(servers[2].socket, server_side=True)
        tls_origin = f"https://127.0.0.1:{servers[2].server_port}"
        for server in servers:
            serve(server)
        environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
                           CC_CORE_PROFILE="debug", CC_HTTP_FIXTURE=origins[0], CC_TLS_FIXTURE=tls_origin)
        try:
            # DirectCoreWorker test doubles share Rust's process-global session
            # store; real App clients have separate XPC processes. Serialize test
            # cases, with concurrency/cancellation exercised inside dedicated tests.
            output, inventory = run_swift_tests(environment, evidence)
            with LOCK:
                records = list(RECORDS)
            evidence["stage"] = "validation"
            measured = validate_evidence(records, output, inventory)
            evidence.update(stage="complete", requests=records)
            evidence.update(measured)
        finally:
            for server in servers:
                server.shutdown()
                server.server_close()


def main():
    build = ROOT / "build"
    build.mkdir(exist_ok=True)
    evidence = {"passed": False, "finished": False, "stage": "setup", "suiteExitCode": None,
                "discoveryExitCode": None,
                "origins": "ephemeral loopback only", "certificateTrustChanged": False,
                "realVaultAccessed": False, "requests": [], "failure": None}
    path = build / "network-check.json"
    path.write_text(json.dumps(evidence, indent=2))
    for name in ["network-check.log", "network-inventory.log"]:
        (build / name).write_text("")
    with LOCK:
        RECORDS.clear()
    began = time.monotonic()
    try:
        run_matrix(evidence)
        evidence["passed"] = True
    except BaseException as error:
        evidence["failure"] = {"stage": evidence["stage"], "errorClass": type(error).__name__}
        if isinstance(error, SystemExit) and isinstance(error.code, int):
            evidence["failure"]["exitCode"] = error.code
        raise
    finally:
        with LOCK:
            evidence["requests"] = list(RECORDS)
        evidence["finished"] = True
        evidence["seconds"] = round(time.monotonic() - began, 3)
        path.write_text(json.dumps(evidence, indent=2))
    print("REAL_LOOPBACK_NETWORK_MATRIX_OK")


if __name__ == "__main__":
    main()
