//! Dedicated user-scope cases. Inputs and expectations are synthetic, never executed.
use compare_core::process;
use serde_json::{Value, json};

fn request(value: Value) -> Value {
    serde_json::from_str(&process(&value.to_string())).unwrap()
}

fn compare_js(a: &str, b: &str) -> Value {
    let result = request(json!({"op":"compare","kind":"js","a":a,"b":b}));
    assert_eq!(result["ok"], true, "{result}");
    result
}

fn compare_all(a: &str, b: &str) -> Value {
    let result = request(json!({"op":"compare","kind":"js","a":a,"b":b,"rootA":"*","rootB":"*"}));
    assert_eq!(result["ok"], true, "{result}");
    result
}

#[test]
fn whole_file_retains_independent_commonjs_exports() {
    for (a, b, path, status) in [
        (
            "module.exports={PORT:3000};",
            "module.exports={PORT:4000};",
            "$[\"module.exports\"].PORT",
            "VALUE_CHANGED",
        ),
        (
            "exports.PORT=3000;",
            "exports.PORT=4000;",
            "$[\"module.exports\"].PORT",
            "VALUE_CHANGED",
        ),
        (
            "var env={x:1};module.exports={x:1,extra:5};",
            "var env={x:1};module.exports={x:1};",
            "$[\"module.exports\"].extra",
            "ONLY_A",
        ),
        (
            "module.exports={};",
            "module.exports={PORT:4000};",
            "$[\"module.exports\"].PORT",
            "ONLY_B",
        ),
        (
            "exports.PORT=1;delete exports.PORT;",
            "exports.PORT=4000;",
            "$[\"module.exports\"].PORT",
            "ONLY_B",
        ),
        (
            "module.exports=3;",
            "module.exports='3';",
            "$[\"module.exports\"]",
            "TYPE_CHANGED",
        ),
    ] {
        let result = compare_all(a, b);
        assert_eq!(result["complete"], true, "{result}");
        assert_eq!(result["summary"]["differences"], 1, "{result}");
        assert!(
            result["rows"]
                .as_array()
                .unwrap()
                .iter()
                .any(|row| row["path"] == path && row["status"] == status),
            "{result}"
        );
    }
}

#[test]
fn whole_file_export_alias_dedup_uses_identity_not_equal_values() {
    for (a, b, total) in [
        ("var env={x:1};", "var env={x:2};", 1),
        (
            "var env={x:1};module.exports=env;",
            "var env={x:2};module.exports=env;",
            1,
        ),
        (
            "var env={x:1};var happy=env;module.exports=env;",
            "var env={x:2};var happy=env;module.exports=env;",
            2,
        ),
        (
            "var env={x:1};module.exports={x:1};",
            "var env={x:2};module.exports={x:2};",
            2,
        ),
        (
            "var env={x:1};module.exports=env;env={x:10};",
            "var env={x:2};module.exports=env;env={x:10};",
            2,
        ),
    ] {
        let result = compare_all(a, b);
        assert_eq!(result["summary"]["total"], total, "{result}");
        assert_eq!(result["complete"], true, "{result}");
    }
    let rebound = compare_all(
        "var env={x:1};module.exports=env;env={x:10};",
        "var env={x:2};module.exports=env;env={x:10};",
    );
    assert_eq!(rebound["summary"]["valueChanged"], 1, "{rebound}");
}

#[test]
fn whole_file_preserves_unknown_export_fields() {
    let result = compare_all(
        "var env={x:1};module.exports={unknown:y};",
        "var env={x:1};module.exports={unknown:y};",
    );
    assert_eq!(result["complete"], false);
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["notComparable"], 1, "{result}");
}

#[test]
fn export_alias_on_one_side_does_not_create_false_missing_rows() {
    for (a, b) in [
        (
            "var env={x:1};module.exports=env;",
            "var env={x:1};module.exports={x:1};",
        ),
        (
            "var env={x:1};module.exports={x:1};",
            "var env={x:1};module.exports=env;",
        ),
    ] {
        let result = compare_all(a, b);
        assert_eq!(result["summary"]["differences"], 0, "{result}");
        assert_eq!(result["summary"]["total"], 2, "{result}");
        assert_eq!(result["summary"]["same"], 2, "{result}");
    }
}

#[test]
fn unbound_shorthand_is_unknown_with_a_specific_diagnostic() {
    let source = "var env={missing,known:1};";
    let result = compare_js(source, source);
    assert_eq!(result["complete"], false);
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["notComparable"], 1);
    let row = result["rows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["path"] == "$.missing")
        .unwrap();
    assert_eq!(row["status"], "NOT_COMPARABLE");
    assert_eq!(row["a"]["type"], "Unknown");
    assert!(
        result["incompleteRanges"]
            .as_array()
            .unwrap()
            .iter()
            .any(|v| v.as_str().unwrap().contains("missing"))
    );
}

#[test]
fn nested_scope_never_creates_a_top_level_root_or_preserves_a_false_same() {
    for source in [
        "var env={x:1};{let env={x:2};let privateRoot={x:3};}",
        "var env={x:1};function f(){var env={x:2};var privateRoot={x:3};}",
    ] {
        let roots = request(json!({"op":"inspectJs","source":source}));
        assert_eq!(roots["ok"], true);
        assert_eq!(roots["complete"], false);
        assert!(
            !roots["roots"]
                .as_array()
                .unwrap()
                .contains(&json!("privateRoot"))
        );
        let result = compare_js(source, "var env={x:1};");
        assert_eq!(result["summary"]["same"], 0);
        assert_eq!(result["complete"], false);
        let bad_root = request(
            json!({"op":"compare","kind":"js","a":source,"b":source,"rootA":"privateRoot","rootB":"privateRoot"}),
        );
        assert_eq!(bad_root["error"]["code"], "ROOT_NOT_FOUND");
    }
}

#[test]
fn fresh_object_after_unknown_call_can_prove_values_but_not_program_completeness() {
    let result = compare_js(
        "unknownCall();var env={safe:1,nested:{label:'local'}};",
        "var env={safe:1,nested:{label:'local'}};",
    );
    assert_eq!(result["summary"]["same"], 2);
    assert_eq!(result["summary"]["differences"], 0);
    assert_eq!(result["summary"]["notComparable"], 0);
    assert_eq!(result["complete"], false);
    assert!(!result["incompleteRanges"].as_array().unwrap().is_empty());
}

#[test]
fn bom_crlf_and_chinese_keep_value_positions_in_utf8_byte_columns() {
    for newline in ["\n", "\r\n"] {
        let source = format!("\u{feff}var env={{{newline}中文:'值',number:1{newline}}};");
        let result = compare_js(&source, "var env={中文:'值',number:1};");
        assert_eq!(result["summary"]["same"], 2);
        let row = result["rows"]
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["path"].as_str().unwrap().contains("中文"))
            .unwrap();
        assert_eq!(row["a"]["line"], 2);
        assert_eq!(row["a"]["column"], 8); // two Chinese characters (6 bytes) + colon
        assert_eq!(row["a"]["display"], "\"值\"");
    }
}

#[test]
fn leading_bom_is_ignored_for_values_but_counted_in_original_first_line_positions() {
    let js = compare_js("\u{feff}var env={中文:'值'};", "var env={中文:'值'};");
    assert_eq!(js["summary"]["same"], 1);
    assert_eq!(js["rows"][0]["a"]["line"], 1);
    assert_eq!(js["rows"][0]["a"]["column"], 20);
    assert_eq!(js["rows"][0]["b"]["column"], 17);
    let json = request(
        json!({"op":"compare","kind":"json","a":"\u{feff}{\"中文\":1}","b":"{\"中文\":1}"}),
    );
    assert_eq!(json["summary"]["same"], 1);
    assert_eq!(json["rows"][0]["a"]["column"], 14);
    assert_eq!(json["rows"][0]["b"]["column"], 11);
    let invalid = request(json!({"op":"compare","kind":"json","a":"\u{feff}{\"中文\":}","b":"{}"}));
    assert_eq!(invalid["error"]["code"], "JSON_PARSE_ERROR");
    assert_eq!(invalid["error"]["line"], 1);
    assert_eq!(invalid["error"]["column"], 14);
}

#[test]
fn business_data_data_remains_in_plain_object_and_mixed_kv_versions_are_explicit() {
    let a = r#"{"data":{"data":{"PORT":1},"metadata":{"version":1}}}"#;
    let b = r#"{"data":{"data":{"PORT":2},"metadata":{"version":2}}}"#;
    let plain =
        request(json!({"op":"compare","kind":"json","a":a,"b":b,"inputType":"plain-object"}));
    assert_eq!(plain["summary"]["valueChanged"], 2);
    assert_eq!(plain["rows"][0]["path"], "$.data.data.PORT");
    assert_eq!(plain["rows"][1]["path"], "$.data.metadata.version");
    let mixed = request(
        json!({"op":"compare","kind":"json","a":r#"{"data":{"PORT":1}}"#,"b":a,"inputTypeA":"kv-v1-response","inputTypeB":"kv-v2-response"}),
    );
    assert_eq!(mixed["ok"], true);
    assert_eq!(mixed["summary"]["same"], 1);
    assert_eq!(mixed["rows"][0]["path"], "$.PORT");
}

#[test]
fn path_map_uses_exact_keys_and_does_not_claim_vault_inventory_completeness() {
    let result = request(
        json!({"op":"compare","kind":"json","inputType":"path-map","a":r#"{"service/config":{"x":1},"other/config":{"x":2}}"#,"b":r#"{"service/config":{"x":1}}"#}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["onlyA"], 1);
    assert_eq!(result["rows"][0]["path"], "$[\"other/config\"]");
    // `complete` describes this supplied tree, not any live Vault deployment.
    assert_eq!(result["complete"], true);
    for (source, expected) in [
        (r#"{"":{"x":1}}"#, "IMPORT_SCHEMA_INVALID"),
        (r#"{"auth":null}"#, "IMPORT_SCHEMA_INVALID"),
        (r#"{"auth":[]}"#, "IMPORT_SCHEMA_INVALID"),
        (r#"{"auth":1}"#, "IMPORT_SCHEMA_INVALID"),
        (r#"{"auth":{ "x":1,"\u0078":2 }}"#, "JSON_DUPLICATE_KEY"),
        (r#"{"auth":{},"auth":{}}"#, "JSON_DUPLICATE_KEY"),
        (r#"{"scope":"**","entries":[]}"#, "IMPORT_SCHEMA_INVALID"),
        ("[]", "IMPORT_SCHEMA_INVALID"),
    ] {
        let invalid = request(
            json!({"op":"compare","kind":"json","inputType":"path-map","a":source,"b":"{}"}),
        );
        assert_eq!(invalid["ok"], false, "{source}: {invalid}");
        assert_eq!(invalid["error"]["code"], expected);
        assert!(invalid.get("summary").is_none() && invalid.get("rows").is_none());
    }
}

#[test]
fn invalid_kv_wrappers_deleted_data_and_duplicates_fail_whole_input() {
    for (format, source, expected) in [
        ("plain-object", "null", "NO_COMPARABLE_CONTENT"),
        ("kv-v1-response", "{}", "IMPORT_SCHEMA_INVALID"),
        (
            "kv-v1-response",
            r#"{"data":null}"#,
            "NO_COMPARABLE_CONTENT",
        ),
        (
            "kv-v2-response",
            r#"{"data":{"metadata":{"destroyed":true}}}"#,
            "IMPORT_SCHEMA_INVALID",
        ),
        (
            "kv-v2-response",
            r#"{"data":{"data":null,"metadata":{"deletion_time":"synthetic"}}}"#,
            "NO_COMPARABLE_CONTENT",
        ),
        (
            "kv-v2-response",
            r#"{"data":{"data":{},"metadata":{"version":1,"version":2}}}"#,
            "JSON_DUPLICATE_KEY",
        ),
        (
            "kv-v1-response",
            r#"{"data":{},"\u0064ata":{}}"#,
            "JSON_DUPLICATE_KEY",
        ),
        ("guess", "{}", "IMPORT_SCHEMA_INVALID"),
    ] {
        let result = request(
            json!({"op":"compare","kind":"json","a":source,"b":"{}","inputTypeA":format,"inputTypeB":"plain-object"}),
        );
        assert_eq!(result["ok"], false, "{format}, {source}: {result}");
        assert_eq!(result["error"]["code"], expected);
        assert!(result.get("summary").is_none() && result.get("rows").is_none());
    }
}
