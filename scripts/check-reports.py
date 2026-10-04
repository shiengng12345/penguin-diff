#!/usr/bin/env python3
"""Independent CSV parser/writer and typed JSON file roundtrips, synthetic only.

No input JS is executed. json_lines uses the same static Rust core as the App.
CSV is a readable report, not a lossless typed interchange format.
"""
import csv
import hashlib
import io
import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = ["path", "status", "a_type", "b_type", "a_value", "b_value"]
OUT = ROOT / "build/verification/report-proof.json"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_csv(text, expected):
    require(isinstance(text, str) and bool(text), "Empty CSV report")
    try:
        rows = list(csv.reader(io.StringIO(text, newline=""), strict=True))
    except csv.Error as error:
        raise RuntimeError("Invalid CSV quoting") from error
    require(rows == [HEADER, *expected], "CSV rows/columns/values differ from independent expectations")
    # A separate standard-library encoder verifies quoted fields and CRLF record
    # boundaries, including quoted commas/newlines and doubled quotation marks.
    stream = io.StringIO(newline="")
    csv.writer(stream, lineterminator="\r\n").writerow(HEADER)
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="\r\n").writerows(expected)
    require(text == stream.getvalue(), "CSV quoting or CRLF record boundaries differ")
    return len(expected)


def validate_run(status, output, stderr, count):
    require(status == 0 and stderr == "", "Report process crashed or wrote stderr")
    lines = output.splitlines()
    require(len(lines) == count, "Missing/extra report process responses")
    try:
        values = [json.loads(line) for line in lines]
    except (ValueError, TypeError) as error:
        raise RuntimeError("Report response is not JSON") from error
    require(all(isinstance(value, dict) and value.get("ok") is True for value in values),
            "Core rejected a report request")
    return values


def subset(actual, expected, label):
    if isinstance(expected, dict):
        require(isinstance(actual, dict), label + ": missing typed object")
        for key, value in expected.items():
            require(key in actual, label + ": missing " + key)
            subset(actual[key], value, label + "." + key)
    elif isinstance(expected, list):
        require(isinstance(actual, list) and len(actual) == len(expected), label + ": array differs")
        for index, (value, wanted) in enumerate(zip(actual, expected)):
            subset(value, wanted, label + f"[{index}]")
    else:
        require(type(actual) is type(expected) and actual == expected, label + ": value differs")


def validate_json(report, expected, summary, complete, values):
    subset(report, {"ok":True, "schemaVersion":1, "policyVersion":1,
                    "complete":complete, "includesValues":values,
                    "exportedCount":len(expected), "summary":summary}, "report")
    rows = report.get("rows")
    require(isinstance(rows, list) and len(rows) == len(expected), "Missing typed report rows")
    for index, (actual, wanted) in enumerate(zip(rows, expected)):
        subset(actual, {k:wanted[k] for k in ["path", "segments", "status"]}, f"row{index}")
        require(type(actual.get("id")) is int, "Missing machine row ID")
        for side in ["a", "b"]:
            if values:
                subset(actual.get(side), wanted[side], f"row{index}.{side}")
                if wanted[side]["present"]:
                    for position in ["line", "column"]:
                        require(type(actual[side].get(position)) is int and actual[side][position] >= 0,
                                "Missing source position")
            else:
                require(actual.get(side) == {"type":wanted[side]["type"],
                        "present":wanted[side]["present"], "display":"<值未导出>"},
                        "Redacted report retained value fields")
    require(report.get("warnings") == [] and type(report.get("warningCount")) is int
            and report["warningCount"] == 0, "Unexpected/missing warnings metadata")
    require(report.get("hasMoreWarnings") is False, "Incomplete warning export")
    require(isinstance(report.get("incompleteRanges"), list), "Missing completeness diagnostics")
    if not complete:
        require('$["unknown"]' in report["incompleteRanges"], "Unknown result lost its path diagnostic")
    else:
        require(report["incompleteRanges"] == [], "Complete result has incomplete diagnostics")


def units(text):
    raw = text.encode("utf-16-le", errors="surrogatepass")
    return [int.from_bytes(raw[index:index+2], "little") for index in range(0, len(raw), 2)]


def node(kind, literal, **fields):
    return {"type":kind, "display":literal, "literal":literal, **fields}


MISSING = {"type":"Missing", "display":"<不存在>", "present":False}


def row(key, a, b=None, status="ONLY_A"):
    return {"path":"$." + key, "segments":[{"keyUnits":units(key)}], "status":status,
            "a":dict(a, present=True), "b":MISSING if b is None else dict(b, present=True)}


def corpus():
    scalar = [("negative", "-42", "Number"), ("negzero", "-0", "Number"),
              ("pluszero", "0", "Number"), ("nan", "NaN", "Number"),
              ("inf", "Infinity", "Number"), ("negInf", "-Infinity", "Number"),
              ("big", "9007199254740993n", "BigInt"), ("undef", "undefined", "Undefined"),
              ("nullish", "null", "Null")]
    string_values = {"empty":"", "quoted":'comma, "quote"\r\n汉字😀e\u0301',
                     "tab":"\tstart", "cr":"\rstart", "lf":"\nstart",
                     "long":"REPORT_PRIVATE_CANARY_" + "汉😀" * 4096}
    for index, trigger in enumerate(["=", "+", "-", "@", "＝", "＋", "－", "＠"]):
        string_values[f"formula{index}"] = trigger + 'SUM(1,2)"'
    fields = [f"{key}:{literal}" for key, literal, _ in scalar]
    fields += [f"{key}:{json.dumps(value,ensure_ascii=False)}" for key, value in string_values.items()]
    fields += [r"lone:'\ud800'", "array:[,undefined]", "unknown:missingBinding"]
    wanted = [row(key,node(kind,literal)) for key,literal,kind in scalar]
    wanted += [row(key,node("String",json.dumps(value,ensure_ascii=False),units=units(value)))
               for key,value in string_values.items()]
    wanted += [row("lone",node("String",'"\\ud800"',units=[55296])),
               row("array",node("Array","[<空槽>, undefined]",display="[ 2 项 ]",
                     items=[node("Hole","<空槽>"),node("Undefined","undefined")])),
               row("unknown",node("Unknown","<无法比较：UNRESOLVED_EXPRESSION>",
                     reason="UNRESOLVED_EXPRESSION"),status="NOT_COMPARABLE")]
    for key,b,status in [("undef",node("Null","null"),"TYPE_CHANGED"),
                        ("nan",node("Number","0"),"VALUE_CHANGED"),
                        ("pluszero",node("Number","-0"),"VALUE_CHANGED")]:
        match = next(item for item in wanted if item["path"] == "$." + key)
        match.update(b=dict(b,present=True),status=status)
    only_b = row("onlyB",node("Boolean","true"))
    only_b.update(a=MISSING,b=only_b["a"],status="ONLY_B")
    wanted.append(only_b)
    js = {"label":"js-specials", "kind":"js", "a":"var env={"+",".join(fields)+"};",
          "b":"var env={undef:null,nan:0,pluszero:-0,onlyB:true};",
          "rows":sorted(wanted,key=lambda item:item["path"]), "complete":False,
          "search":"formula"}
    nested = node("Object",'{"numbers": [-0, 9007199254740993, 1e10000], "surrogate": "\\udfff"}',
                  display="{ 2 个键 }", complete=True,
                  entries=[{"keyUnits":units("numbers"),"value":node("Array","[-0, 9007199254740993, 1e10000]",
                      display="[ 3 项 ]",items=[node("Number",value) for value in ["-0","9007199254740993","1e10000"]])},
                      {"keyUnits":units("surrogate"),"value":node("String",'"\\udfff"',units=[57343])}])
    exact = {"label":"json-exact", "kind":"json",
             "a":r'{"blob":{"numbers":[-0,9007199254740993,1e10000],"surrogate":"\udfff"}}',
             "b":"{}", "rows":[row("blob",nested)], "complete":True, "search":"blob"}
    bulk = {"label":"bulk-240", "kind":"json",
            "a":json.dumps({f"bulk{index:03}":index for index in range(240)}), "b":"{}",
            "rows":[row(f"bulk{index:03}",node("Number",str(index))) for index in range(240)],
            "complete":True, "search":"bulk000"}
    return [js,exact,bulk]


def summary(rows):
    result = {"total":len(rows)}
    for status,key in [("SAME","same"),("VALUE_CHANGED","valueChanged"),("TYPE_CHANGED","typeChanged"),
                       ("ONLY_A","onlyA"),("ONLY_B","onlyB"),("NOT_COMPARABLE","notComparable")]:
        result[key] = sum(item["status"] == status for item in rows)
    result["differences"] = result["total"] - result["same"] - result["notComparable"]
    return result


def csv_expected(rows, values):
    expected = []
    for item in rows:
        sides = []
        for name in ["a","b"]:
            side = item[name]
            literal = side.get("literal",side["display"]) if values else "<值未导出>"
            # Only real Number/BigInt literals can start with '-' here; strings
            # are represented as quoted literals. Do not confuse raw JS strings
            # with the resulting report cell content.
            if values and side["type"] in ["Number","BigInt"] and literal.startswith("-"):
                literal = "'" + literal
            sides.append(literal)
        expected.append([item["path"],item["status"],item["a"]["type"],item["b"]["type"],*sides])
    return expected


def main():
    fixtures = corpus()
    requests = []
    for case in fixtures:
        session = "report-oracle-" + case["label"]
        requests.append({"op":"compare","session":session,**{key:case[key] for key in ["kind","a","b"]}})
        for include_values,filtered in [(True,False),(False,False),(True,True)]:
            options = {"op":"report","session":session,"includeValues":include_values}
            if filtered:
                options.update(filter="ONLY_A",search=case["search"],searchScope="key")
            for format_name in ["json","csv"]:
                requests.append(dict(options,format=format_name))
        requests.append({"op":"release","session":session})
    payload = "".join(json.dumps(request,ensure_ascii=True)+"\n" for request in requests)
    profiles = {}
    for profile in ["debug","release"]:
        command = ["rtk","proxy","cargo","build","--locked","-p","compare-core","--example","json_lines"]
        if profile == "release": command.append("--release")
        subprocess.run(command,cwd=ROOT,check=True,timeout=300)
        binary = ROOT/"target"/profile/"examples/json_lines"
        before = hashlib.sha256(binary.read_bytes()).hexdigest()
        response = subprocess.run(["rtk","proxy",str(binary)],input=payload,cwd=ROOT,capture_output=True,
                                  text=True,timeout=60)
        replies = validate_run(response.returncode,response.stdout,response.stderr,len(requests))
        measured = {"requests":len(requests),"jsonFileRoundtrips":0,"csvReports":0,"csvRows":0}
        with tempfile.TemporaryDirectory(prefix="config-compare-report-") as temporary:
            for case_index,case in enumerate(fixtures):
                start = case_index * 8
                compared = replies[start]
                subset(compared,{"summary":summary(case["rows"]),"complete":case["complete"]},case["label"])
                require(len(compared["rows"]) == min(len(case["rows"]),200),"Initial page size differs")
                for variant,(values,filtered) in enumerate([(True,False),(False,False),(True,True)]):
                    expected = [item for item in case["rows"] if not filtered or
                                (item["status"]=="ONLY_A" and case["search"] in item["path"])]
                    report = replies[start+1+variant*2]
                    path = pathlib.Path(temporary)/f"{case_index}-{variant}.json"
                    path.write_text(json.dumps(report,ensure_ascii=True),encoding="utf-8")
                    with path.open(encoding="utf-8") as file: restored = json.load(file)
                    require(restored==report,"JSON file roundtrip altered typed data")
                    validate_json(restored,expected,summary(case["rows"]),case["complete"],values)
                    subset(restored,{"filter":"ONLY_A" if filtered else "all",
                                    "search":case["search"] if filtered else "",
                                    "searchScope":"key" if filtered else "all"},"report filters")
                    if not values:
                        require("REPORT_PRIVATE_CANARY_" not in path.read_text(),"Redacted report leaked long text")
                    measured["jsonFileRoundtrips"] += 1
                    measured["csvRows"] += validate_csv(replies[start+2+variant*2].get("text"),csv_expected(expected,values))
                    measured["csvReports"] += 1
        require(hashlib.sha256(binary.read_bytes()).hexdigest()==before,"Report probe binary changed")
        profiles[profile] = dict(measured,binarySHA256=before)
    evidence = {"realVaultAccessed":False,"userJSExecuted":False,"profiles":profiles,
                "corpusSHA256":hashlib.sha256(payload.encode()).hexdigest(),
                "scope":"Core reports + standard-library CSV/JSON files; GUI/clipboard/spreadsheet reopen separate"}
    OUT.parent.mkdir(parents=True,exist_ok=True)
    OUT.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps(evidence,ensure_ascii=False))


if __name__ == "__main__":
    main()
