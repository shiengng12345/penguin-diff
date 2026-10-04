use compare_core::process;
use serde_json::{Value, json};

fn request(value: Value) -> Value {
    serde_json::from_str(&process(&value.to_string())).unwrap()
}

#[test]
fn compares_reordered_json_without_false_differences() {
    let result = request(
        json!({"op":"compare","kind":"json","a":"{\"a\":1,\"c\":3}","b":"{\"c\":3,\"a\":1}","inputType":"plain-object"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["same"], 2);
    assert_eq!(result["summary"]["differences"], 0);
    assert_eq!(result["complete"], true);
}

#[test]
fn distinguishes_json_types_missing_and_large_numbers() {
    let result = request(
        json!({"op":"compare","kind":"json","a":"{\"port\":3000,\"x\":null,\"big\":9007199254740993}","b":"{\"port\":\"3000\",\"big\":9007199254740992}","inputType":"plain-object"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["typeChanged"], 1);
    assert_eq!(result["summary"]["onlyA"], 1);
    assert_eq!(result["summary"]["valueChanged"], 1);
}

#[test]
fn rejects_duplicate_json_keys_instead_of_overwriting() {
    let result = request(
        json!({"op":"compare","kind":"json","a":"{\"a\":1,\"\\u0061\":2}","b":"{}","inputType":"plain-object"}),
    );
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"]["code"], "JSON_DUPLICATE_KEY");
}

#[test]
fn unwraps_vault_only_when_user_selects_the_format() {
    let result = request(
        json!({"op":"compare","kind":"json","a":"{\"data\":{\"data\":{\"PORT\":1},\"metadata\":{\"version\":1}}}","b":"{\"data\":{\"data\":{\"PORT\":1},\"metadata\":{\"version\":2}}}","inputType":"kv-v2-response"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["differences"], 0);
    assert_eq!(result["summary"]["same"], 1);
}

#[test]
fn js_sample_has_the_hand_checked_seven_results() {
    let a = "var devConfig={DEBUG:true};var env={a:1,b:2,c:3,port:3000,redis:{host:'cache-a',port:6379}};module.exports=env;";
    let b = "var devConfig={DEBUG:false};var env={redis:{port:6379,host:'cache-b'},port:'3000',c:30,a:1,d:4};module.exports=env;";
    let result =
        request(json!({"op":"compare","kind":"js","a":a,"b":b,"rootA":"env","rootB":"env"}));
    assert_eq!(result["ok"], true);
    assert_eq!(
        result["summary"],
        json!({"total":7,"same":2,"valueChanged":2,"typeChanged":1,"onlyA":1,"onlyB":1,"notComparable":0,"differences":5})
    );
}

#[test]
fn unknown_runtime_expressions_never_become_same() {
    let source = "var env={HOST:getHost(),TOKEN:process.env.API_TOKEN};module.exports=env;";
    let result = request(
        json!({"op":"compare","kind":"js","a":source,"b":source,"rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["same"], 0);
    assert_eq!(result["complete"], false);
}

#[test]
fn yaml_formatter_retains_comments_quotes_and_aliases() {
    let input = "# config\nbase: &base {port:  3000}\ncopy: *base\ntext: '3000' # string\n";
    let result = request(json!({"op":"formatYaml","source":input}));
    assert_eq!(result["ok"], true);
    let output = result["text"].as_str().unwrap();
    assert!(output.contains("# config"));
    assert!(output.contains("# string"));
    assert!(output.contains("&base"));
    assert!(output.contains("*base"));
    assert!(output.contains("'3000'"));
    assert!(!output.contains("port:  3000"));
}

#[test]
fn yaml_formatter_rejects_duplicate_keys() {
    let result = request(json!({"op":"formatYaml","source":"a: 1\na: 2\n"}));
    assert_eq!(result["ok"], false);
    assert_eq!(result["error"]["code"], "YAML_DUPLICATE_KEY");
}

#[test]
fn export_reference_survives_binding_reassignment() {
    let result = request(
        json!({"op":"compare","kind":"js","a":"var env={a:1};module.exports=env;env={a:2};","b":"var env={a:1};module.exports=env;","rootA":"module.exports","rootB":"module.exports"}),
    );
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["complete"], true);
}

#[test]
fn assignment_captures_the_left_reference_before_evaluating_right() {
    let result = request(
        json!({"op":"compare","kind":"js","a":"var env={};var old=env;env.a=(env={n:1});module.exports=old;","b":"var env={a:{n:1}};module.exports=env;","rootA":"module.exports","rootB":"module.exports"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["differences"], 0);
    assert_eq!(result["complete"], true);
}

#[test]
fn delete_removes_an_own_property_without_executing_code() {
    let result = request(
        json!({"op":"compare","kind":"js","a":"var env={a:1,b:2};delete env.a;","b":"var env={b:2};","rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["differences"], 0);
}

#[test]
fn unknown_control_flow_keeps_a_selected_root_as_unknown() {
    let source = "var env={a:1};if(flag){env=other;}env.B=2;module.exports=env;";
    let result = request(
        json!({"op":"compare","kind":"js","a":source,"b":source,"rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["complete"], false);
    assert_eq!(result["summary"]["same"], 0);
}

#[test]
fn unknown_spread_retains_proven_later_value_without_claiming_complete() {
    let source = "var env={...getConfig(),fixed:1};";
    let result = request(
        json!({"op":"compare","kind":"js","a":source,"b":source,"rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["complete"], false);
}

#[test]
fn json_numeric_equivalence_preserves_signed_zero() {
    let result = request(
        json!({"op":"compare","kind":"json","a":"{\"n\":1.0,\"z\":-0}","b":"{\"n\":1e0,\"z\":0}","inputType":"plain-object"}),
    );
    assert_eq!(result["summary"]["same"], 1);
    assert_eq!(result["summary"]["valueChanged"], 1);
}

#[test]
fn lone_surrogates_are_not_replaced_before_comparison() {
    let result = request(
        json!({"op":"compare","kind":"js","a":"var env={x:'\\ud800'};","b":"var env={x:'\\ufffd'};","rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["summary"]["valueChanged"], 1);
}

#[test]
fn unicode_property_paths_use_the_ascii_dot_rule() {
    let source = r#"{"plain":1,"é":2,"中文":3,"e\u0301":4,"a.b":5,"\ud800":6}"#;
    let result = request(json!({"op":"compare","kind":"json","a":source,"b":source}));
    let mut paths = result["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| row["path"].as_str().unwrap().to_owned())
        .collect::<Vec<_>>();
    paths.sort();
    assert_eq!(
        paths,
        vec![
            "$.plain",
            "$[\"\\ud800\"]",
            "$[\"a.b\"]",
            "$[\"e\u{301}\"]",
            "$[\"é\"]",
            "$[\"中文\"]"
        ]
    );
}

#[test]
fn sparse_array_is_distinct_from_undefined() {
    let result = request(
        json!({"op":"compare","kind":"js","a":"var env={x:[,]};","b":"var env={x:[undefined]};","rootA":"env","rootB":"env"}),
    );
    assert_eq!(result["summary"]["same"], 0);
    assert_eq!(result["summary"]["typeChanged"], 1);
}

#[test]
fn opaque_call_can_rebind_a_root_and_must_not_leave_known_rows() {
    let src = "var env={a:1};mutate();";
    let r = request(json!({"op":"compare","kind":"js","a":src,"b":src}));
    assert_eq!(r["summary"]["same"], 0);
    assert_eq!(r["complete"], false);
}
#[test]
fn unsupported_expression_cannot_hide_assignment_side_effects() {
    let src = "var env={a:1};flag && (env.a=2);";
    let r = request(json!({"op":"compare","kind":"js","a":src,"b":src}));
    assert_eq!(r["summary"]["same"], 0);
}
#[test]
fn accessor_properties_are_explicitly_unsupported() {
    let src = "var env={get a(){return 1;}};env.a=2;";
    let r = request(json!({"op":"compare","kind":"js","a":src,"b":src}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "UNSUPPORTED_SEMANTICS");
}
#[test]
fn unknown_subtrees_make_one_sided_container_incomplete() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var env={x:{q:process.env.Q}};","b":"var env={};"}),
    );
    assert_eq!(r["complete"], false);
}

#[test]
fn filtered_report_does_not_reintroduce_values_when_disabled() {
    request(
        json!({"op":"compare","kind":"json","a":"{\"same\":1,\"secret\":\"hide-me\"}","b":"{\"same\":1,\"secret\":\"changed\"}","session":"redacted-report"}),
    );
    let report = request(
        json!({"op":"report","session":"redacted-report","filter":"differences","includeValues":false}),
    );
    assert_eq!(report["rows"].as_array().unwrap().len(), 1);
    assert!(!report.to_string().contains("hide-me"));
    assert!(!report.to_string().contains("changed\\\""));
    assert_eq!(report["rows"][0]["a"]["type"], "String");
}
#[test]
fn csv_report_escapes_formula_keys_and_quotes() {
    request(
        json!({"op":"compare","kind":"json","a":"{\"x\":-42}","b":"{\"x\":42}","session":"csv-test"}),
    );
    let report =
        request(json!({"op":"report","session":"csv-test","format":"csv","includeValues":true}));
    assert!(report["text"].as_str().unwrap().contains("'-42"));
}
#[test]
fn global_mode_matches_named_roots_without_duplicate_export_identity() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var env={x:1};var dev={d:2};module.exports=env;","b":"var dev={d:3};var env={x:1};module.exports=env;","rootA":"*","rootB":"*"}),
    );
    assert_eq!(r["summary"]["same"], 1);
    assert_eq!(r["summary"]["valueChanged"], 1);
}
#[test]
fn readonly_globals_cannot_be_rebound_as_user_variables() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"undefined=1;var env={x:undefined};","b":"var env={x:1};"}),
    );
    assert_eq!(r["ok"], false);
}

#[test]
fn json_allows_non_ascii_control_characters_per_rfc() {
    let r = request(
        json!({"op":"compare","kind":"json","a":"{\"x\":\"\u{0085}\"}","b":"{\"x\":\"\u{0085}\"}"}),
    );
    assert_eq!(r["ok"], true);
    assert_eq!(r["summary"]["same"], 1);
}
#[test]
fn array_length_is_known_and_noncanonical_indexes_are_not_elements() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var xs=[1,2];var env={n:xs.length,x:xs['01']};","b":"var env={n:2,x:undefined};"}),
    );
    assert_eq!(r["summary"]["same"], 2);
    assert_eq!(r["complete"], true);
}

#[test]
fn reading_array_hole_is_undefined_but_own_holes_remain_distinct() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var xs=[,];var env={x:xs[0]};","b":"var env={x:undefined};"}),
    );
    assert_eq!(r["summary"]["same"], 1);
}
#[test]
fn numeric_property_keys_use_ecmascript_spelling() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var env={[1e21]:1,[1e-7]:2};","b":"var env={'1e+21':1,'1e-7':2};"}),
    );
    assert_eq!(r["summary"]["same"], 2);
    assert_eq!(r["summary"]["onlyA"], 0);
}
#[test]
fn lexical_conflicts_and_temporal_dead_zone_are_rejected() {
    for src in [
        "let x=1;var x=2;var env={a:1};",
        "let x=x;var env={a:1};",
        "var env={x};let x=1;",
    ] {
        let r = request(json!({"op":"compare","kind":"js","a":src,"b":"var env={a:1};"}));
        assert_eq!(r["ok"], false, "{src}");
        assert_eq!(r["error"]["code"], "JS_BINDING_ERROR");
    }
}
#[test]
fn var_hoisting_and_empty_redeclaration_preserve_runtime_values() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var before=later;var later=2;var env={x:before,a:1};var env;","b":"var env={x:undefined,a:1};"}),
    );
    assert_eq!(r["summary"]["same"], 2);
    assert_eq!(r["complete"], true);
}
#[test]
fn exponent_budget_has_explicit_resource_error() {
    let r = request(json!({"op":"compare","kind":"json","a":"{\"x\":1e10001}","b":"{}"}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "RESOURCE_LIMIT");
}
#[test]
fn inline_yaml_comments_remain_on_their_own_fields() {
    let r = request(json!({"op":"formatYaml","source":"a:  1 # c1\nb:  2 # c2\n"}));
    assert_eq!(r["ok"], true);
    let out = r["text"].as_str().unwrap();
    assert!(out.contains("a: 1 # c1"));
    assert!(out.contains("b: 2 # c2"));
}

#[test]
fn yaml_aliases_cannot_cross_document_boundaries() {
    let r = request(json!({"op":"formatYaml","source":"a: &x 1\n---\nb: *x\n"}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "YAML_PARSE_ERROR");
}
#[test]
fn yaml_multidocument_block_scalars_tags_and_aliases_survive() {
    let src = "base: &base\n  port:  3000\ncopy: *base\nnote: |\n  first\n  second\n---\nx: !custom '001'\n";
    let r = request(json!({"op":"formatYaml","source":src}));
    assert_eq!(r["ok"], true);
    let out = r["text"].as_str().unwrap();
    assert!(out.contains("!custom '001'"));
    assert!(out.contains("---"));
    assert!(out.contains("first\n  second"));
}
#[test]
fn exponential_alias_graph_is_bounded_before_materialization() {
    let mut src = "var x={v:1};".to_string();
    for _ in 0..30 {
        src.push_str("x={a:x,b:x};");
    }
    src.push_str("var env=x;");
    let r = request(json!({"op":"compare","kind":"js","a":src,"b":"var env={};"}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "RESOURCE_LIMIT");
}
#[test]
fn input_size_is_bounded_without_truncating_values() {
    let src = format!("{{\"x\":\"{}\"}}", "x".repeat(20 * 1024 * 1024));
    let r = request(json!({"op":"compare","kind":"json","a":src,"b":"{}"}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "RESOURCE_LIMIT");
}

#[test]
fn lexical_initialization_after_unknown_flow_keeps_partial_diagnostics() {
    let src = "var env={a:1};if(flag){env=other;}let x=1;env.B=x;";
    let r = request(json!({"op":"compare","kind":"js","a":src,"b":src}));
    assert_eq!(r["ok"], true);
    assert_eq!(r["complete"], false);
}
#[test]
fn largest_supported_exponent_is_exact_and_does_not_overflow() {
    let r =
        request(json!({"op":"compare","kind":"json","a":"{\"x\":1e10000}","b":"{\"x\":10e9999}"}));
    assert_eq!(r["ok"], true);
    assert_eq!(r["summary"]["same"], 1);
}

#[test]
fn js_line_separator_continuations_do_not_become_literal_characters() {
    for separator in ['\u{2028}', '\u{2029}'] {
        let src = format!("var env={{x:'a\\{separator}b'}};");
        let r = request(json!({"op":"compare","kind":"js","a":src,"b":"var env={x:'ab'};"}));
        assert_eq!(r["summary"]["same"], 1);
    }
}
#[test]
fn nested_declarations_cannot_bypass_lexical_checks() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"let env={a:1};if(true)var env={a:2};","b":"var env={a:2};"}),
    );
    assert_eq!(r["ok"], false);
}
#[test]
fn array_prototype_methods_are_never_undefined_or_same() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var env={f:[].map};","b":"var env={f:undefined};"}),
    );
    assert_eq!(r["summary"]["same"], 0);
    assert_eq!(r["summary"]["notComparable"], 1);
}
#[test]
fn json_unicode_escape_requires_four_hex_digits_without_signs() {
    let r =
        request(json!({"op":"compare","kind":"json","a":r#"{"k":"\u+041"}"#,"b":r#"{"k":"A"}"#}));
    assert_eq!(r["ok"], false);
    assert_eq!(r["error"]["code"], "JSON_PARSE_ERROR");
}
#[test]
fn js_displays_and_searches_ecmascript_numbers() {
    let r = request(
        json!({"op":"compare","kind":"js","a":"var env={a:Infinity,b:-Infinity,c:1e21,d:1e-7};","b":"var env={};"}),
    );
    let displays: Vec<_> = r["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|row| row["a"]["display"].as_str().unwrap())
        .collect();
    assert_eq!(displays, vec!["Infinity", "-Infinity", "1e+21", "1e-7"]);
}

#[test]
fn discarded_unresolved_expressions_still_make_the_program_incomplete() {
    for src in [
        "null.x;var env={a:1};",
        "(null.x,1);var env={a:1};",
        "var unused=null.x;var env={a:1};",
    ] {
        let r = request(json!({"op":"compare","kind":"js","a":src,"b":"var env={a:1};"}));
        assert_eq!(r["ok"], true);
        assert_eq!(r["complete"], false, "{src}");
    }
}

#[test]
fn inactive_branches_cannot_hide_hoisted_or_conflicting_declarations() {
    for src in [
        "if(false)var env={a:1};",
        "let env={a:1};if(false)var env={a:2};",
        "if(false){var env={a:1};}",
    ] {
        let r = request(
            json!({"op":"compare","kind":"js","a":src,"b":"var env;","rootA":"*","rootB":"*"}),
        );
        assert_eq!(r["ok"], false, "{src}");
        assert_eq!(r["error"]["code"], "UNSUPPORTED_SEMANTICS");
    }
}
#[test]
fn live_vault_snapshot_preserves_types_precision_and_rejects_duplicates() {
    let result = request(
        json!({"op":"vaultSnapshot","entries":[{"namespace":".","path":"auth","format":"kv-v2-response","response":r#"{"data":{"data":{"p":3000,"big":9007199254740993,"s":"\ud800"}}}"#}]}),
    );
    assert_eq!(result["ok"], true);
    let text = result["text"].as_str().unwrap();
    assert!(text.contains("9007199254740993"));
    assert!(text.contains("\\ud800"));
    let duplicate = request(
        json!({"op":"vaultSnapshot","entries":[{"namespace":".","path":"auth","format":"kv-v1-response","response":r#"{"data":{"x":1,"x":2}}"#}]}),
    );
    assert_eq!(duplicate["ok"], false);
    let invalid =
        request(json!({"op":"validateJson","source":r#"{"type":"database","type":"kv"}"#}));
    assert_eq!(invalid["ok"], false);
}
