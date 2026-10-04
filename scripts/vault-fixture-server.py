#!/usr/bin/env python3
"""Loopback-only synthetic Vault fixture. Never contacts another host or logs headers."""
import http.server
import json
import pathlib
import sys
import urllib.parse

class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if self.headers.get("X-Vault-Token") != "synthetic-token":
            status, body = 403, {"errors": ["forbidden"]}
        elif path == "/v1/sys/namespaces":
            status, body = 200, {"data": {"keys": []}}
        elif path in ["/v1/sys/internal/ui/mounts/FPMS-NT-V2", "/v1/sys/internal/ui/mounts/OTHER-KV", "/v1/sys/internal/ui/mounts/KV-V1"]:
            mount = path.rsplit("/", 1)[1]
            status, body = 200, {"data": {"type": "kv", "path": mount + "/", "options": {"version": "1" if mount == "KV-V1" else "2"}}}
        elif path == "/v1/KV-V1" or path.startswith("/v1/KV-V1/"):
            relative = path.removeprefix("/v1/KV-V1").strip("/")
            if urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("list") == ["true"]:
                keys = ["auth/", "common/"] if not relative else (["uat-swim", "qa-other"] if relative in ["auth", "common"] else [])
                status, body = 200, {"data": {"keys": keys}}
            elif relative.rsplit("/", 1)[-1] in ["uat-swim", "qa-other"]:
                name = relative.rsplit("/", 1)[-1]
                status, body = 200, {"data": {"PORT": 3000 if name == "uat-swim" else "3000", "BIG": 9007199254740993}}
            else:
                status, body = 404, {"errors": ["unknown"]}
        elif "/metadata" in path:
            relative = path.split("/metadata", 1)[1].strip("/")
            keys = ["auth/", "common/"] if not relative else (["uat-swim", "qa-other"] if relative in ["auth", "common"] else [])
            status, body = 200, {"data": {"keys": keys}}
        elif "/data/" in path:
            name = path.rsplit("/", 1)[1]
            if name in ["uat-swim", "qa-other"]:
                status, body = 200, {"data": {"data": {"PORT": 3000 if name == "uat-swim" else "3000", "BIG": 9007199254740993}, "metadata": {"version": 7, "created_time": "2026-10-03T01:02:03.123456789Z", "deletion_time": "2099-01-01T00:00:00Z", "destroyed": False}}}
            elif name in ["deleted", "destroyed"]:
                status, body = 404, {"data": {"data": None, "metadata": {"version": 8, "deletion_time": "2020-01-01T00:00:00Z" if name == "deleted" else "", "destroyed": name == "destroyed"}}}
            else:
                status, body = 404, {"errors": ["unknown"]}
        else:
            status, body = 404, {"errors": ["unknown"]}
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
port = server.server_address[1]
if len(sys.argv) > 1:
    pathlib.Path(sys.argv[1]).write_text(str(port))
print("SYNTHETIC_LOOPBACK_FIXTURE_PORT=" + str(port), flush=True)
server.serve_forever()
