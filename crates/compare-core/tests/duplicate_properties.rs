use compare_core::process;
use serde_json::{Value, json};
use std::sync::Mutex;

static SERIAL: Mutex<()> = Mutex::new(());

fn request(fields: Value) -> Value {
    serde_json::from_str(&process(&fields.to_string())).unwrap()
}

fn compare(a: &str, b: &str) -> Value {
    request(json!({"op":"compare","kind":"js","a":a,"b":b,"session":"duplicate-property-contract"}))
}

#[test]
fn duplicates_keep_final_values_and_report_safe_utf8_locations() {
    let _serial = SERIAL.lock().unwrap_or_else(|failure| failure.into_inner());
    let a = "\u{feff}var env={\r\n  '中文': 1,\r\n  ['中文']: 2,\r\n  '\\u4e2d\\u6587': 3\r\n};";
    let result = compare(a, "var env={中文:3};");
    assert_eq!(result["ok"], true);
    assert_eq!(result["complete"], true);
    assert_eq!(result["summary"]["same"], 1);
    let warnings = result["warnings"]
        .as_array()
        .expect("source warnings missing");
    assert_eq!(warnings.len(), 2);
    assert_eq!(warnings[0]["side"], "A");
    assert_eq!(warnings[0]["code"], "JS_DUPLICATE_PROPERTY");
    assert_eq!(warnings[0]["line"], 3);
    assert_eq!(warnings[0]["column"], 3);
    assert_eq!(warnings[0]["previousLine"], 2);
    assert_eq!(warnings[0]["previousColumn"], 3);
    assert_eq!(warnings[1]["line"], 4);
    assert_eq!(warnings[1]["previousLine"], 3);
    assert!(!serde_json::to_string(warnings).unwrap().contains("中文"));
    let unicode_prefix = compare(
        "var env={emoji:'😀', 'a':1, a:2};",
        "var env={emoji:'😀',a:2};",
    );
    assert_eq!(unicode_prefix["warnings"][0]["column"], 31);
}

#[test]
fn definition_identity_is_decoded_and_spread_overwrites_are_separate() {
    let _serial = SERIAL.lock().unwrap_or_else(|failure| failure.into_inner());
    for (a, b, count) in [
        ("var env={1:1,'1':2,[1]:3};", "var env={1:3};", 2),
        (
            "var env={'\\ud800':1,['\\ud800']:2};",
            "var env={'\\ud800':2};",
            1,
        ),
        ("var base={a:1};var env={...base,a:2};", "var env={a:2};", 0),
        (
            "var base={a:9};var env={a:1,...base,a:2};",
            "var env={a:2};",
            1,
        ),
        (
            "var env={nested:{a:1,a:2},items:[{a:3,a:4}]};",
            "var env={nested:{a:2},items:[{a:4}]};",
            2,
        ),
    ] {
        let result = compare(a, b);
        assert_eq!(result["ok"], true, "{result}");
        assert_eq!(result["complete"], true);
        assert_eq!(result["summary"]["valueChanged"], 0);
        assert_eq!(result["warnings"].as_array().unwrap().len(), count);
    }
}

#[test]
fn warnings_are_source_metadata_and_survive_filters_without_values() {
    let _serial = SERIAL.lock().unwrap_or_else(|failure| failure.into_inner());
    let result = compare("var env={x:'synthetic-secret',x:2};", "var env={x:0,x:2};");
    assert_eq!(result["warnings"].as_array().unwrap().len(), 2);
    assert_eq!(result["warnings"][1]["side"], "B");
    let report = request(
        json!({"op":"report","session":"duplicate-property-contract","includeValues":false,"filter":"differences"}),
    );
    assert_eq!(report["rows"].as_array().unwrap().len(), 0);
    assert_eq!(report["complete"], true);
    assert_eq!(report["warnings"], result["warnings"]);
    assert!(!report.to_string().contains("synthetic-secret"));
    let json = request(
        json!({"op":"compare","kind":"json","a":"{}","b":"{}","session":"duplicate-property-contract"}),
    );
    assert_eq!(json["warnings"], json!([]));
}

#[test]
fn inspection_reports_source_level_warnings_and_full_report_is_not_page_limited() {
    let _serial = SERIAL.lock().unwrap_or_else(|failure| failure.into_inner());
    let source = format!(
        "var other={{k:1,k:2}};var env={{{}}};",
        vec!["x:2"; 301].join(",")
    );
    let inspected = request(json!({"op":"inspectJs","source":source}));
    assert_eq!(inspected["ok"], true);
    assert_eq!(inspected["warnings"].as_array().unwrap().len(), 200);
    assert_eq!(inspected["warningCount"], 301);
    assert!(inspected["warnings"][0].get("side").is_none());
    let result = compare(&source, "var env={x:2};");
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["warnings"].as_array().unwrap().len(), 200);
    assert_eq!(result["warningCount"], 301);
    for fields in [
        json!({"op":"report","session":"duplicate-property-contract","includeValues":false,"limit":1,"filter":"differences"}),
        json!({"op":"report","session":"duplicate-property-contract","includeValues":false,"format":"csv"}),
    ] {
        let report = request(fields);
        assert_eq!(report["warningCount"], 301);
        if report.get("text").is_some() {
            assert!(report.get("warnings").is_none());
        } else {
            assert_eq!(report["warnings"].as_array().unwrap().len(), 301);
        }
    }
}
