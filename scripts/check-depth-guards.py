#!/usr/bin/env python3
"""Isolated Debug/Release resource probes. Only fixed synthetic inputs are used.

JavaScript is parsed statically, never executed. A core abort/timeout, stderr,
WORKER_INTERRUPTED or failed recovery is a failure, not an accepted resource limit.
"""
import hashlib
import json
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
SIZES = [1000, 10000, 1000000]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def expression(value):
    return "var env={field:" + value + "};"


AXES = {
    "parentheses": lambda n: expression("("*n + "1" + ")"*n),
    "unary": lambda n: expression("!"*n + "1"),
    "binary": lambda n: expression("1+"*n + "1"),
    "member": lambda n: expression("a" + ".x"*n),
    "call": lambda n: expression("f" + "()"*n),
    "regex": lambda n: expression("[" + "/a/,"*n + "]"),
    "conditional-alternative": lambda n: expression("true?1:"*n + "1"),
    "conditional-consequent": lambda n: expression("true?"*n + "1" + ":1"*n),
    "assignment": lambda n: expression("a="*n + "1"),
    "exponent": lambda n: expression("1**"*n + "1"),
    "arrow": lambda n: expression("a=>"*n + "1"),
    "new": lambda n: expression("new "*n + "A"),
    "array": lambda n: expression("["*n + "1" + "]"*n),
    "object": lambda n: expression("{x:"*n + "1" + "}"*n),
    "template": lambda n: expression("`${"*n + "1" + "}`"*n),
    "if": lambda n: "var env={};" + "if(true)"*n + "env.x=1;",
    "label": lambda n: "var env={};" + "".join("a"+str(i)+":" for i in range(n)) + "env.x=1;",
    "function": lambda n: expression("function(){return "*n + "1" + "}"*n),
    "class": lambda n: expression("class {m(){return "*n + "1" + "}}"*n),
    "arrow-lookahead": lambda n: expression("(" + "{x:"*n + "x" + "}"*n + ")=>1"),
    "paren-lookahead": lambda n: expression("(" + "("*n + "a" + ")"*n + ")"),
}


def validate_run(returncode, stdout, stderr, label, allowed_errors=("RESOURCE_LIMIT",)):
    require(returncode == 0, label + ": core process failed")
    require(stderr == "", label + ": core wrote stderr")
    lines = stdout.splitlines()
    require(len(lines) == 2, label + ": missing primary/recovery response")
    primary, recovery = map(json.loads, lines)
    if primary.get("ok") is True:
        require(primary.get("complete") in [True, False] and isinstance(primary.get("summary"), dict),
                label + ": malformed successful response")
    else:
        require(primary.get("ok") is False and primary.get("error", {}).get("code") in allowed_errors,
                label + ": wrong error outcome " + str(primary.get("error", {}).get("code")))
        require("rows" not in primary and "summary" not in primary, label + ": partial result after rejection")
    require(recovery.get("ok") is True and recovery.get("complete") is True
            and recovery.get("summary", {}).get("same") == 1, label + ": failed subsequent small input")
    rows = primary.get("rows", [])
    return {"ok": primary["ok"], "error": primary.get("error", {}).get("code"),
            "complete": primary.get("complete"), "summary":primary.get("summary"),
            "pageRows":len(rows), "firstRow":rows[0] if rows else None, "recoveryPassed": True}


def probe(binary, source, label, kind="js"):
    request = ({"op":"formatYaml", "source":source} if kind == "yaml" else
               {"op":"compare", "kind":kind, "a":source, "b":source, "session":"depth-probe"})
    recovery = {"op":"compare", "kind":"json", "a":"{}", "b":"{}", "session":"recovery"}
    payload = json.dumps(request) + "\n" + json.dumps(recovery) + "\n"
    began = time.monotonic()
    run = subprocess.run(["rtk", "proxy", str(binary)], cwd=ROOT, input=payload,
                         text=True, capture_output=True, timeout=30)
    # A very deep YAML flow fixture can be rejected by the dependency scanner
    # before our event-depth guard, with a controlled YAML_PARSE_ERROR.
    errors = ("RESOURCE_LIMIT", "YAML_PARSE_ERROR") if kind == "yaml" else ("RESOURCE_LIMIT",)
    outcome = validate_run(run.returncode, run.stdout, run.stderr, label, errors)
    return outcome | {"seconds":round(time.monotonic()-began, 6), "sourceBytes":len(source.encode()),
                      "sourceSHA256":hashlib.sha256(source.encode()).hexdigest()}


def main():
    output = ROOT / "build/depth-guards-check.json"
    output.parent.mkdir(exist_ok=True)
    results = {"passed":False, "userCodeExecuted":False, "realVaultAccessed":False,
               "sizes":SIZES, "axes":list(AXES), "profiles":{}}
    try:
        for profile in ["debug", "release"]:
            command = ["rtk", "proxy", "cargo", "build", "--locked", "-p", "compare-core", "--example", "json_lines"]
            if profile == "release": command.append("--release")
            subprocess.run(command, cwd=ROOT, check=True, timeout=300)
            binary = ROOT / "target" / profile / "examples/json_lines"
            binary_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
            records = []
            results["profiles"][profile] = {"binarySHA256":binary_hash, "probes":records}
            for axis, generate in AXES.items():
                for depth in SIZES:
                    label = f"{profile}/{axis}/{depth}"
                    source = generate(depth)
                    require(len(source.encode()) <= 20*1024*1024, label + ": fixture exceeds source limit before parser")
                    measured = probe(binary, source, label)
                    records.append({"axis":axis, "depth":depth} | measured)
                print("PASS " + profile + "/" + axis, flush=True)
            for kind, shape in [("json", "object"), ("json", "array"), ("yaml", "flow")]:
                for depth in SIZES:
                    if shape == "object": source = '{"x":'*depth + "1" + "}"*depth
                    elif shape == "array": source = '{"x":' + "["*(depth-1) + "1" + "]"*(depth-1) + "}"
                    else: source = "["*depth + "1" + "]"*depth + "\n"
                    require(len(source.encode()) <= 20*1024*1024, "Non-JS fixture exceeds source limit")
                    measured = probe(binary, source, f"{profile}/{kind}/{shape}/{depth}", kind)
                    require(measured["ok"] is False, "Excessive non-JS depth was accepted")
                    records.append({"axis":kind+"-"+shape, "depth":depth} | measured)
            # Shift the exhaustion point across lexer operations. The old
            # regex guard installed EOF then sliced source at EOF + 1.
            for offset in range(16):
                source = ";"*offset + expression("[" + "/a/g,"*1050000 + "]")
                measured = probe(binary, source, f"{profile}/regex-budget-offset/{offset}")
                require(measured["ok"] is False and measured["error"] == "RESOURCE_LIMIT", "Regex budget was not controlled")
                records.append({"axis":"regex-budget-offset", "offset":offset} | measured)
            # Preserve valid broad configurations that fit the original
            # node/evaluation limits; the earlier 600k cursor cap rejected them.
            for count, literal, expected_type, display in [(40000,"(undefined)","Undefined","undefined"),
                    (99000,"(undefined)","Undefined","undefined"), (99000,"'s'","String",'"s"'),
                    (99000,"-1","Number","-1")]:
                source = "var env={" + ",".join(f"k{index}:{literal}" for index in range(count)) + "};"
                measured = probe(binary, source, f"{profile}/valid-wide/{count}/{literal}")
                require(measured["ok"] is True and measured["complete"] is True
                        and measured["summary"]["total"] == count and measured["summary"]["same"] == count,
                        "Valid broad configuration was rejected or lost values")
                first = measured["firstRow"]
                require(first["status"] == "SAME" and first["a"]["type"] == expected_type
                        and first["a"]["display"] == display, "Wide configuration changed scalar type/value")
                records.append({"axis":"valid-wide", "fields":count, "literal":literal} | measured)
            # Large comment text is not syntax depth; no heuristic raw bracket
            # counting is allowed to mistake strings/comments for recursion.
            prefix, suffix = "/*", "*/var env={x:1};"
            source = prefix + "(" * (20*1024*1024 - len(prefix) - len(suffix)) + suffix
            for excess in [0, 1]:
                fixture = source + " "*excess
                require(len(fixture.encode()) == 20*1024*1024 + excess, "Incorrect source boundary fixture")
                measured = probe(binary, fixture, f"{profile}/source-limit/{excess}")
                require(measured["ok"] == (excess == 0), "20 MiB input boundary differs")
                if excess:
                    require(measured["error"] == "RESOURCE_LIMIT", "Wrong source-limit error")
                else:
                    require(measured["complete"] is True and measured["summary"]["same"] == 1
                            and measured["firstRow"]["path"] == "$.x"
                            and measured["firstRow"]["a"]["display"] == "1", "Large comment changed the known value")
                records.append({"axis":"source-limit", "excessBytes":excess} | measured)
            require(hashlib.sha256(binary.read_bytes()).hexdigest() == binary_hash, "Probe binary changed")
        results["passed"] = True
        print("DEPTH_GUARDS_OK", flush=True)
    finally:
        output.write_text(json.dumps(results, indent=2)+"\n")


if __name__ == "__main__":
    main()
