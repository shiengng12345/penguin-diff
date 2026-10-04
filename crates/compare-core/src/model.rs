use serde_json::{Value as Json, json};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Undefined,
    Hole,
    Boolean(bool),
    JsNumber(f64),
    JsonNumber(String),
    BigInt(String),
    String(Vec<u16>),
    Object(BTreeMap<Vec<u16>, Node>, bool),
    Array(Vec<Node>),
    Unknown(String),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Node {
    pub value: Value,
    pub line: usize,
    pub column: usize,
}
impl Node {
    pub fn new(value: Value) -> Self {
        Self {
            value,
            line: 0,
            column: 0,
        }
    }
    pub fn unknown(reason: &str) -> Self {
        Self::new(Value::Unknown(reason.into()))
    }
    pub fn kind(&self) -> &str {
        match self.value {
            Value::Null => "Null",
            Value::Undefined => "Undefined",
            Value::Hole => "Hole",
            Value::Boolean(_) => "Boolean",
            Value::JsNumber(_) => "Number",
            Value::JsonNumber(_) => "Number",
            Value::BigInt(_) => "BigInt",
            Value::String(_) => "String",
            Value::Object(..) => "Object",
            Value::Array(_) => "Array",
            Value::Unknown(_) => "Unknown",
        }
    }
    pub fn display(&self) -> String {
        match &self.value {
            Value::Null => "null".into(),
            Value::Undefined => "undefined".into(),
            Value::Hole => "<空槽>".into(),
            Value::Boolean(v) => v.to_string(),
            Value::JsNumber(v) => {
                if v.is_nan() {
                    "NaN".into()
                } else if v.is_infinite() {
                    if v.is_sign_negative() {
                        "-Infinity"
                    } else {
                        "Infinity"
                    }
                    .into()
                } else if *v == 0.0 && v.is_sign_negative() {
                    "-0".into()
                } else {
                    dragonbox_ecma::Buffer::new().format(*v).to_string()
                }
            }
            Value::JsonNumber(v) => v.clone(),
            Value::BigInt(v) => format!("{v}n"),
            Value::String(v) => quoted(v),
            Value::Object(v, _) => format!("{{ {} 个键 }}", v.len()),
            Value::Array(v) => format!("[ {} 项 ]", v.len()),
            Value::Unknown(v) => format!("<无法比较：{v}>"),
        }
    }
    pub fn literal(&self) -> String {
        match &self.value {
            Value::Object(fields, _) => format!(
                "{{{}}}",
                fields
                    .iter()
                    .map(|(k, v)| format!("{}: {}", quoted(k), v.literal()))
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            Value::Array(items) => format!(
                "[{}]",
                items
                    .iter()
                    .map(Node::literal)
                    .collect::<Vec<_>>()
                    .join(", ")
            ),
            _ => self.display(),
        }
    }
    pub fn dto(&self) -> Json {
        let mut v = json!({"type":self.kind(),"display":self.display(),"literal":self.literal(),"line":self.line,"column":self.column});
        match &self.value {
            Value::String(units) => v["units"] = json!(units),
            Value::Object(fields, complete) => {
                v["complete"] = json!(complete);
                v["entries"] = json!(
                    fields
                        .iter()
                        .map(|(key, node)| json!({"keyUnits":key,"value":node.dto()}))
                        .collect::<Vec<_>>()
                );
            }
            Value::Array(items) => {
                v["items"] = json!(items.iter().map(Node::dto).collect::<Vec<_>>())
            }
            Value::Unknown(reason) => v["reason"] = json!(reason),
            _ => {}
        }
        v
    }
}

pub fn quoted(units: &[u16]) -> String {
    let mut s = String::from("\"");
    for u in char::decode_utf16(units.iter().copied()) {
        match u {
            Ok('"') => s.push_str("\\\""),
            Ok('\\') => s.push_str("\\\\"),
            Ok('\n') => s.push_str("\\n"),
            Ok('\r') => s.push_str("\\r"),
            Ok('\t') => s.push_str("\\t"),
            Ok(c) if c.is_control() => s.push_str(&format!("\\u{:04x}", c as u32)),
            Ok(c) => s.push(c),
            Err(e) => s.push_str(&format!("\\u{:04x}", e.unpaired_surrogate())),
        }
    }
    s.push('"');
    s
}

pub fn number_key(raw: &str) -> Option<String> {
    let negative = raw.starts_with('-');
    let input = raw.trim_start_matches('-');
    let (mantissa, exponent) = input.split_once(['e', 'E']).unwrap_or((input, "0"));
    let mut exponent: i64 = exponent.parse().ok()?;
    if exponent.unsigned_abs() > 10000 || mantissa.len() > 100000 {
        return None;
    }
    let decimals = mantissa.split_once('.').map_or(0, |(_, r)| r.len());
    let mut digits = mantissa
        .replace('.', "")
        .trim_start_matches('0')
        .to_string();
    exponent -= decimals as i64;
    if digits.is_empty() {
        return Some(if negative { "-0" } else { "0" }.into());
    }
    while digits.ends_with('0') {
        digits.pop();
        exponent += 1;
    }
    Some(format!(
        "{}{digits}e{exponent}",
        if negative { "-" } else { "" }
    ))
}

fn simple_path_key(units: &[u16]) -> bool {
    !units.is_empty()
        && units.iter().all(|unit| {
            (b'0' as u16..=b'9' as u16).contains(unit)
                || (b'A' as u16..=b'Z' as u16).contains(unit)
                || (b'a' as u16..=b'z' as u16).contains(unit)
                || *unit == b'_' as u16
        })
}

#[derive(Clone, Debug)]
pub struct Row {
    pub path: String,
    pub segments: Json,
    pub a: Option<Node>,
    pub b: Option<Node>,
    pub status: &'static str,
}
impl Row {
    pub fn dto(&self, id: usize, full: bool) -> Json {
        let side = |node: &Option<Node>| match node {
            None => json!({"type":"Missing","display":"<不存在>","present":false}),
            Some(n) => {
                if full {
                    let mut dto = n.dto();
                    dto["present"] = json!(true);
                    dto
                } else {
                    let display = n.display();
                    let preview: String = display.chars().take(240).collect();
                    json!({"type":n.kind(),"display":preview,"truncated":display.chars().count()>240,"present":true,"line":n.line,"column":n.column})
                }
            }
        };
        json!({"id":id,"path":self.path,"segments":self.segments,"status":self.status,"a":side(&self.a),"b":side(&self.b)})
    }
}

pub struct Comparison {
    pub rows: Vec<Row>,
    pub incomplete: Vec<String>,
    pub warnings: Vec<crate::warnings::SourceWarning>,
}
impl Comparison {
    pub fn new(a: &Node, b: &Node) -> Self {
        let mut result = Self {
            rows: vec![],
            incomplete: vec![],
            warnings: vec![],
        };
        result.collect_incomplete(a, "$");
        result.collect_incomplete(b, "$");
        result.walk("$".into(), vec![], Some(a), Some(b), true, true);
        result
    }
    fn collect_incomplete(&mut self, node: &Node, path: &str) {
        match &node.value {
            Value::Unknown(_) => self.incomplete.push(path.into()),
            Value::Object(fields, complete) => {
                if !complete {
                    self.incomplete.push(path.into());
                }
                for (k, v) in fields {
                    self.collect_incomplete(v, &format!("{}[{}]", path, quoted(k)));
                }
            }
            Value::Array(items) => {
                for (i, v) in items.iter().enumerate() {
                    self.collect_incomplete(v, &format!("{path}[{i}]"));
                }
            }
            _ => {}
        }
    }
    fn walk(
        &mut self,
        path: String,
        segments: Vec<Json>,
        a: Option<&Node>,
        b: Option<&Node>,
        known_a: bool,
        known_b: bool,
    ) {
        let status = match (a, b) {
            (
                Some(Node {
                    value: Value::Unknown(_),
                    ..
                }),
                _,
            )
            | (
                _,
                Some(Node {
                    value: Value::Unknown(_),
                    ..
                }),
            ) => "NOT_COMPARABLE",
            (None, Some(_)) => {
                if known_a {
                    "ONLY_B"
                } else {
                    "NOT_COMPARABLE"
                }
            }
            (Some(_), None) => {
                if known_b {
                    "ONLY_A"
                } else {
                    "NOT_COMPARABLE"
                }
            }
            (Some(a), Some(b)) if a.kind() != b.kind() => "TYPE_CHANGED",
            (Some(a), Some(b)) => match (&a.value, &b.value) {
                (Value::Object(aa, ca), Value::Object(bb, cb)) => {
                    if !ca || !cb {
                        self.incomplete.push(path.clone());
                    }
                    let keys: BTreeSet<_> = aa.keys().chain(bb.keys()).cloned().collect();
                    if !keys.is_empty() {
                        for key in keys {
                            let mut next = segments.clone();
                            next.push(json!({"keyUnits":key}));
                            let display = if simple_path_key(&key) {
                                let name = String::from_utf16_lossy(&key);
                                format!("{path}.{name}")
                            } else {
                                format!("{path}[{}]", quoted(&key))
                            };
                            self.walk(display, next, aa.get(&key), bb.get(&key), *ca, *cb);
                        }
                        return;
                    }
                    if *ca && *cb { "SAME" } else { "NOT_COMPARABLE" }
                }
                (Value::Array(aa), Value::Array(bb)) if !aa.is_empty() || !bb.is_empty() => {
                    for index in 0..aa.len().max(bb.len()) {
                        let mut next = segments.clone();
                        next.push(json!({"index":index}));
                        self.walk(
                            format!("{path}[{index}]"),
                            next,
                            aa.get(index),
                            bb.get(index),
                            true,
                            true,
                        );
                    }
                    return;
                }
                (Value::JsNumber(x), Value::JsNumber(y)) => {
                    if (x.is_nan() && y.is_nan()) || x.to_bits() == y.to_bits() {
                        "SAME"
                    } else {
                        "VALUE_CHANGED"
                    }
                }
                (Value::JsonNumber(x), Value::JsonNumber(y)) => {
                    if number_key(x) == number_key(y) {
                        "SAME"
                    } else {
                        "VALUE_CHANGED"
                    }
                }
                _ => {
                    if a.value == b.value {
                        "SAME"
                    } else {
                        "VALUE_CHANGED"
                    }
                }
            },
            (None, None) => return,
        };
        self.rows.push(Row {
            path,
            segments: json!(segments),
            a: a.cloned(),
            b: b.cloned(),
            status,
        });
    }
    pub fn summary(&self) -> Json {
        let count = |status| self.rows.iter().filter(|r| r.status == status).count();
        json!({"total":self.rows.len(),"same":count("SAME"),"valueChanged":count("VALUE_CHANGED"),"typeChanged":count("TYPE_CHANGED"),"onlyA":count("ONLY_A"),"onlyB":count("ONLY_B"),"notComparable":count("NOT_COMPARABLE"),"differences":self.rows.iter().filter(|r|r.status!="SAME"&&r.status!="NOT_COMPARABLE").count()})
    }
    pub fn complete(&self) -> bool {
        self.incomplete.is_empty() && self.rows.iter().all(|r| r.status != "NOT_COMPARABLE")
    }
}
