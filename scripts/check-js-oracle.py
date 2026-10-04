#!/usr/bin/env python3
"""Compare static semantics with Node for fixed, generated, trusted programs ONLY.

No CLI inputs, user files, Vault data or credentials are accepted. Node is a
development test dependency, never an App dependency. No user JS is executed.
"""
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEED = 0x5E202610
CORPUS_SHA256 = "d248cf3ce40849ed1230cd2f3c832f95408164cbd53177c4c3096df0a18ba729"
ORACLE = r'''
const vm = require('node:vm');
let random = 0x5e202610;
function next() { random ^= random << 13; random ^= random >>> 17; random ^= random << 5; return random >>> 0; }
const literals = ['0','-0','1','-1','0.1','0.2','1e-7','1e-6','1e20','1e21',
    '9007199254740991','9007199254740992','9007199254740993','5e-324','1.7976931348623157e308',
    'Infinity','-Infinity','NaN','123.456','-987.654'];
const hole = Symbol('hole'), missing = Symbol('missing');
function program(template) {
    const x=literals[next()%literals.length], y=literals[next()%literals.length], n=next()%1000;
    switch(template) {
    case 0: return {source:`var env={n:${x},nested:{other:${y}},empty:{},array:[]};`,root:'env'};
    case 1: return {source:`var env={add:(${x})+(${y}),sub:(${x})-(${y}),mul:(${x})*(${y}),div:(${x})/(${y})};`,root:'env'};
    case 2: return {source:`var env={n:${x},remove:1};var alias=env;alias.n=${y};delete alias.remove;module.exports=env;env={n:${n}};`,root:'module.exports'};
    case 3: return {source:`var n=${x};var base={n:1,other:${y}};var env={n,...base,n:${n},nested:{...base}};`,root:'env'};
    case 4: return {source:`var xs=[${x},,${y}];var env={xs:xs,copy:[...xs],read:xs[1],length:xs.length};`,root:'env'};
    case 5: return {source:`var env={[${x}]:${y},fixed:${n},nan:NaN,zero:-0,big:9007199254740993n};`,root:'env'};
    case 6: return {source:String.raw`var text='a\ud800汉字';var env={text:text+'${n}',undef:undefined,nullish:null,flag:${n%2===0}};`,root:'env'};
    case 7: return {source:`var env={x:${x},b:${y}};if(${n%2===0})env.x=${n};else env.b=${n};`,root:'env'};
    case 8: {
        const typed=['null','undefined','true','false','0','-0','NaN','Infinity',"'text'",'1n','{}','[]','[,]'];
        return {source:`var env={value:${typed[next()%typed.length]}};`,root:'env'};
    }
    case 9: {
        const separator=['\n','\r\n','\r','\u2028','\u2029'][next()%5];
        return {source:String.raw`var base={'\u{D800}':'\u{DFFF}'};var env={${separator}  ['\uD800']:base['\uD800'],${separator}  ['\u{D800}']:'\uDFFF',${separator}  emoji:'\u{1F600}',${separator}  tail:'\u{10FFFF}',${separator}  number:${n}${separator}};`,root:'env'};
    }
    case 10: return {source:`var base={x:${x},x:${y}};var env={...base,x:${n}};`,root:'env'};
    default: throw Error('Unknown trusted template');
    }
}
function kind(v) {
    if(v===missing)return 'Missing';if(v===hole)return 'Hole';if(v===null)return 'Null';
    if(Array.isArray(v))return 'Array';
    return {undefined:'Undefined',boolean:'Boolean',number:'Number',bigint:'BigInt',string:'String',object:'Object'}[typeof v];
}
function side(v) {
    const type=kind(v);let display;
    switch(type){
    case 'Missing':display='<不存在>';break;
    case 'Hole':display='<空槽>';break;
    case 'String':display=JSON.stringify(v);break;
    case 'BigInt':display=String(v)+'n';break;
    case 'Number':display=Object.is(v,-0)?'-0':String(v);break;
    case 'Object':display=`{ ${Object.keys(v).length} 个键 }`;break;
    case 'Array':display=`[ ${v.length} 项 ]`;break;
    default:display=String(v);
    }
    return {type,display,present:v!==missing};
}
function own(v,k){return Object.hasOwn(v,k)?v[k]:(Array.isArray(v)?hole:missing);}
function diff(a,b,path='$',segments=[],rows=[]) {
    const ta=kind(a),tb=kind(b);let status;
    if(a===missing)status='ONLY_B';else if(b===missing)status='ONLY_A';
    else if(ta!==tb)status='TYPE_CHANGED';
    else if(ta==='Object'){
        const keys=[...new Set([...Object.keys(a),...Object.keys(b)])].sort();
        if(keys.length){for(const k of keys){
            const p=/^[a-zA-Z0-9_]+$/.test(k)?`${path}.${k}`:`${path}[${JSON.stringify(k)}]`;
            const keyUnits=Array.from({length:k.length},(_,i)=>k.charCodeAt(i));
            diff(own(a,k),own(b,k),p,[...segments,{keyUnits}],rows);
        }return rows;}status='SAME';
    }else if(ta==='Array'){
        const length=Math.max(a.length,b.length);
        if(length){for(let i=0;i<length;i++)diff(i<a.length?own(a,i):missing,i<b.length?own(b,i):missing,`${path}[${i}]`,[...segments,{index:i}],rows);return rows;}
        status='SAME';
    }else status=Object.is(a,b)?'SAME':'VALUE_CHANGED';
    rows.push({path,segments,status,a:side(a),b:side(b)});return rows;
}
const cases=[];
function evaluate(program) {
    const exports={};
    return vm.runInNewContext(program.source+';'+program.root,{exports,module:{exports}}, {timeout:100});
}
for(let template=0;template<11;template++)for(let iteration=0;iteration<128;iteration++){
    const a=program(template),b=iteration%4===0?a:program(template);
    // Only the fixed templates above run here. No caller supplies source code.
    const av=evaluate(a), bv=evaluate(b);
    cases.push({template,iteration,a:a.source,b:b.source,rootA:a.root,rootB:b.root,rows:diff(av,bv)});
}
process.stdout.write(JSON.stringify(cases));
'''


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def validate_cases(cases, lines):
    require(len(lines) == len(cases), "Core response count differs from oracle")
    rows_checked = 0
    counts = {status:0 for status in ["SAME","VALUE_CHANGED","TYPE_CHANGED","ONLY_A","ONLY_B"]}
    for case, line in zip(cases, lines):
        result = json.loads(line)
        label = f"seed={SEED:x}, template={case['template']}, iteration={case['iteration']}"
        require(result.get("ok") is True and result.get("complete") is True, f"{label}: {result}")
        actual = [{k: r[k] for k in ["path", "segments", "status"]} |
                  {s: {k: r[s][k] for k in ["type", "display", "present"]} for s in ["a", "b"]}
                  for r in result["rows"]]
        require(actual == case["rows"], f"{label}: expected {case['rows']}, got {actual}")
        expected = {"total":len(actual),"notComparable":0}
        for status, key in [("SAME","same"),("VALUE_CHANGED","valueChanged"),("TYPE_CHANGED","typeChanged"),("ONLY_A","onlyA"),("ONLY_B","onlyB")]:
            expected[key] = sum(r["status"] == status for r in case["rows"])
        expected["differences"] = expected["total"] - expected["same"]
        require(result["summary"] == expected, f"{label}: summary differs")
        # Template 3 defines n explicitly before and after a known spread.
        # The independent runtime rows prove last-definition-wins semantics.
        warnings = result.get("warnings")
        require(isinstance(warnings, list) and len(warnings) == (2 if case["template"] in [3,9,10] else 0), f"{label}: duplicate-property warnings differ")
        require(type(result.get("warningCount")) is int and result["warningCount"] == len(warnings) and result.get("hasMoreWarnings") is False, f"{label}: warning metadata differs")
        require(all(w["code"] == "JS_DUPLICATE_PROPERTY" and
                    ((w["line"] == 3 and w["previousLine"] == 2 and w["column"] == w["previousColumn"] == 3) if case["template"] == 9
                     else (w["line"] == w["previousLine"] == 1 and w["column"] > w["previousColumn"])) for w in warnings), f"{label}: warning positions differ")
        rows_checked += len(actual)
        for row in actual:
            counts[row["status"]] += 1
    return {"rowsChecked":rows_checked,"statusCounts":counts}


def main():
    oracle = subprocess.run(["rtk", "proxy", "node", "--input-type=commonjs", "-e", ORACLE],
                            cwd=ROOT, capture_output=True, text=True, check=True, timeout=60)
    cases = json.loads(oracle.stdout)
    require(len(cases) == 1408, "Independent oracle corpus is incomplete")
    corpus_hash = hashlib.sha256(oracle.stdout.encode()).hexdigest()
    require(corpus_hash == CORPUS_SHA256, "Trusted oracle corpus changed; inspect and explicitly update its pinned hash")
    requests = [dict(op="compare", kind="js", a=c["a"], b=c["b"], rootA=c["rootA"], rootB=c["rootB"]) for c in cases]
    payload = "".join(json.dumps(r)+"\n" for r in requests)
    profiles = {}
    for profile in ["debug","release"]:
        command = ["rtk", "proxy", "cargo", "build", "--locked", "-p", "compare-core", "--example", "json_lines"]
        if profile == "release": command.append("--release")
        subprocess.run(command, cwd=ROOT, check=True, timeout=300)
        binary = ROOT/"target"/profile/"examples/json_lines"
        binary_hash = hashlib.sha256(binary.read_bytes()).hexdigest()
        response = subprocess.run(["rtk", "proxy", str(binary)], input=payload, cwd=ROOT,
                                  capture_output=True, text=True, check=True, timeout=60)
        measured = validate_cases(cases,response.stdout.splitlines())
        require(all(count > 0 for count in measured["statusCounts"].values()), "Trusted corpus omitted a comparable status")
        require(hashlib.sha256(binary.read_bytes()).hexdigest() == binary_hash, "Oracle binary changed during verification")
        profiles[profile] = measured | {"binarySHA256":binary_hash}
    versions = {}
    for tool in ["node","rustc","cargo"]:
        versions[tool] = subprocess.run(["rtk","proxy",tool,"--version"],cwd=ROOT,capture_output=True,
                                        text=True,check=True,timeout=30).stdout.strip()
        require(bool(versions[tool]),"Missing tool version: "+tool)
    evidence = {"seed":f"{SEED:x}","trustedTemplates":11,"cases":len(cases),
                "profiles":profiles,"toolVersions":versions,"generatedCorpusSHA256":corpus_hash,
                "oracleSourceSHA256":hashlib.sha256(ORACLE.encode()).hexdigest(),
                "userCodeExecuted":False,"realVaultAccessed":False,"passed":True}
    (ROOT/"build").mkdir(exist_ok=True)
    (ROOT/"build/js-oracle-check.json").write_text(json.dumps(evidence, indent=2)+"\n")
    print("SYNTHETIC_JS_ORACLE_OK " + json.dumps(evidence))


if __name__ == "__main__":
    main()
