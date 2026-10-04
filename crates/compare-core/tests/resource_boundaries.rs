//! Exact depth acceptance/rejection, with real core recovery. Synthetic inputs only.
use compare_core::process;
use serde_json::{Value, json};
use std::sync::Mutex;

static SERIAL: Mutex<()> = Mutex::new(());

fn request(value: Value) -> Value {
    serde_json::from_str(&process(&value.to_string())).expect("core must return JSON")
}

fn object(depth: usize) -> String {
    let mut result = "1".to_string();
    for _ in 0..depth {
        result = format!("{{\"field\":{result}}}");
    }
    result
}

fn array(depth: usize) -> String {
    // The required object root adds one level; leaf depth is exactly `depth`.
    format!(
        "{{\"field\":{}1{}}}",
        "[".repeat(depth - 1),
        "]".repeat(depth - 1)
    )
}

fn exact_compare_depth(kind: &str) {
    for shape in [object as fn(usize) -> String, array] {
        let wrap = |input: String| {
            if kind == "js" {
                format!("var env={input};")
            } else {
                input
            }
        };
        let accepted = wrap(shape(128));
        let result = request(
            json!({"op":"compare","kind":kind,"a":accepted,"b":accepted,"session":"depth-accepted"}),
        );
        assert_eq!(result["ok"], true, "{kind}: {result}");
        assert_eq!(result["complete"], true);
        assert_eq!(result["summary"]["total"], 1);
        assert_eq!(result["summary"]["same"], 1);
        assert_eq!(result["rows"][0]["segments"].as_array().unwrap().len(), 128);
        let rejected = wrap(shape(129));
        let failure = request(
            json!({"op":"compare","kind":kind,"a":rejected,"b":accepted,"session":"depth-rejected"}),
        );
        assert_eq!(failure["ok"], false, "{kind}: {failure}");
        assert_eq!(failure["error"]["code"], "RESOURCE_LIMIT");
        assert!(failure.get("rows").is_none() && failure.get("summary").is_none());
        let missing = request(json!({"op":"report","session":"depth-rejected"}));
        assert_eq!(missing["error"]["code"], "SESSION_NOT_FOUND");
        let recovered = request(
            json!({"op":"compare","kind":"json","a":"{}","b":"{}","session":"depth-rejected"}),
        );
        assert_eq!(recovered["summary"]["same"], 1);
        for session in ["depth-accepted", "depth-rejected"] {
            assert_eq!(
                request(json!({"op":"release","session":session}))["ok"],
                true
            );
        }
    }
}

#[test]
fn json_accepts_leaf_depth_128_rejects_129_and_recovers() {
    let _guard = SERIAL.lock().unwrap();
    exact_compare_depth("json");
}

#[test]
fn js_accepts_leaf_depth_128_rejects_129_and_recovers() {
    let _guard = SERIAL.lock().unwrap();
    exact_compare_depth("js");
}

#[test]
fn yaml_accepts_128_containers_rejects_129_and_recovers() {
    let _guard = SERIAL.lock().unwrap();
    let input = |depth| format!("{}1{}\n", "[".repeat(depth), "]".repeat(depth));
    let accepted = request(json!({"op":"formatYaml","source":input(128)}));
    assert_eq!(accepted["ok"], true, "{accepted}");
    let formatted = accepted["text"].as_str().unwrap();
    assert_eq!(formatted.matches('[').count(), 128);
    assert_eq!(formatted.matches(']').count(), 128);
    let again = request(json!({"op":"formatYaml","source":formatted}));
    assert_eq!(again["text"], accepted["text"]);
    let rejected = request(json!({"op":"formatYaml","source":input(129)}));
    assert_eq!(rejected["ok"], false, "{rejected}");
    assert_eq!(rejected["error"]["code"], "RESOURCE_LIMIT");
    assert!(rejected.get("text").is_none());
    assert_eq!(
        request(json!({"op":"formatYaml","source":"x:  1\n"}))["text"],
        "x: 1\n"
    );
}

#[test]
fn js_branch_validation_and_selected_statements_have_depth_budgets() {
    let _guard = SERIAL.lock().unwrap();
    for condition in ["true", "false"] {
        for depth in [128, 129, 10000] {
            let source = format!(
                "var env={{}};{}env.x=1;",
                format!("if({condition})").repeat(depth)
            );
            let result = request(
                json!({"op":"compare","kind":"js","a":source,"b":source,"session":"if-depth"}),
            );
            if depth == 128 {
                assert_eq!(result["ok"], true, "{condition}: {result}");
                assert_eq!(result["complete"], true);
                assert_eq!(result["summary"]["same"], 1);
                request(json!({"op":"release","session":"if-depth"}));
            } else {
                assert_eq!(
                    result["error"]["code"], "RESOURCE_LIMIT",
                    "{condition}: {result}"
                );
                assert_eq!(
                    request(json!({"op":"rows","session":"if-depth"}))["error"]["code"],
                    "SESSION_NOT_FOUND"
                );
            }
        }
    }
}

#[test]
fn real_c_abi_accepts_depth_128_on_a_512_kib_caller_stack() {
    let _guard = SERIAL.lock().unwrap();
    std::thread::Builder::new().stack_size(512 * 1024).spawn(|| {
        use std::ffi::{CStr, CString};
        for kind in ["json", "js"] {
            let source = if kind == "js" { format!("var env={};", object(128)) } else { object(128) };
            let input = CString::new(json!({"op":"compare","kind":kind,"a":source,"b":source,"session":"small-stack"}).to_string()).unwrap();
            // The input CString remains alive until the scoped core thread joins.
            let output = unsafe { compare_core::cc_process(input.as_ptr()) };
            assert!(!output.is_null());
            let text = unsafe { CStr::from_ptr(output) }.to_str().unwrap();
            let response: Value = serde_json::from_str(text).unwrap();
            unsafe { compare_core::cc_free(output) };
            assert_eq!(response["ok"], true, "{kind}: {response}");
            assert_eq!(response["summary"]["same"], 1);
            request(json!({"op":"release","session":"small-stack"}));
        }
    }).unwrap().join().unwrap();
}

#[test]
fn parser_regex_cursor_budget_alignment_never_panics() {
    use oxc_allocator::Allocator;
    use oxc_parser::{ParseOptions, Parser};
    use oxc_span::SourceType;
    for suffix in ["", "g", "im"] {
        for prefix in 0..8 {
            let source = format!(
                "{}var env={{x:[/a/{suffix},/b/{suffix}]}};",
                ";".repeat(prefix)
            );
            for budget in 1..100 {
                let allocator = Allocator::default();
                let parsed = Parser::new(&allocator, &source, SourceType::cjs())
                    .with_options(ParseOptions {
                        cursor_budget: Some(budget),
                        ..ParseOptions::default()
                    })
                    .parse();
                if parsed.resource_exhausted {
                    assert!(
                        parsed.fatal_error,
                        "budget={budget}, prefix={prefix}, flags={suffix}"
                    );
                } else {
                    assert!(
                        parsed.diagnostics.is_empty(),
                        "budget={budget}, prefix={prefix}, flags={suffix}"
                    );
                }
            }
        }
    }
}

#[test]
fn js_wide_parenthesized_values_within_original_limits_still_compare() {
    let _guard = SERIAL.lock().unwrap();
    for count in [40000, 99000] {
        let fields = (0..count)
            .map(|n| format!("k{n}:(undefined)"))
            .collect::<Vec<_>>()
            .join(",");
        let source = format!("var env={{{fields}}};");
        assert!(source.len() < 20 * 1024 * 1024);
        let compared = request(
            json!({"op":"compare","kind":"js","a":source,"b":source,"session":"wide-parentheses"}),
        );
        assert_eq!(compared["ok"], true, "count={count}: {compared}");
        assert_eq!(compared["complete"], true);
        assert_eq!(compared["summary"]["total"], count);
        assert_eq!(compared["summary"]["same"], count);
        assert_eq!(compared["summary"]["notComparable"], 0);
        request(json!({"op":"release","session":"wide-parentheses"}));
    }
}
