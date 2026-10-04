//! Reproducible synthetic quality matrix. No user code is ever executed.
use compare_core::process;
use serde_json::{Value, json};
use std::collections::BTreeMap;
use std::sync::Mutex;

static SERIAL: Mutex<()> = Mutex::new(());
const SEED: u64 = 0x5e_2026_1003;
struct Random(u64);
impl Random {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn scalar(&mut self) -> Value {
        match self.next() % 4 {
            0 => Value::Null,
            1 => json!(self.next().is_multiple_of(2)),
            2 => json!((self.next() % 200) as i64 - 100),
            _ => json!(
                [
                    "plain", "汉字", "😀", "é", "e\u{301}", "a\nb", "=SUM(1)", ""
                ][self.next() as usize % 8]
            ),
        }
    }
}
fn request(value: Value) -> Value {
    serde_json::from_str(&process(&value.to_string())).expect("core must return JSON")
}
fn compare(a: &str, b: &str, kind: &str) -> Value {
    let result = request(json!({"op":"compare","kind":kind,"a":a,"b":b,"session":"quality"}));
    assert_eq!(
        result["ok"], true,
        "seed={SEED:x}, a={a}, b={b}, result={result}"
    );
    result
}
fn scalar_kind(value: &Value) -> &'static str {
    match value {
        Value::Null => "Null",
        Value::Bool(_) => "Boolean",
        Value::Number(_) => "Number",
        Value::String(_) => "String",
        _ => panic!("oracle is intentionally limited to independent scalar cases"),
    }
}

#[test]
fn seeded_scalar_oracle_symmetry_and_determinism_600_pairs() {
    let _guard = SERIAL.lock().unwrap();
    let mut random = Random(SEED);
    for iteration in 0..600 {
        let mut a = BTreeMap::new();
        let mut b = BTreeMap::new();
        for i in 0..40 {
            let key = format!("k{i:02}");
            if !random.next().is_multiple_of(4) {
                a.insert(key.clone(), random.scalar());
            }
            if !random.next().is_multiple_of(4) {
                b.insert(key, random.scalar());
            }
        }
        let a_text = serde_json::to_string(&a).unwrap();
        let b_text = serde_json::to_string(&b).unwrap();
        let actual = compare(&a_text, &b_text, "json");
        let again = compare(&a_text, &b_text, "json");
        assert_eq!(actual, again, "iteration={iteration}, seed={SEED:x}");
        let reversed = compare(&b_text, &a_text, "json");
        let expected: BTreeMap<_, _> = a
            .keys()
            .chain(b.keys())
            .map(|key| {
                let status = match (a.get(key), b.get(key)) {
                    (Some(_), None) => "ONLY_A",
                    (None, Some(_)) => "ONLY_B",
                    (Some(x), Some(y)) if scalar_kind(x) != scalar_kind(y) => "TYPE_CHANGED",
                    (Some(x), Some(y)) if x == y => "SAME",
                    (Some(_), Some(_)) => "VALUE_CHANGED",
                    _ => unreachable!(),
                };
                (format!("$.{key}"), status)
            })
            .collect();
        let rows = actual["rows"].as_array().unwrap();
        assert_eq!(rows.len(), expected.len());
        assert_eq!(actual["summary"]["total"], expected.len());
        assert_eq!(actual["complete"], true);
        for (row, reverse) in rows.iter().zip(reversed["rows"].as_array().unwrap()) {
            let status = expected[row["path"].as_str().unwrap()];
            assert_eq!(row["status"], status, "iteration={iteration}");
            let inverted = match status {
                "ONLY_A" => "ONLY_B",
                "ONLY_B" => "ONLY_A",
                _ => status,
            };
            assert_eq!(reverse["status"], inverted);
            assert_eq!(row["path"], reverse["path"]);
            assert_eq!(row["a"], reverse["b"]);
            assert_eq!(row["b"], reverse["a"]);
        }
        for (status, field) in [
            ("SAME", "same"),
            ("VALUE_CHANGED", "valueChanged"),
            ("TYPE_CHANGED", "typeChanged"),
            ("ONLY_A", "onlyA"),
            ("ONLY_B", "onlyB"),
        ] {
            assert_eq!(
                actual["summary"][field],
                expected.values().filter(|s| **s == status).count()
            );
        }
    }
}

#[test]
fn multiple_variables_recurse_through_objects_arrays_and_distinct_key_paths() {
    let _guard = SERIAL.lock().unwrap();
    let a = r#"var env={api:{timeout:30,retries:{max:3,enabled:true}},servers:[{host:'a',tls:{enabled:true}},{host:'b',tls:{enabled:false}}],shape:{inner:{flag:true}},empty:{}};
var happy={options:{cache:{enabled:true,ttl:60},api:{timeout:30}},labels:{'a.b':{value:1},a:{b:{value:9}}}};"#;
    let b = r#"var happy={labels:{a:{b:{value:9}},'a.b':{value:2}},options:{api:{timeout:30},cache:{grace:7,enabled:true}}};
var env={empty:{},shape:'disabled',servers:[{tls:{enabled:false},host:'a'},{tls:{enabled:false},host:'b'}],api:{retries:{enabled:true,max:'3'},timeout:45}};"#;
    let expected = BTreeMap::from([
        ("$.env.api.timeout", "VALUE_CHANGED"),
        ("$.env.api.retries.max", "TYPE_CHANGED"),
        ("$.env.api.retries.enabled", "SAME"),
        ("$.env.servers[0].host", "SAME"),
        ("$.env.servers[0].tls.enabled", "VALUE_CHANGED"),
        ("$.env.servers[1].host", "SAME"),
        ("$.env.servers[1].tls.enabled", "SAME"),
        ("$.env.shape", "TYPE_CHANGED"),
        ("$.env.empty", "SAME"),
        ("$.happy.options.cache.enabled", "SAME"),
        ("$.happy.options.cache.ttl", "ONLY_A"),
        ("$.happy.options.cache.grace", "ONLY_B"),
        ("$.happy.options.api.timeout", "SAME"),
        ("$.happy.labels[\"a.b\"].value", "VALUE_CHANGED"),
        ("$.happy.labels.a.b.value", "SAME"),
    ]);
    for (left, right, reverse) in [(a, b, false), (b, a, true)] {
        let result = request(
            json!({"op":"compare","kind":"js","a":left,"b":right,"rootA":"*","rootB":"*","session":"quality"}),
        );
        assert_eq!(result["ok"], true);
        assert_eq!(result["complete"], true);
        assert_eq!(
            result["summary"],
            json!({"total":15,"same":8,"valueChanged":3,"typeChanged":2,"onlyA":1,"onlyB":1,"notComparable":0,"differences":7})
        );
        let actual: BTreeMap<_, _> = result["rows"]
            .as_array()
            .unwrap()
            .iter()
            .map(|row| {
                (
                    row["path"].as_str().unwrap(),
                    row["status"].as_str().unwrap(),
                )
            })
            .collect();
        let statuses: BTreeMap<_, _> = expected
            .iter()
            .map(|(path, status)| {
                (
                    *path,
                    match (*status, reverse) {
                        ("ONLY_A", true) => "ONLY_B",
                        ("ONLY_B", true) => "ONLY_A",
                        _ => *status,
                    },
                )
            })
            .collect();
        assert_eq!(actual, statuses);
        assert_eq!(result["rows"].as_array().unwrap().len(), expected.len());
    }
}

#[test]
fn unknown_deep_leaf_in_one_variable_preserves_known_sibling_results() {
    let _guard = SERIAL.lock().unwrap();
    let result = request(json!({"op":"compare","kind":"js","rootA":"*","rootB":"*",
        "a":"var env={api:{timeout:30}};var happy={options:{cache:{enabled:outside},retry:{max:3}}};",
        "b":"var env={api:{timeout:30}};var happy={options:{cache:{enabled:true},retry:{max:4}}};"}));
    assert_eq!(result["ok"], true);
    assert_eq!(result["complete"], false);
    assert_eq!(result["summary"]["total"], 3);
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["valueChanged"], 1);
    assert_eq!(result["summary"]["notComparable"], 1);
    let statuses: BTreeMap<_, _> = result["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| {
            (
                row["path"].as_str().unwrap(),
                row["status"].as_str().unwrap(),
            )
        })
        .collect();
    assert_eq!(
        statuses,
        BTreeMap::from([
            ("$.env.api.timeout", "SAME"),
            ("$.happy.options.cache.enabled", "NOT_COMPARABLE"),
            ("$.happy.options.retry.max", "VALUE_CHANGED"),
        ])
    );
    assert!(!result["incompleteRanges"].as_array().unwrap().is_empty());
}

#[test]
fn nested_key_order_array_order_and_empty_container_matrix() {
    let _guard = SERIAL.lock().unwrap();
    let ordered = r#"{"one":{"a":1,"b":{"x":"汉字","y":null}},"two":[{"c":true,"d":[]},{}]}"#;
    let reordered = r#"{"two":[{"d":[],"c":true},{}],"one":{"b":{"y":null,"x":"汉字"},"a":1}}"#;
    let same = compare(ordered, reordered, "json");
    assert_eq!(same["summary"]["same"], 6);
    assert_eq!(same["summary"]["differences"], 0);
    for (a, b, field, count) in [
        (r#"{"x":{}}"#, r#"{"x":[]}"#, "typeChanged", 1),
        (r#"{"x":[1,2]}"#, r#"{"x":[2,1]}"#, "valueChanged", 2),
        (r#"{"x":null}"#, r#"{}"#, "onlyA", 1),
        (r#"{"x":null}"#, r#"{"x":""}"#, "typeChanged", 1),
    ] {
        assert_eq!(compare(a, b, "json")["summary"][field], count);
    }
}

#[test]
fn decimal_scale_equivalence_and_utf16_paths_1000_cases() {
    let _guard = SERIAL.lock().unwrap();
    for n in 1..=1000 {
        let a = format!("{{\"n\":{n}e2}}");
        let b = format!("{{\"n\":{n}00.000}}");
        assert_eq!(compare(&a, &b, "json")["summary"]["same"], 1);
    }
    let result = compare(
        r#"{"a.b":1,"a/b":2,"":3,"\ud800":4,"\ufffd":5,"é":6,"e\u0301":7}"#,
        "{}",
        "json",
    );
    assert_eq!(result["summary"]["onlyA"], 7);
    let rows = result["rows"].as_array().unwrap();
    let mut paths: Vec<_> = rows.iter().map(|r| r["segments"].to_string()).collect();
    paths.sort();
    paths.dedup();
    assert_eq!(paths.len(), 7);
    let report = request(json!({"op":"report","session":"quality","includeValues":true}));
    assert!(report.to_string().contains("55296"));
}

#[test]
fn typed_js_special_values_aliases_exports_and_relative_roots() {
    let _guard = SERIAL.lock().unwrap();
    let src = "var env={zero:-0,nan:NaN,pos:Infinity,neg:-Infinity,big:9007199254740993n,missing:undefined,hole:[,]};";
    let same = compare(src, src, "js");
    assert_eq!(same["summary"]["same"], 7);
    let changed = compare(
        src,
        "var env={zero:0,nan:null,pos:1,neg:-1,big:9007199254740993,missing:null,hole:[undefined]};",
        "js",
    );
    assert_eq!(changed["summary"]["same"], 0);
    assert_eq!(changed["summary"]["valueChanged"], 3);
    assert_eq!(changed["summary"]["typeChanged"], 4);
    for (a, b) in [
        ("var env={a:1};var alias=env;alias.a=2;", "var env={a:2};"),
        (
            "var env={a:1};module.exports=env;exports={b:2};",
            "var env={a:1};module.exports=env;",
        ),
        (
            "var x=1;var env={x,...{x:2,y:3},y:4};",
            "var env={x:2,y:4};",
        ),
    ] {
        assert_eq!(compare(a, b, "js")["summary"]["differences"], 0);
    }
    let paired = request(
        json!({"op":"compare","kind":"js","a":"const alpha={nested:{x:1}};","b":"let beta={nested:{x:1}};","rootA":"alpha","rootB":"beta"}),
    );
    assert_eq!(paired["summary"]["same"], 1);
    assert_eq!(paired["rows"][0]["path"], "$.nested.x");
}

#[test]
fn pagination_details_redaction_and_filters_preserve_summary() {
    let _guard = SERIAL.lock().unwrap();
    let values: BTreeMap<_, _> = (0..450)
        .map(|n| {
            (
                format!("k{n:03}"),
                json!(format!("private-{n}-{}", "x".repeat(300))),
            )
        })
        .collect();
    let text = serde_json::to_string(&values).unwrap();
    let result = compare(&text, "{}", "json");
    assert_eq!(result["summary"]["total"], 450);
    assert_eq!(result["rows"].as_array().unwrap().len(), 200);
    assert_eq!(result["rows"][0]["a"]["truncated"], true);
    let mut ids = vec![];
    for offset in [0, 200, 400] {
        let page = request(
            json!({"op":"report","session":"quality","offset":offset,"limit":200,"includeValues":false}),
        );
        assert_eq!(page["summary"], result["summary"]);
        assert!(!page.to_string().contains("private-"));
        ids.extend(
            page["rows"]
                .as_array()
                .unwrap()
                .iter()
                .map(|r| r["id"].as_u64().unwrap()),
        );
    }
    assert_eq!(ids, (0..450).collect::<Vec<_>>());
    let detail = request(json!({"op":"details","session":"quality","id":449}));
    assert_eq!(
        detail["row"]["a"]["units"].as_array().unwrap().len(),
        "private-449-".len() + 300
    );
    let filtered =
        request(json!({"op":"rows","session":"quality","search":"private-449-","searchScope":"a"}));
    assert_eq!(filtered["matched"], 1);
    assert_eq!(filtered["rows"][0]["id"], 449);
}

#[test]
fn yaml_style_duplicate_and_idempotency_matrix() {
    let _guard = SERIAL.lock().unwrap();
    let sources = [
        "# header\na:  '001' # inline\nb: \"true\"\n",
        "base: &base {port:  3000}\ncopy: *base\n---\nx: !custom '001'\n",
        "literal: |+\n  first\n  second\n\nfold: >-\n  alpha\n  beta\n",
        "items:\n  - {x:  1, y: 'a#b'}\n  - null\n",
        "# header\r\na:  1\r\nb: 'two'\r\n",
    ];
    for indent in [2, 4] {
        for source in sources {
            let formatted = request(json!({"op":"formatYaml","source":source,"indent":indent}));
            assert_eq!(formatted["ok"], true, "{source}: {formatted}");
            let again =
                request(json!({"op":"formatYaml","source":formatted["text"],"indent":indent}));
            assert_eq!(again["text"], formatted["text"]);
        }
    }
    for source in [
        "a: 1\n'a': 2\n",
        "x: {a: 1, a: 2}\n",
        "1: x\n",
        "true: x\n",
        "? [a, b]\n: x\n",
        "a: *absent\n",
        "a: [1,2\n",
    ] {
        let result = request(json!({"op":"formatYaml","source":source}));
        assert_eq!(result["ok"], false, "{source}: {result}");
        assert!(result.get("text").is_none());
    }
}

#[test]
fn deterministic_parser_mutation_corpus_2400_cases() {
    let _guard = SERIAL.lock().unwrap();
    let bases = [
        ("json", r#"{"a":[1,true,null],"b":{"x":"汉字"}}"#),
        ("js", "var env={a:[1,,3],b:'text'};module.exports=env;"),
        ("yaml", "a: [1, 2]\nb: &x 'quoted'\nc: *x\n"),
    ];
    let alphabet = [
        '{', '}', ':', ',', '[', ']', '\'', '"', '\\', '\0', '\n', '\r', '\u{2028}', '汉', '0',
        '/', '*', '?', 'a',
    ];
    let mut random = Random(SEED);
    for (kind, base) in bases {
        for iteration in 0..800 {
            let mut input: Vec<char> = base.chars().collect();
            for _ in 0..1 + random.next() % 6 {
                let index = random.next() as usize % (input.len() + 1);
                if random.next().is_multiple_of(3) && index < input.len() {
                    input.remove(index);
                } else {
                    input.insert(index, alphabet[random.next() as usize % alphabet.len()]);
                }
            }
            let source: String = input.into_iter().collect();
            let args = if kind == "yaml" {
                json!({"op":"formatYaml","source":source})
            } else {
                json!({"op":"compare","kind":kind,"a":source,"b":if kind=="js" {"var env={};"} else {"{}"}})
            };
            let result = request(args);
            assert!(
                result["ok"].is_boolean(),
                "kind={kind}, iteration={iteration}, seed={SEED:x}"
            );
            assert_ne!(
                result["error"]["code"], "WORKER_INTERRUPTED",
                "kind={kind}, iteration={iteration}, source={source:?}"
            );
        }
    }
}
