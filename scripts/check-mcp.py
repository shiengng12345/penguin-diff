#!/usr/bin/env python3
"""Exercise the packaged stdio server with synthetic text. No tokens in MCP messages."""
import json
import hashlib
import pathlib
import select
import socket
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
binary = root / "build/Config Compare.app/Contents/MacOS/ConfigCompare"
process = subprocess.Popen([str(binary), "--mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
sequence = 0
evidence = []

def require(condition, message="MCP verification failed"):
    if not condition:
        raise RuntimeError(message)

def send(method, params=None, notification=False):
    global sequence
    sequence += 1
    packet = {"jsonrpc": "2.0", "method": method}
    if params is not None:
        packet["params"] = params
    if not notification:
        packet["id"] = sequence
    process.stdin.write(json.dumps(packet) + "\n")
    process.stdin.flush()
    if notification:
        return
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if not select.select([process.stdout], [], [], 1)[0]:
            continue
        line = process.stdout.readline()
        require(line, "MCP exited before replying")
        result = json.loads(line)
        if result.get("id") == sequence:
            require("error" not in result, result)
            return result["result"]
    raise TimeoutError(method)

def call(name, arguments=None):
    return send("tools/call", {"name": name, "arguments": arguments or {}})


def typed_report(name, arguments):
    result = call(name, arguments)
    require(result.get("isError") is not True, "Synthetic packaged call failed")
    return json.loads(result["content"][0]["text"])


def check_static_boundary_and_types():
    dense_source = "var env={" + ",".join(["x:2"] * 402) + "};"
    dense = typed_report("env_compare", {"a":dense_source, "b":"var env={x:2};"})
    require(dense["warningCount"] == 401 and len(dense["warnings"]) == 200 and dense["hasMoreWarnings"] is True, "Warning preview exceeded or lost the count")
    columns = [warning["column"] for warning in dense["warnings"]]
    for offset, size, more in [(200,200,True),(400,1,False)]:
        page = typed_report("comparison_rows", {"session":dense["session"],"warningOffset":offset})
        require(page["rows"] == [] and page["warningCount"] == 401 and len(page["warnings"]) == size and page["hasMoreWarnings"] is more, "Independent warning pagination lost positions")
        columns.extend(warning["column"] for warning in page["warnings"])
    require(columns == list(range(14,1615,4)), "Paginated warning positions differ from independent source offsets")
    require(call("comparison_rows", {"session":dense["session"],"warningOffset":True}).get("isError") is True, "Boolean warning offset accepted")
    oversized = call("env_compare", {"a":"var env={" + ",".join(["x:2"] * 100002) + "};", "b":"var env={x:2};"})
    require(oversized.get("isError") is True and oversized["content"][0]["text"].startswith("RESOURCE_LIMIT："), "Warning budget did not fail before returning rows")
    unicode_source = "var env={\r  ['\\u{D800}']:'\\u{DFFF}',\u2028  ['\\uD800']:'\\uDFFF'\u2029};"
    unicode = typed_report("env_compare", {"a":unicode_source,"b":r"var env={'\uD800':'\uDFFF'};"})
    require(unicode["complete"] is True and unicode["summary"]["same"] == 1 and unicode["warningCount"] == 1 and unicode["warnings"][0]["line"] == 3 and unicode["warnings"][0]["column"] == 3, "Packaged XPC lost braced surrogates or line positions")
    duplicate = typed_report("env_compare", {"a":"var env={sensitive_key:'synthetic-secret',sensitive_key:2};", "b":"var env={sensitive_key:2};"})
    require(duplicate["rows"] == [] and duplicate["complete"] is True and duplicate["summary"]["same"] == 1, "Duplicate property changed last-value semantics")
    require(len(duplicate["warnings"]) == 1 and duplicate["warnings"][0]["code"] == "JS_DUPLICATE_PROPERTY" and duplicate["warnings"][0]["side"] == "A", "Packaged XPC lost source warnings")
    require("synthetic-secret" not in json.dumps(duplicate) and "sensitive_key" not in json.dumps(duplicate), "Source warning exposed input content")
    duplicate_page = typed_report("comparison_rows", {"session":duplicate["session"]})
    require(duplicate_page["warnings"] == duplicate["warnings"], "Pagination lost source warnings")
    with tempfile.TemporaryDirectory(prefix="config-compare-packaged-probe-") as temporary, socket.socket() as listener:
        directory = pathlib.Path(temporary)
        markers = [directory/name for name in ["file", "process", "import"]]
        module = directory/"synthetic.mjs"
        module.write_text("import fs from 'node:fs';fs.writeFileSync(" + json.dumps(str(markers[2])) + ",'synthetic');export default {};\n")
        listener.bind(("127.0.0.1",0)); listener.listen(16); listener.setblocking(False)
        url = f"http://127.0.0.1:{listener.getsockname()[1]}/synthetic"
        expressions = [
            "require('node:fs').writeFileSync("+json.dumps(str(markers[0]))+",'synthetic');",
            "require('node:child_process').execFileSync('/usr/bin/touch',["+json.dumps(str(markers[1]))+"]);",
            "fetch("+json.dumps(url)+");",
            "import("+json.dumps(module.as_uri())+");",
        ]
        for expression in expressions:
            report = typed_report("env_compare", {"a":expression+"var env={safe:1};","b":"var env={safe:1};"})
            require(report["complete"] is False and report["summary"]["same"] == 1, "Unknown call must retain incomplete diagnostic")
        time.sleep(0.1)
        connection = None
        try:
            connection, _ = listener.accept()
        except BlockingIOError:
            pass
        if connection is not None:
            connection.close()
            raise RuntimeError("Static comparison caused a synthetic loopback request")
        require(not any(marker.exists() for marker in markers), "Static comparison caused a filesystem/process/import side effect")
        source = r"var env={string:'\ud800',big:9007199254740993n,zero:-0,nan:NaN,infinity:Infinity,hole:[,],undef:undefined};"
        initial = typed_report("env_compare", {"a":source,"b":source,"includeValues":True})
        require(initial["rows"] == [], "Default differences filter unexpectedly returned SAME")
        typed = typed_report("comparison_rows", {"session":initial["session"],"filter":"all","includeValues":True})
        require(typed["complete"] is True and typed["summary"]["same"] == 7, "Special-value summary differs")
        rows = {row["path"]:row["a"] for row in typed["rows"]}
        expected = {"$.env.string":("String",'"\\ud800"'),"$.env.big":("BigInt","9007199254740993n"),
                    "$.env.zero":("Number","-0"),"$.env.nan":("Number","NaN"),"$.env.infinity":("Number","Infinity"),
                    "$.env.hole[0]":("Hole","<空槽>"),"$.env.undef":("Undefined","undefined")}
        for path, (kind, display) in expected.items():
            require(rows[path]["type"] == kind and rows[path]["display"] == display, "Special value lost type or display: "+path)
        require(rows["$.env.string"]["units"] == [55296], "Lone surrogate units were lost")
        bom = typed_report("env_compare", {"a":"\ufeffvar env={中文:'值'};","b":"var env={中文:'值'};"})
        detail = typed_report("comparison_rows", {"session":bom["session"],"filter":"all","includeValues":True})
        require(detail["rows"][0]["a"]["line"] == 1 and detail["rows"][0]["a"]["column"] == 20 and
                detail["rows"][0]["b"]["column"] == 17, "BOM first-line byte offsets changed across packaged XPC")
        measured = {"packagedBinarySHA256":hashlib.sha256(binary.read_bytes()).hexdigest(),
                    "syntheticSideEffectCases":4,"markersCreated":False,"loopbackConnections":0,
                    "typedSpecialCases":7,"loneSurrogateUnits":rows["$.env.string"]["units"],
                    "firstLineBOMColumns":{"a":20,"b":17},"passed":True}
        (root/"build/mcp-static-boundary-check.json").write_text(json.dumps(measured,indent=2)+"\n")

try:
    init = send("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "local-synthetic-check", "version": "1"}})
    require(init["capabilities"]["tools"] is not None, 'MCP verification failed at check 49')
    send("notifications/initialized", notification=True)
    tools = send("tools/list")
    require({tool["name"] for tool in tools["tools"]} == {"env_compare", "yaml_format", "vault_preview", "vault_compare", "comparison_rows"}, 'MCP verification failed at check 52')
    env_schema = next(tool for tool in tools["tools"] if tool["name"] == "env_compare")["inputSchema"]["properties"]
    require(env_schema["rootA"]["default"] == "*" and env_schema["rootB"]["default"] == "*", "MCP schema must advertise all-variable defaults")
    evidence.append("initialize/tools/list: PASS")
    yaml = call("yaml_format", {"source": "# comment\nx:  1\n"})
    require(yaml.get("isError") is not True and yaml["content"][0]["text"] == "# comment\nx: 1\n", 'MCP verification failed at check 55')
    env = call("env_compare", {"a": "var env={PORT:3000};", "b": "var env={PORT:'3000'};"})
    report = json.loads(env["content"][0]["text"])
    require(report["summary"]["typeChanged"] == 1 and report["includesValues"] is False, 'MCP verification failed at check 58')
    require("3000" not in env["content"][0]["text"], 'MCP verification failed at check 59')
    evidence.append("packaged XPC via MCP env/YAML/redaction: PASS")
    batch = typed_report("env_compare", {"a":"var env={y:2,x:3};var happy={x:y};", "b":"var env={y:2};var happy={};"})
    require(batch["summary"]["total"] == 3 and batch["summary"]["notComparable"] == 1 and batch["includesValues"] is False,
            "Default MCP must compare the whole file and retain unknown diagnostics")
    require({row["path"] for row in batch["rows"]} == {"$.env.x", "$.happy.x"}, "Batch paths must retain variable ownership")
    picked = typed_report("env_compare", {"a":"var env={y:2,x:3};var happy={x:y};", "b":"var env={y:2};var happy={};", "rootA":"env", "rootB":"env"})
    require(picked["summary"]["total"] == 2 and picked["rows"][0]["path"] == "$.x", "Explicit single-root comparison changed")
    evidence.append("packaged XPC via MCP all-variable default/single-root override/unknown: PASS")
    for a, b, path in [
        ("module.exports={PORT:3000};", "module.exports={PORT:4000};", '$["module.exports"].PORT'),
        ("exports.PORT=3000;", "exports.PORT=4000;", '$["module.exports"].PORT'),
        ("var env={x:1};module.exports={extra:5};", "var env={x:1};module.exports={};", '$["module.exports"].extra'),
    ]:
        exported = typed_report("env_compare", {"a":a, "b":b})
        require(exported["complete"] is True and exported["summary"]["differences"] == 1, "Independent CommonJS exports must not become false SAME")
        require(len(exported["rows"]) == 1 and exported["rows"][0]["path"] == path and exported["includesValues"] is False,
                "CommonJS default batch must retain the exported path and hide values")
    alias = typed_report("env_compare", {"a":"var env={x:1};module.exports=env;", "b":"var env={x:2};module.exports=env;"})
    require(alias["summary"]["total"] == 1 and alias["rows"][0]["path"] == "$.env.x", "CommonJS named-object alias must not be duplicated")
    paired = typed_report("env_compare", {"a":"var env={x:1};module.exports=env;", "b":"var env={x:1};module.exports={x:1};"})
    require(paired["summary"]["same"] == 2 and paired["summary"]["differences"] == 0 and paired["rows"] == [],
            "Alias versus equal independent export must not create artificial missing rows")
    evidence.append("packaged XPC via MCP independent CommonJS exports/reference-identity alias: PASS")
    rejected = call("vault_preview", {"url": "https://prod.example.invalid"})
    require(rejected.get("isError") is True and
            rejected["content"][0]["text"].startswith("VAULT_SCOPE_INVALID：包含工具未允许的参数"),
            "Scope override must fail parameter validation, not fall through to credential access")
    if "--vault" in sys.argv:
        preview = call("vault_preview")
        require(preview.get("isError") is not True, preview)
        plan = json.loads(preview["content"][0]["text"])
        require(len(plan["a"]) == 2 and len(plan["b"]) == 2, 'MCP verification failed at check 66')
        comparison = call("vault_compare", {"planId": plan["planId"]})
        require(comparison.get("isError") is not True, comparison)
        result = json.loads(comparison["content"][0]["text"])
        require(result["summary"]["typeChanged"] == 2 and result["summary"]["same"] == 2, 'MCP verification failed at check 70')
        require("9007199254740993" not in comparison["content"][0]["text"], 'MCP verification failed at check 71')
        evidence.append("authorized Keychain + real loopback HTTP + batch + independent mounts/names: PASS")
        print("MCP_VAULT_CHECK_OK; awaiting GUI revoke", flush=True)
        deadline = time.monotonic() + 180
        flag = root / "build/mcp-revoked.flag"
        while not flag.exists() and time.monotonic() < deadline:
            time.sleep(0.25)
        require(flag.exists(), "revoke check was not completed")
        require(call("comparison_rows", {"session": result["session"], "includeValues": True})["isError"] is True, 'MCP verification failed at check 79')
        require(call("vault_preview")["isError"] is True, 'MCP verification failed at check 80')
        evidence.append("GUI revoke blocks new reads and cached Vault rows: PASS")
    else:
        # No existence/value query and no Vault I/O: this also eliminates a race
        # where the user saves an authorization just after an absence check.
        evidence.append("Vault I/O: NOT_RUN (ordinary verification never calls credential-consuming tools)")
    evidence.append("scope override rejected before credential access: PASS")
    check_static_boundary_and_types()
    evidence.append("packaged XPC: warning budget +401 warning pagination + braced surrogate/line positions +4 synthetic side-effect probes +7 special types +BOM original positions: PASS")
    process.stdin.close()
    require(process.wait(timeout=10) == 0, 'MCP verification failed at check 88')
    stderr = process.stderr.read()
    require(stderr == "", "MCP wrote unexpected diagnostics")
    evidence.append("EOF exits cleanly; stdout protocol only; stderr empty: PASS")
    (root / "build/mcp-check.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2))
    print("MCP_PACKAGED_CHECK_OK: " + "; ".join(evidence))
finally:
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
