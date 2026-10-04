//! Synthetic protocol tests: never contact Vault or execute input code.
use compare_core::process;
use serde_json::{Value, json};

fn inspect(source: &str, version: u8) -> Value {
    serde_json::from_str(&process(
        &json!({"op":"inspectVaultRead","source":source,"kvVersion":version,"httpStatus":200})
            .to_string(),
    ))
    .unwrap()
}

#[test]
fn read_operation_rejects_missing_invalid_and_kv1_404_status() {
    for (request, code) in [
        (
            json!({"op":"inspectVaultRead","source":"{\"data\":{}}","kvVersion":2}),
            "IMPORT_SCHEMA_INVALID",
        ),
        (
            json!({"op":"inspectVaultRead","source":"{\"data\":{}}","kvVersion":2,"httpStatus":403}),
            "IMPORT_SCHEMA_INVALID",
        ),
        (
            json!({"op":"inspectVaultRead","source":"{\"data\":{}}","kvVersion":1,"httpStatus":404}),
            "VAULT_HTTP_404",
        ),
    ] {
        let response: Value = serde_json::from_str(&process(&request.to_string())).unwrap();
        assert_eq!(response["ok"], false, "{response}");
        assert_eq!(response["error"]["code"], code, "{response}");
        assert!(response.get("text").is_none());
        assert!(response.get("vaultMetadata").is_none());
    }
}

#[test]
fn kv2_metadata_is_independent_of_exact_business_values() {
    let result = inspect(
        r#"{"data":{"data":{"big":9007199254740993,"huge":1e10000,"s":"\ud800"},"metadata":{"version":7,"created_time":"2026-10-03T01:02:03.123456789Z","deletion_time":"","destroyed":false,"custom_metadata":{"private":"synthetic-private"}}}}"#,
        2,
    );
    assert_eq!(result["ok"], true, "{result}");
    let text = result["text"].as_str().unwrap();
    assert!(
        text.contains("9007199254740993") && text.contains("1e10000") && text.contains("\\ud800"),
        "{text}"
    );
    assert_eq!(result["vaultMetadata"]["kvVersion"], 2);
    assert_eq!(result["vaultMetadata"]["version"], "7");
    assert_eq!(
        result["vaultMetadata"]["createdTime"],
        "2026-10-03T01:02:03.123456789Z"
    );
    assert_eq!(result["vaultMetadata"]["destroyed"], false);
    assert_eq!(result["vaultMetadata"]["state"], "readable");
    assert!(!result.to_string().contains("synthetic-private"));
}

#[test]
fn kv1_and_absent_kv2_metadata_never_fabricate_versions() {
    for (source, version) in [
        (r#"{"data":{"PORT":3,"metadata":{"version":99}}}"#, 1),
        (r#"{"data":{"data":{"PORT":3}}}"#, 2),
    ] {
        let result = inspect(source, version);
        assert_eq!(result["ok"], true, "{result}");
        assert!(result["vaultMetadata"]["version"].is_null());
        assert!(result["vaultMetadata"]["destroyed"].is_null());
        assert_eq!(result["vaultMetadata"]["state"], "readable");
        if version == 1 {
            assert!(result["text"].as_str().unwrap().contains("metadata"));
        }
    }
}

#[test]
fn deleted_or_destroyed_metadata_does_not_return_comparable_values() {
    for (metadata, state) in [
        (
            json!({"version":3,"deletion_time":"2026-10-03T01:02:03Z","destroyed":false}),
            "deleted",
        ),
        (json!({"version":3,"destroyed":true}), "destroyed"),
    ] {
        let source = json!({"data":{"data":null,"metadata":metadata}}).to_string();
        let result = inspect(&source, 2);
        assert_eq!(result["ok"], false, "{result}");
        assert_eq!(
            result["error"]["code"],
            if state == "deleted" {
                "VAULT_SECRET_DELETED"
            } else {
                "VAULT_SECRET_DESTROYED"
            }
        );
        assert!(result.get("text").is_none());
        assert!(result.get("vaultMetadata").is_none());
    }
}

#[test]
fn invalid_metadata_is_rejected_without_echoing_its_contents() {
    for metadata in [
        json!("synthetic-sensitive"),
        json!({"version":true}),
        json!({"version":0}),
        json!({"version":-1}),
        json!({"version":1.5}),
        json!({"version":"7"}),
        json!({"version":9223372036854775808u64}),
        json!({"destroyed":"false"}),
        json!({"created_time":"synthetic-sensitive"}),
        json!({"created_time":"2025-02-29T00:00:00Z"}),
        json!({"deletion_time":"2026-10-03T25:00:00Z"}),
    ] {
        let result = inspect(
            &json!({"data":{"data":{"x":1},"metadata":metadata}}).to_string(),
            2,
        );
        assert_eq!(result["ok"], false, "{result}");
        assert_eq!(
            result["error"]["code"], "VAULT_METADATA_INVALID",
            "{result}"
        );
        assert!(!result.to_string().contains("synthetic-sensitive"));
    }
}

#[test]
fn read_provenance_reuses_strict_schema_and_duplicate_key_guards() {
    for (source, code) in [
        (
            r#"{"data":{"data":{"x":1,"\u0078":2},"metadata":{"version":1}}}"#,
            "JSON_DUPLICATE_KEY",
        ),
        (r#"{"data":{"data":null}}"#, "NO_COMPARABLE_CONTENT"),
    ] {
        let result = inspect(source, 2);
        assert_eq!(result["ok"], false, "{result}");
        assert_eq!(result["error"]["code"], code, "{result}");
    }
    assert_eq!(
        inspect(r#"{"data":{}}"#, 3)["error"]["code"],
        "IMPORT_SCHEMA_INVALID"
    );
}

#[test]
fn deletion_time_with_returned_business_object_is_not_a_deleted_boolean() {
    // Vault can schedule deletion in advance; never rely on the client's clock.
    for time in ["2099-01-01T00:00:00Z", "2020-01-01T00:00:00Z"] {
        let source = json!({"data":{"data":{"x":1},"metadata":{"version":3,"deletion_time":time,"destroyed":false}}}).to_string();
        let result = inspect(&source, 2);
        assert_eq!(result["vaultMetadata"]["state"], "readable", "{result}");
        assert_eq!(result["vaultMetadata"]["deletionTime"], time);
        let config: Value = serde_json::from_str(result["text"].as_str().unwrap()).unwrap();
        assert_eq!(config, json!({"x":1}));
    }
}

#[test]
fn http_status_and_404_envelope_must_confirm_unavailable_version() {
    for (source, code) in [
        (
            r#"{"request_id":"synthetic","data":{"data":null,"metadata":{"version":3,"deletion_time":"2020-01-01T00:00:00Z","destroyed":false}}}"#,
            "VAULT_SECRET_DELETED",
        ),
        (
            r#"{"data":{"data":null,"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_SECRET_DESTROYED",
        ),
        (r#"{"errors":[]}"#, "VAULT_HTTP_404"),
        (
            r#"{"errors":[],"data":{"data":null,"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"unexpected":"synthetic-private","data":{"data":null,"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"data":{"extra":1,"data":null,"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"data":{"data":{"x":1},"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"data":{"data":null,"metadata":{"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"data":{"data":null,"metadata":{"version":3,"deletion_time":"2020-01-01T00:00:00Z"}}}"#,
            "VAULT_HTTP_404",
        ),
        (
            r#"{"wrap_info":{"token":"synthetic-private"},"data":{"data":null,"metadata":{"version":3,"destroyed":true}}}"#,
            "VAULT_HTTP_404",
        ),
    ] {
        let result: Value = serde_json::from_str(&process(
            &json!({"op":"inspectVaultRead","source":source,"kvVersion":2,"httpStatus":404})
                .to_string(),
        ))
        .unwrap();
        assert_eq!(result["ok"], false, "{result}");
        assert_eq!(result["error"]["code"], code, "{result}");
        assert!(result.get("text").is_none());
        assert!(!result.to_string().contains("synthetic-private"));
    }
}
