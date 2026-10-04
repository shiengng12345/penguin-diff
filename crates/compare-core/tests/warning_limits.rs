use compare_core::process;
use serde_json::{Value, json};
use std::sync::Mutex;

static SERIAL: Mutex<()> = Mutex::new(());
fn request(value: Value) -> Value {
    serde_json::from_str(&process(&value.to_string())).unwrap()
}
fn source(warnings: usize) -> String {
    format!("var env={{{}}};", vec!["x:2"; warnings + 1].join(","))
}

#[test]
fn previews_and_warning_pages_are_bounded_but_full_json_retains_every_warning() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let input = source(401);
    let result = request(
        json!({"op":"compare","kind":"js","a":input,"b":"var env={x:2};","session":"warning-pages"}),
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["warningCount"], 401);
    assert_eq!(result["warnings"].as_array().unwrap().len(), 200);
    assert_eq!(result["hasMoreWarnings"], true);
    let inspected = request(json!({"op":"inspectJs","source":input}));
    assert_eq!(inspected["warningCount"], 401);
    assert_eq!(inspected["warnings"].as_array().unwrap().len(), 200);
    let full = request(
        json!({"op":"report","session":"warning-pages","includeValues":false,"filter":"differences"}),
    );
    assert_eq!(full["warnings"].as_array().unwrap().len(), 401);
    assert!(full["rows"].as_array().unwrap().is_empty());
    let mut collected = vec![];
    for (offset, length, more) in [
        (0, 200, true),
        (200, 200, true),
        (400, 1, false),
        (401, 0, false),
    ] {
        let page = request(
            json!({"op":"report","session":"warning-pages","includeValues":false,"warningOffset":offset,"warningLimit":200,"limit":1,"filter":"differences"}),
        );
        assert_eq!(page["warningCount"], 401);
        assert_eq!(page["warningOffset"], offset);
        assert_eq!(page["warningPageSize"], 200);
        assert_eq!(page["hasMoreWarnings"], more);
        assert_eq!(page["warnings"].as_array().unwrap().len(), length);
        collected.extend(page["warnings"].as_array().unwrap().iter().cloned());
    }
    assert_eq!(collected, *full["warnings"].as_array().unwrap());
    for fields in [
        json!({"warningOffset":-1}),
        json!({"warningOffset":100001}),
        json!({"warningOffset":true}),
        json!({"warningLimit":0}),
        json!({"warningLimit":201}),
        json!({"warningLimit":"200"}),
    ] {
        let mut fields = fields;
        fields["op"] = json!("report");
        fields["session"] = json!("warning-pages");
        assert_eq!(request(fields)["error"]["code"], "WARNING_PAGE_INVALID");
    }
    let csv = request(json!({"op":"report","session":"warning-pages","format":"csv"}));
    assert_eq!(csv["warningCount"], 401);
    assert!(csv.get("warnings").is_none());
    assert!(
        csv["text"]
            .as_str()
            .unwrap()
            .starts_with("path,status,a_type,b_type,a_value,b_value\r\n")
    );
}

#[test]
fn count_budget_is_per_operation_including_both_sides_and_recovery_is_possible() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let valid = request(
        json!({"op":"compare","kind":"js","a":source(50000),"b":source(50000),"session":"warning-limit-valid"}),
    );
    assert_eq!(valid["ok"], true);
    assert_eq!(valid["warningCount"], 100000);
    assert_eq!(valid["warnings"].as_array().unwrap().len(), 200);
    for fields in [
        json!({"op":"inspectJs","source":source(100001)}),
        json!({"op":"compare","kind":"js","a":source(100001),"b":"var env={x:2};","session":"warning-limit-invalid-a"}),
        json!({"op":"compare","kind":"js","a":source(50000),"b":source(50001),"session":"warning-limit-invalid"}),
    ] {
        let result = request(fields);
        assert_eq!(result["ok"], false);
        assert_eq!(result["error"]["code"], "RESOURCE_LIMIT");
        assert!(result.get("rows").is_none() && result.get("summary").is_none());
    }
    let absent = request(json!({"op":"report","session":"warning-limit-invalid"}));
    assert_eq!(absent["error"]["code"], "SESSION_NOT_FOUND");
    let absent_a = request(json!({"op":"report","session":"warning-limit-invalid-a"}));
    assert_eq!(absent_a["error"]["code"], "SESSION_NOT_FOUND");
    let recovered =
        request(json!({"op":"compare","kind":"js","a":"var env={x:2};","b":"var env={x:2};"}));
    assert_eq!(recovered["ok"], true);
    assert_eq!(recovered["warningCount"], 0);
    assert_eq!(recovered["summary"]["same"], 1);
}

#[test]
fn side_label_bytes_exceed_budget_before_session_save_and_can_recover() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let input = "\n".repeat(1_000_000) + &" ".repeat(1_000_000) + &source(100000);
    let inspected = request(json!({"op":"inspectJs","source":input}));
    assert_eq!(inspected["ok"], true);
    assert_eq!(inspected["warningCount"], 100000);
    assert_eq!(inspected["warnings"][0]["line"], 1000001);
    let result = request(
        json!({"op":"compare","kind":"js","a":input,"b":"var env={x:2};","session":"warning-byte-invalid"}),
    );
    assert_eq!(result["error"]["code"], "RESOURCE_LIMIT");
    assert!(result.get("rows").is_none() && result.get("summary").is_none());
    assert_eq!(
        request(json!({"op":"report","session":"warning-byte-invalid"}))["error"]["code"],
        "SESSION_NOT_FOUND"
    );
    let recovered =
        request(json!({"op":"compare","kind":"js","a":"var env={x:2};","b":"var env={x:2};"}));
    assert_eq!(recovered["ok"], true);
    assert_eq!(recovered["summary"]["same"], 1);
}
