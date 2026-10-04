#!/usr/bin/env python3
"""Reproducible local quality gate; uses no real Vault, Token or AI API.

Development tools are required by this verifier, not by the resulting App.
Full device, UI/accessibility and distribution gates remain separate.
"""
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build/verification"
ENVIRONMENT = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
COMMANDS = [
    ("cli-entry-routing-tests", [sys.executable, "scripts/test-cli-entry.py"]),
    ("verifier-negative-tests", [sys.executable, "scripts/test-verifiers.py"]),
    ("third-party-notice-tests", [sys.executable, "scripts/test-licenses.py"]),
    ("oxc-vendor-provenance", [sys.executable, "scripts/check-oxc-vendor.py"]),
    ("rust-format", ["cargo", "fmt", "--all", "--check"]),
    ("rust-clippy", ["cargo", "clippy", "--locked", "--all-targets", "--", "-D", "warnings"]),
    ("rust-tests", ["cargo", "test", "--locked", "--workspace"]),
    ("synthetic-js-oracle", [sys.executable, "scripts/check-js-oracle.py"]),
    ("typed-json-csv-reports", [sys.executable, "scripts/check-reports.py"]),
    ("depth-guards", [sys.executable, "scripts/check-depth-guards.py"]),
    ("rust-static-debug", ["cargo", "build", "--locked", "-p", "compare-core"]),
    ("swift-clean", ["swift", "package", "--package-path", "apps/macos", "clean"]),
    ("swift-http-tls-controller-tests", [sys.executable, "scripts/check-network.py"]),
    ("release-package-sign-xpc", [sys.executable, "scripts/build-macos.py"]),
    ("packaged-mcp", [sys.executable, "scripts/check-mcp.py"]),
]


def source_manifest(root=ROOT):
    files = sorted(p for folder in ["crates", "vendor", "apps/macos/Sources", "apps/macos/Tests", "apps/macos/Packaging", "scripts"]
                   for p in (root / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
    files += [root/p for p in ["Cargo.toml", "Cargo.lock", "apps/macos/Package.swift", "apps/macos/Package.resolved"]]
    return "".join(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(root)}\n" for p in sorted(files))


def write_evidence(evidence):
    # Replace complete JSON atomically; readers never see a partially written
    # successful record. Persist an unfinished failure state before commands.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=OUT,
                                         prefix=".results-", delete=False) as file:
            temporary = pathlib.Path(file.name)
            json.dump(evidence, file, ensure_ascii=False, indent=2)
            file.write("\n")
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, OUT/"results.json")
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    evidence = {"machine": platform.machine(), "macOS": platform.mac_ver()[0],
                "runID":str(uuid.uuid4()), "passed":False, "finished":False,
                "candidateSHA256":None, "finalManifestSHA256":None,
                "manifestStable":False, "failure":None,
                "expectedCommandCount":len(COMMANDS),
                "realVaultAccessed": False, "formalReleasePassed": False, "commands": []}
    print("VERIFICATION_RUN_ID " + evidence["runID"], flush=True)
    manifest = None
    failure = None
    stage = "EVIDENCE_INITIALIZATION"
    try:
        OUT.mkdir(parents=True, exist_ok=True)
        write_evidence(evidence)
        stage = "INITIAL_MANIFEST"
        manifest = source_manifest()
        (OUT/"candidate.manifest.sha256").write_text(manifest)
        evidence["candidateSHA256"] = hashlib.sha256(manifest.encode()).hexdigest()
        stage = "GATE_CONFIGURATION"
        if not COMMANDS:
            raise RuntimeError("No verification commands configured")
        for name, command in COMMANDS:
            stage = "COMMAND"
            began = time.monotonic()
            print("RUN " + name, flush=True)
            entry = {"name":name, "command":["rtk","proxy",*command], "exitCode":None}
            evidence["commands"].append(entry)
            try:
                with (OUT/(name+".log")).open("w") as log:
                    result = subprocess.run(entry["command"], cwd=ROOT, env=ENVIRONMENT,
                                            stdout=log, stderr=subprocess.STDOUT, timeout=900)
                entry["exitCode"] = result.returncode
            except BaseException as error:
                entry["errorClass"] = type(error).__name__
                raise
            finally:
                entry["seconds"] = round(time.monotonic()-began,3)
            if result.returncode:
                print((OUT/(name+".log")).read_text(), flush=True)
                raise SystemExit(result.returncode)
            print("PASS " + name, flush=True)
    except BaseException as error:
        failure = error
        code = {"INITIAL_MANIFEST":"INITIAL_MANIFEST_UNAVAILABLE",
                "GATE_CONFIGURATION":"NO_COMMANDS",
                "EVIDENCE_INITIALIZATION":"EVIDENCE_INITIALIZATION_FAILED"}.get(stage,"COMMAND_ERROR")
        if isinstance(error, KeyboardInterrupt): code = "INTERRUPTED"
        elif isinstance(error, subprocess.TimeoutExpired): code = "COMMAND_TIMEOUT"
        elif isinstance(error, SystemExit): code = "COMMAND_FAILED"
        # Do not serialize arbitrary exception messages/command payloads.
        evidence["failure"] = {"code":code, "stage":stage, "errorClass":type(error).__name__}
    finally:
        if manifest is not None:
            try:
                current = source_manifest()
                evidence["finalManifestSHA256"] = hashlib.sha256(current.encode()).hexdigest()
                evidence["manifestStable"] = current == manifest
                (OUT/"final.manifest.sha256").write_text(current)
                if not evidence["manifestStable"] and failure is None:
                    failure = RuntimeError("Source changed during verification")
                    evidence["failure"] = {"code":"SOURCE_CHANGED", "stage":"FINAL_MANIFEST", "errorClass":"RuntimeError"}
            except BaseException as error:
                evidence["manifestStable"] = False
                evidence["finalManifestSHA256"] = None
                evidence["finalManifestError"] = type(error).__name__
                if failure is None:
                    failure = error
                    evidence["failure"] = {"code":"FINAL_MANIFEST_UNAVAILABLE", "stage":"FINAL_MANIFEST", "errorClass":type(error).__name__}
        evidence["passed"] = (failure is None and evidence["manifestStable"]
                              and len(evidence["commands"]) == evidence["expectedCommandCount"]
                              and all(command["exitCode"] == 0 for command in evidence["commands"]))
        if not evidence["passed"] and failure is None:
            failure = RuntimeError("Verification did not complete its expected gates")
            evidence["failure"] = {"code":"VERIFICATION_INCOMPLETE", "stage":"FINAL_RESULT", "errorClass":"RuntimeError"}
        evidence["finished"] = True
        write_evidence(evidence)
    if failure is not None:
        raise failure
    print("LOCAL_AUTOMATED_GATE_OK (full goal/device/distribution gates remain separate)",flush=True)


if __name__ == "__main__":
    main()
