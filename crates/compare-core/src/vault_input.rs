//! Read-only extraction. Provenance never becomes a business comparison key.
use crate::{
    Error, json_input,
    model::{Node, Value},
};
use serde::Serialize;
use std::collections::BTreeMap;

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReadMetadata {
    kv_version: u8,
    version: Option<String>,
    created_time: Option<String>,
    deletion_time: Option<String>,
    destroyed: Option<bool>,
    state: &'static str,
}

fn invalid() -> Error {
    Error::new(
        "VAULT_METADATA_INVALID",
        "Vault 版本来源格式无效；没有输出可比较结果。",
    )
}

fn field<'a>(fields: &'a BTreeMap<Vec<u16>, Node>, key: &str) -> Option<&'a Node> {
    fields.get(&key.encode_utf16().collect::<Vec<_>>())
}

fn timestamp(value: Option<&Node>, empty: bool) -> Result<Option<String>, Error> {
    let Some(value) = value else { return Ok(None) };
    if matches!(value.value, Value::Null) {
        return Ok(None);
    }
    let Value::String(units) = &value.value else {
        return Err(invalid());
    };
    let text = String::from_utf16(units).map_err(|_| invalid())?;
    if (empty && text.is_empty()) || valid_timestamp(&text) {
        Ok(Some(text))
    } else {
        Err(invalid())
    }
}

fn valid_timestamp(text: &str) -> bool {
    let b = text.as_bytes();
    if !(20..=128).contains(&b.len())
        || !text.is_ascii()
        || b[4] != b'-'
        || b[7] != b'-'
        || !matches!(b[10], b'T' | b't')
        || b[13] != b':'
        || b[16] != b':'
    {
        return false;
    }
    let number = |start: usize, end: usize| -> Option<u32> {
        let digits = &b[start..end];
        if !digits.iter().all(u8::is_ascii_digit) {
            return None;
        }
        Some(
            digits
                .iter()
                .fold(0, |n, digit| n * 10 + u32::from(digit - b'0')),
        )
    };
    let (Some(year), Some(month), Some(day), Some(hour), Some(minute), Some(second)) = (
        number(0, 4),
        number(5, 7),
        number(8, 10),
        number(11, 13),
        number(14, 16),
        number(17, 19),
    ) else {
        return false;
    };
    let leap = year.is_multiple_of(400) || (year.is_multiple_of(4) && !year.is_multiple_of(100));
    let days = match month {
        2 => {
            if leap {
                29
            } else {
                28
            }
        }
        4 | 6 | 9 | 11 => 30,
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        _ => return false,
    };
    if day == 0 || day > days || hour > 23 || minute > 59 || second > 60 {
        return false;
    }
    let mut cursor = 19;
    if b[cursor] == b'.' {
        cursor += 1;
        let start = cursor;
        while cursor < b.len() && b[cursor].is_ascii_digit() {
            cursor += 1;
        }
        if start == cursor {
            return false;
        }
    }
    let zone = &b[cursor..];
    if matches!(zone, [b'Z' | b'z']) {
        return true;
    }
    zone.len() == 6
        && matches!(zone[0], b'+' | b'-')
        && zone[3] == b':'
        && number(cursor + 1, cursor + 3).is_some_and(|h| h <= 23)
        && number(cursor + 4, cursor + 6).is_some_and(|m| m <= 59)
}

fn unavailable() -> Error {
    Error::new("VAULT_HTTP_404", "范围无法确认；未将 404 当作缺失。")
}

fn confirm_404_envelope(parsed: &Node) -> Result<(), Error> {
    let Value::Object(root, _) = &parsed.value else {
        return Err(unavailable());
    };
    let allowed: Vec<Vec<u16>> = [
        "request_id",
        "lease_id",
        "renewable",
        "lease_duration",
        "data",
        "wrap_info",
        "warnings",
        "auth",
        "mount_type",
    ]
    .iter()
    .map(|key| key.encode_utf16().collect())
    .collect();
    if root.keys().any(|key| !allowed.contains(key))
        || field(root, "wrap_info").is_some_and(|value| !matches!(value.value, Value::Null))
    {
        return Err(unavailable());
    }
    let Some(Node {
        value: Value::Object(data, _),
        ..
    }) = field(root, "data")
    else {
        return Err(unavailable());
    };
    let allowed: Vec<Vec<u16>> = ["data", "metadata"]
        .iter()
        .map(|key| key.encode_utf16().collect())
        .collect();
    if data.keys().any(|key| !allowed.contains(key))
        || !field(data, "data").is_some_and(|payload| matches!(payload.value, Value::Null))
        || !field(data, "metadata")
            .is_some_and(|metadata| matches!(metadata.value, Value::Object(_, _)))
    {
        return Err(unavailable());
    }
    Ok(())
}

pub fn inspect(
    source: &str,
    kv_version: u8,
    http_status: u16,
) -> Result<(Node, ReadMetadata), Error> {
    inspect_inner(source, kv_version, http_status).map_err(|error| {
        if http_status == 404
            && !matches!(
                error.code.as_str(),
                "VAULT_SECRET_DELETED" | "VAULT_SECRET_DESTROYED"
            )
        {
            unavailable()
        } else {
            error
        }
    })
}

fn inspect_inner(
    source: &str,
    kv_version: u8,
    http_status: u16,
) -> Result<(Node, ReadMetadata), Error> {
    if !matches!(kv_version, 1 | 2) {
        return Err(Error::new(
            "IMPORT_SCHEMA_INVALID",
            "请选择明确的 KV v1 或 v2。",
        ));
    }
    if !matches!(http_status, 200 | 404) || (http_status == 404 && kv_version != 2) {
        return Err(unavailable());
    }
    let parsed = json_input::parse(source).map_err(|error| {
        if http_status == 404 {
            unavailable()
        } else {
            error
        }
    })?;
    if http_status == 404 {
        confirm_404_envelope(&parsed)?;
    }
    let mut metadata = ReadMetadata {
        kv_version,
        version: None,
        created_time: None,
        deletion_time: None,
        destroyed: None,
        state: "readable",
    };
    if kv_version == 2
        && let Value::Object(root, _) = &parsed.value
        && let Some(Node {
            value: Value::Object(data, _),
            ..
        }) = field(root, "data")
        && let Some(value) = field(data, "metadata")
        && !matches!(value.value, Value::Null)
    {
        let Value::Object(fields, _) = &value.value else {
            return Err(invalid());
        };
        if let Some(value) = field(fields, "version")
            && !matches!(value.value, Value::Null)
        {
            let Value::JsonNumber(raw) = &value.value else {
                return Err(invalid());
            };
            if !raw.bytes().all(|b| b.is_ascii_digit())
                || raw.parse::<i64>().ok().filter(|v| *v > 0).is_none()
            {
                return Err(invalid());
            }
            metadata.version = Some(raw.clone());
        }
        metadata.created_time = timestamp(field(fields, "created_time"), false)?;
        metadata.deletion_time = timestamp(field(fields, "deletion_time"), true)?;
        if let Some(value) = field(fields, "destroyed")
            && !matches!(value.value, Value::Null)
        {
            let Value::Boolean(destroyed) = value.value else {
                return Err(invalid());
            };
            metadata.destroyed = Some(destroyed);
        }
        if metadata.destroyed == Some(true) {
            metadata.state = "destroyed";
        } else if metadata
            .deletion_time
            .as_ref()
            .is_some_and(|time| !time.is_empty())
            && field(data, "data").is_some_and(|payload| matches!(payload.value, Value::Null))
        {
            // deletion_time may be a future schedule. A returned business object
            // remains readable; never use the client's wall clock to reject it.
            metadata.state = "deleted";
        }
    }
    if http_status == 404 && (metadata.version.is_none() || metadata.destroyed.is_none()) {
        return Err(unavailable());
    }
    if metadata.state == "deleted" || metadata.state == "destroyed" {
        return Err(Error::new(
            if metadata.state == "deleted" {
                "VAULT_SECRET_DELETED"
            } else {
                "VAULT_SECRET_DESTROYED"
            },
            "读取版本已删除或销毁；整批停止，不生成缺失或相同结论。",
        ));
    }
    if http_status == 404 {
        return Err(unavailable());
    }
    if let Value::Object(root, _) = &parsed.value
        && field(root, "wrap_info").is_some_and(|value| !matches!(value.value, Value::Null))
    {
        return Err(invalid());
    }
    Ok((
        json_input::root(
            parsed,
            if kv_version == 2 {
                "kv-v2-response"
            } else {
                "kv-v1-response"
            },
        )?,
        metadata,
    ))
}
