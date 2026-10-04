mod js_input;
mod json_input;
mod model;
mod vault_input;
mod warnings;
mod yaml_format;

use model::Comparison;
use serde::Serialize;
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, VecDeque},
    ffi::{CStr, CString, c_char},
    sync::{Arc, Mutex, OnceLock},
};

#[derive(Debug, Serialize)]
pub struct Error {
    pub code: String,
    pub message: String,
    pub line: usize,
    pub column: usize,
}
impl Error {
    pub fn new(code: &str, message: &str) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            line: 0,
            column: 0,
        }
    }
}
#[derive(Default)]
struct SessionStore {
    values: BTreeMap<String, Arc<Comparison>>,
    order: VecDeque<String>,
}
impl SessionStore {
    fn get(&self, id: &str) -> Option<&Arc<Comparison>> {
        self.values.get(id)
    }
    fn remove(&mut self, id: &str) {
        self.values.remove(id);
        self.order.retain(|key| key != id);
    }
    fn insert(&mut self, id: String, value: Arc<Comparison>) {
        self.remove(&id);
        if self.values.len() >= 4
            && let Some(old) = self.order.pop_front()
        {
            self.values.remove(&old);
        }
        self.order.push_back(id.clone());
        self.values.insert(id, value);
    }
}
static SESSIONS: OnceLock<Mutex<SessionStore>> = OnceLock::new();
fn sessions() -> &'static Mutex<SessionStore> {
    SESSIONS.get_or_init(|| Mutex::new(SessionStore::default()))
}
fn text<'a>(request: &'a Value, key: &str) -> Result<&'a str, Error> {
    request[key]
        .as_str()
        .ok_or_else(|| Error::new("INPUT_REQUIRED", "缺少必需的输入"))
}
fn source<'a>(request: &'a Value, key: &str) -> Result<&'a str, Error> {
    let source = text(request, key)?;
    if source.len() > 20 * 1024 * 1024 {
        return Err(Error::new("RESOURCE_LIMIT", "单侧输入超过 20 MiB"));
    }
    Ok(source)
}

fn warning_range(request: &Value) -> Result<(usize, usize), Error> {
    let integer = |key: &str, fallback: usize, minimum: usize, maximum: usize| {
        if request.get(key).is_none() {
            return Ok(fallback);
        }
        request[key]
            .as_u64()
            .filter(|n| *n >= minimum as u64 && *n <= maximum as u64)
            .map(|n| n as usize)
            .ok_or_else(|| Error::new("WARNING_PAGE_INVALID", "源码警告分页参数无效。"))
    };
    Ok((
        integer("warningOffset", 0, 0, warnings::MAX_COUNT)?,
        integer("warningLimit", warnings::MAX_COUNT, 1, warnings::PAGE_SIZE)?,
    ))
}

fn matches_row(row: &model::Row, request: &Value) -> bool {
    let filter = request["filter"].as_str().unwrap_or("all");
    let query = request["search"].as_str().unwrap_or("");
    let scope = request["searchScope"].as_str().unwrap_or("all");
    let status = filter == "all"
        || (filter == "differences" && row.status != "SAME")
        || row.status == filter;
    status
        && (query.is_empty()
            || (scope != "value" && row.path.contains(query))
            || (scope != "key" && row.a.as_ref().is_some_and(|n| n.literal().contains(query)))
            || (scope != "key" && row.b.as_ref().is_some_and(|n| n.literal().contains(query))))
}
fn csv_cell(value: &str) -> String {
    let trimmed = value.trim_start();
    let protected =
        if trimmed.starts_with(['=', '+', '-', '@']) || value.starts_with(['\t', '\r', '\n']) {
            format!("'{value}")
        } else {
            value.into()
        };
    format!("\"{}\"", protected.replace('"', "\"\""))
}
fn choose_root(
    mut parsed: js_input::Parsed,
    name: &str,
    include_exports: bool,
) -> Result<model::Node, Error> {
    if name == "*" {
        if !parsed.export_used || !include_exports {
            parsed.roots.remove("module.exports");
        }
        return Ok(model::Node::new(model::Value::Object(
            parsed
                .roots
                .into_iter()
                .map(|(k, v)| (k.encode_utf16().collect(), v))
                .collect(),
            parsed.complete,
        )));
    }
    parsed
        .roots
        .remove(name)
        .ok_or_else(|| Error::new("ROOT_NOT_FOUND", "所选对象不存在；请从实际候选中选择"))
}
fn run(request: &Value) -> Result<Value, Error> {
    match text(request, "op")? {
        "validateJson" => {
            let parsed = json_input::parse(source(request, "source")?)?;
            Ok(json!({"ok":true,"text":parsed.literal()}))
        }
        "inspectVaultRead" => {
            let version = request["kvVersion"]
                .as_u64()
                .filter(|v| matches!(v, 1 | 2))
                .ok_or_else(|| Error::new("IMPORT_SCHEMA_INVALID", "请选择明确的 KV v1 或 v2。"))?;
            let status = request["httpStatus"]
                .as_u64()
                .filter(|status| matches!(status, 200 | 404))
                .ok_or_else(|| {
                    Error::new(
                        "IMPORT_SCHEMA_INVALID",
                        "Vault 读取必须提供明确的 HTTP 状态。",
                    )
                })?;
            let (config, metadata) =
                vault_input::inspect(source(request, "source")?, version as u8, status as u16)?;
            Ok(
                json!({"ok":true,"text":config.literal(),"vaultMetadata":metadata,"policyVersion":1}),
            )
        }
        "vaultSnapshot" => {
            let entries = request["entries"]
                .as_array()
                .ok_or_else(|| Error::new("IMPORT_SCHEMA_INVALID", "缺少已读取条目"))?;
            if entries.is_empty() || entries.len() > 1000 {
                return Err(Error::new("RESOURCE_LIMIT", "读取条目须为 1–1000 个"));
            }
            let mut namespaces = std::collections::BTreeMap::<
                Vec<u16>,
                std::collections::BTreeMap<Vec<u16>, model::Node>,
            >::new();
            let mut bytes = 0usize;
            for entry in entries {
                let namespace = text(entry, "namespace")?;
                let path = text(entry, "path")?;
                if namespace.is_empty() || path.is_empty() {
                    return Err(Error::new("IMPORT_SCHEMA_INVALID", "配对键不能为空"));
                }
                let raw = source(entry, "response")?;
                bytes += raw.len();
                if bytes > 20 * 1024 * 1024 {
                    return Err(Error::new("RESOURCE_LIMIT", "来源响应总量超过 20 MiB"));
                }
                let node = json_input::root(json_input::parse(raw)?, text(entry, "format")?)?;
                let paths = namespaces
                    .entry(namespace.encode_utf16().collect())
                    .or_default();
                if paths.insert(path.encode_utf16().collect(), node).is_some() {
                    return Err(Error::new("DUPLICATE_PATH", "读取条目配对键重复"));
                }
            }
            let value = model::Node::new(model::Value::Object(
                namespaces
                    .into_iter()
                    .map(|(ns, entries)| {
                        (ns, model::Node::new(model::Value::Object(entries, true)))
                    })
                    .collect(),
                true,
            ));
            Ok(json!({"ok":true,"text":value.literal()}))
        }
        "inspectJs" => {
            let parsed = js_input::parse(source(request, "source")?)?;
            Ok(
                json!({"ok":true,"roots":parsed.roots.keys().collect::<Vec<_>>(),"complete":parsed.complete,"warnings":parsed.warnings.iter().take(warnings::PAGE_SIZE).collect::<Vec<_>>(),"warningCount":parsed.warnings.len(),"hasMoreWarnings":parsed.warnings.len()>warnings::PAGE_SIZE,"warningOffset":0,"warningPageSize":warnings::PAGE_SIZE}),
            )
        }
        "formatYaml" => {
            let output = yaml_format::format(
                source(request, "source")?.trim_start_matches('\u{feff}'),
                request["indent"].as_u64().unwrap_or(2) as usize,
            )?;
            Ok(json!({"ok":true,"text":output,"policyVersion":1}))
        }
        "compare" => {
            let (a, b, source_complete, warnings) = match text(request, "kind")? {
                "json" => {
                    let input = request["inputType"].as_str().unwrap_or("plain-object");
                    (
                        json_input::root(
                            json_input::parse(source(request, "a")?)?,
                            request["inputTypeA"].as_str().unwrap_or(input),
                        )?,
                        json_input::root(
                            json_input::parse(source(request, "b")?)?,
                            request["inputTypeB"].as_str().unwrap_or(input),
                        )?,
                        true,
                        vec![],
                    )
                }
                "js" => {
                    let mut a = js_input::parse(source(request, "a")?)?;
                    let mut b = js_input::parse(source(request, "b")?)?;
                    let complete = a.complete && b.complete;
                    let root_a = request["rootA"].as_str().unwrap_or("env");
                    let root_b = request["rootB"].as_str().unwrap_or("env");
                    if (root_a == "*") != (root_b == "*") {
                        return Err(Error::new(
                            "ROOT_MODE_MISMATCH",
                            "两侧必须同时选择单根或全部变量模式",
                        ));
                    }
                    // Apply the same export selection policy to both sides. If
                    // either export is independent, keep the other side's explicit
                    // export too, even when it aliases a named root; otherwise an
                    // alias-vs-literal pair would produce artificial missing keys.
                    let include_exports = (a.export_used && !a.export_is_named_alias)
                        || (b.export_used && !b.export_is_named_alias);
                    let warnings: Vec<_> =
                        std::mem::take(&mut a.warnings)
                            .into_iter()
                            .map(|mut warning| {
                                warning.side = Some("A");
                                warning
                            })
                            .chain(std::mem::take(&mut b.warnings).into_iter().map(
                                |mut warning| {
                                    warning.side = Some("B");
                                    warning
                                },
                            ))
                            .collect();
                    warnings::validate(&warnings)?;
                    (
                        choose_root(a, root_a, include_exports)?,
                        choose_root(b, root_b, include_exports)?,
                        complete,
                        warnings,
                    )
                }
                _ => return Err(Error::new("INPUT_KIND_INVALID", "不支持的输入方式")),
            };
            let mut comparison = Comparison::new(&a, &b);
            comparison.warnings = warnings;
            if !source_complete {
                comparison
                    .incomplete
                    .push("根级静态执行范围无法完全确认".into());
            }
            comparison.incomplete.sort();
            comparison.incomplete.dedup();
            if comparison.rows.len() > 100000 {
                return Err(Error::new("RESOURCE_LIMIT", "结果超过 100000 项"));
            }
            let id = request["session"].as_str().unwrap_or("default").to_string();
            let result = json!({"ok":true,"session":id,"summary":comparison.summary(),"complete":comparison.complete(),"incompleteRanges":comparison.incomplete,"warnings":comparison.warnings.iter().take(warnings::PAGE_SIZE).collect::<Vec<_>>(),"warningCount":comparison.warnings.len(),"warningOffset":0,"warningPageSize":warnings::PAGE_SIZE,"hasMoreWarnings":comparison.warnings.len()>warnings::PAGE_SIZE,"rows":comparison.rows.iter().take(200).enumerate().map(|(id,row)|row.dto(id,false)).collect::<Vec<_>>(),"policyVersion":1});
            let mut map = sessions()
                .lock()
                .map_err(|_| Error::new("WORKER_INTERRUPTED", "结果存储不可用"))?;
            map.insert(id, Arc::new(comparison));
            Ok(result)
        }
        "rows" | "details" | "report" => {
            let session = text(request, "session")?;
            let result = sessions()
                .lock()
                .map_err(|_| Error::new("WORKER_INTERRUPTED", "结果存储不可用"))?
                .get(session)
                .cloned()
                .ok_or_else(|| Error::new("SESSION_NOT_FOUND", "结果已释放，请重新比较"))?;
            match text(request, "op")? {
                "details" => {
                    let id = request["id"].as_u64().unwrap_or(u64::MAX) as usize;
                    let row = result
                        .rows
                        .get(id)
                        .ok_or_else(|| Error::new("ROW_NOT_FOUND", "结果项不存在"))?;
                    Ok(json!({"ok":true,"row":row.dto(id,true)}))
                }
                "report" => {
                    let values = request["includeValues"].as_bool().unwrap_or(true);
                    let offset = request["offset"].as_u64().unwrap_or(0).min(100000) as usize;
                    let limit = request["limit"]
                        .as_u64()
                        .map(|n| n.min(200) as usize)
                        .unwrap_or(100000);
                    let rows:Vec<_>=result.rows.iter().enumerate().filter(|(_,row)|matches_row(row,request)).skip(offset).take(limit).map(|(id,row)|{
                    let mut dto=row.dto(id,values);if !values{for side in ["a","b"]{let original=&dto[side];dto[side]=json!({"type":original["type"],"present":original["present"],"display":"<值未导出>"});}}dto
                }).collect();
                    if request["format"] == "csv" {
                        let mut output =
                            String::from("path,status,a_type,b_type,a_value,b_value\r\n");
                        for row in &rows {
                            let cells = [
                                row["path"].as_str().unwrap_or(""),
                                row["status"].as_str().unwrap_or(""),
                                row["a"]["type"].as_str().unwrap_or(""),
                                row["b"]["type"].as_str().unwrap_or(""),
                                row["a"]["literal"]
                                    .as_str()
                                    .or(row["a"]["display"].as_str())
                                    .unwrap_or(""),
                                row["b"]["literal"]
                                    .as_str()
                                    .or(row["b"]["display"].as_str())
                                    .unwrap_or(""),
                            ];
                            output.push_str(&cells.map(csv_cell).join(","));
                            output.push_str("\r\n");
                        }
                        return Ok(
                            json!({"ok":true,"text":output,"warningCount":result.warnings.len()}),
                        );
                    }
                    let (warning_offset, warning_limit) = warning_range(request)?;
                    let page: Vec<_> = result
                        .warnings
                        .iter()
                        .skip(warning_offset)
                        .take(warning_limit)
                        .collect();
                    Ok(
                        json!({"ok":true,"schemaVersion":1,"policyVersion":1,"complete":result.complete(),"summary":result.summary(),"incompleteRanges":result.incomplete,"warnings":page,"warningCount":result.warnings.len(),"warningOffset":warning_offset,"warningPageSize":warning_limit,"hasMoreWarnings":warning_offset+page.len()<result.warnings.len(),"exportedCount":rows.len(),"includesValues":values,"filter":request["filter"].as_str().unwrap_or("all"),"search":request["search"].as_str().unwrap_or(""),"searchScope":request["searchScope"].as_str().unwrap_or("all"),"rows":rows}),
                    )
                }
                _ => {
                    let offset = request["offset"].as_u64().unwrap_or(0) as usize;
                    let limit = request["limit"].as_u64().unwrap_or(200).min(1000) as usize;
                    let matches: Vec<_> = result
                        .rows
                        .iter()
                        .enumerate()
                        .filter(|(_, row)| matches_row(row, request))
                        .collect();
                    Ok(
                        json!({"ok":true,"matched":matches.len(),"rows":matches.into_iter().skip(offset).take(limit).map(|(id,row)|row.dto(id,false)).collect::<Vec<_>>()}),
                    )
                }
            }
        }
        "release" => {
            sessions()
                .lock()
                .map_err(|_| Error::new("WORKER_INTERRUPTED", "结果存储不可用"))?
                .remove(text(request, "session")?);
            Ok(json!({"ok":true}))
        }
        _ => Err(Error::new("OPERATION_INVALID", "不支持的本地操作")),
    }
}

// Recursive parsers/formatters must not consume a foreign caller's small stack.
// Scoped borrowing avoids another copy of the (bounded) request; joining keeps
// C ABI input references alive until all processing and serialization finish.
const PROCESS_STACK_BYTES: usize = 8 * 1024 * 1024;

pub fn process(request: &str) -> String {
    if request.len() > 100 * 1024 * 1024 {
        return json!({"ok":false,"error":Error::new("RESOURCE_LIMIT","请求超过资源限制")})
            .to_string();
    }
    std::thread::scope(|scope| {
        let result = std::thread::Builder::new()
            .name("config-compare-core".into())
            .stack_size(PROCESS_STACK_BYTES)
            .spawn_scoped(scope, || process_inner(request))
            .map(|worker| worker.join());
        finish_processing(result)
    })
}

fn finish_processing(result: Result<std::thread::Result<String>, std::io::Error>) -> String {
    match result {
        Ok(Ok(response)) => response,
        _ => json!({"ok":false,"error":Error::new("WORKER_INTERRUPTED","本地计算中断；可以重新比较")})
            .to_string(),
    }
}

fn process_inner(request: &str) -> String {
    let outcome = std::panic::catch_unwind(|| {
        let request: Value = serde_json::from_str(request)
            .map_err(|_| Error::new("REQUEST_INVALID", "请求格式无效"))?;
        run(&request)
    });
    match outcome{Ok(Ok(value))=>value.to_string(),Ok(Err(error))=>json!({"ok":false,"error":error}).to_string(),Err(_)=>json!({"ok":false,"error":Error::new("WORKER_INTERRUPTED","本地计算中断；可以重新比较")}).to_string()}
}

/// # Safety
/// `request` must point to a valid NUL-terminated UTF-8 string for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cc_process(request: *const c_char) -> *mut c_char {
    if request.is_null() {
        return std::ptr::null_mut();
    }
    let input = unsafe { CStr::from_ptr(request) };
    let output = match input.to_str() {
        Ok(input) => process(input),
        Err(_) => json!({"ok":false,"error":Error::new("ENCODING_INVALID","请求编码不受支持")})
            .to_string(),
    };
    CString::new(output).map_or(std::ptr::null_mut(), CString::into_raw)
}
/// # Safety
/// The pointer must be returned by `cc_process` and must not have been freed before.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cc_free(response: *mut c_char) {
    if !response.is_null() {
        drop(unsafe { CString::from_raw(response) });
    }
}

#[cfg(test)]
mod session_tests {
    use super::*;
    #[test]
    fn failed_thread_start_or_join_does_not_return_private_payloads() {
        let responses = [
            finish_processing(Err(std::io::Error::other("synthetic-private-os-error"))),
            finish_processing(Ok(Err(Box::new("synthetic-private-panic")))),
        ];
        for response in responses {
            let value: Value = serde_json::from_str(&response).unwrap();
            assert_eq!(value["ok"], false);
            assert_eq!(value["error"]["code"], "WORKER_INTERRUPTED");
            assert!(!response.contains("synthetic-private"));
        }
        assert_eq!(
            finish_processing(Ok(Ok("unchanged response".into()))),
            "unchanged response"
        );
    }
    #[test]
    fn evicts_oldest_created_session_and_retains_recent_sessions() {
        let mut store = SessionStore::default();
        for id in ["z-first", "y-second", "a-third", "b-fourth", "c-fifth"] {
            store.insert(
                id.into(),
                Arc::new(Comparison::new(
                    &model::Node::new(model::Value::Null),
                    &model::Node::new(model::Value::Null),
                )),
            );
        }
        assert!(store.get("z-first").is_none());
        assert!(store.get("a-third").is_some());
        assert!(store.get("c-fifth").is_some());
    }
}
