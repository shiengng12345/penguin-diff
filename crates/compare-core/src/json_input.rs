use crate::{
    Error,
    model::{Node, Value, number_key},
};
use std::collections::BTreeMap;

pub fn parse(source: &str) -> Result<Node, Error> {
    let mut parser = Parser {
        source,
        // Preserve the parser's existing tolerance for consecutive leading BOMs.
        // The importer retains them; node/error offsets refer to the original text.
        pos: source.len() - source.trim_start_matches('\u{feff}').len(),
        nodes: 0,
        line_starts: std::iter::once(0)
            .chain(source.match_indices('\n').map(|(i, _)| i + 1))
            .collect(),
    };
    let value = parser.value(0)?;
    parser.space();
    if parser.pos != source.len() {
        return Err(parser.error("JSON_PARSE_ERROR"));
    }
    Ok(value)
}
struct Parser<'a> {
    source: &'a str,
    pos: usize,
    nodes: usize,
    line_starts: Vec<usize>,
}
impl Parser<'_> {
    fn error(&self, code: &str) -> Error {
        let line = self.line_starts.partition_point(|p| *p <= self.pos);
        Error {
            code: code.into(),
            message: "JSON 输入无法可靠解析".into(),
            line,
            column: self.pos - self.line_starts[line.saturating_sub(1)] + 1,
        }
    }
    fn space(&mut self) {
        while self
            .source
            .as_bytes()
            .get(self.pos)
            .is_some_and(|b| matches!(b, b' ' | b'\n' | b'\t' | b'\r'))
        {
            self.pos += 1;
        }
    }
    fn take(&mut self, b: u8) -> bool {
        self.space();
        if self.source.as_bytes().get(self.pos) == Some(&b) {
            self.pos += 1;
            true
        } else {
            false
        }
    }
    fn string(&mut self) -> Result<Vec<u16>, Error> {
        self.space();
        if !self.take(b'"') {
            return Err(self.error("JSON_PARSE_ERROR"));
        }
        let mut units = vec![];
        while self.pos < self.source.len() {
            let c = self.source[self.pos..].chars().next().unwrap();
            self.pos += c.len_utf8();
            match c {
                '"' => return Ok(units),
                '\\' => {
                    let escaped = *self
                        .source
                        .as_bytes()
                        .get(self.pos)
                        .ok_or_else(|| self.error("JSON_PARSE_ERROR"))?;
                    self.pos += 1;
                    match escaped {
                        b'"' => units.push(34),
                        b'\\' => units.push(92),
                        b'/' => units.push(47),
                        b'b' => units.push(8),
                        b'f' => units.push(12),
                        b'n' => units.push(10),
                        b'r' => units.push(13),
                        b't' => units.push(9),
                        b'u' => {
                            let end = self.pos + 4;
                            let hex = self
                                .source
                                .get(self.pos..end)
                                .ok_or_else(|| self.error("JSON_PARSE_ERROR"))?;
                            if !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
                                return Err(self.error("JSON_PARSE_ERROR"));
                            }
                            let u = u16::from_str_radix(hex, 16)
                                .map_err(|_| self.error("JSON_PARSE_ERROR"))?;
                            units.push(u);
                            self.pos = end;
                        }
                        _ => return Err(self.error("JSON_PARSE_ERROR")),
                    }
                }
                c if c < '\u{0020}' => return Err(self.error("JSON_PARSE_ERROR")),
                c => {
                    let mut buffer = [0; 2];
                    units.extend_from_slice(c.encode_utf16(&mut buffer));
                }
            }
        }
        Err(self.error("JSON_PARSE_ERROR"))
    }
    fn value(&mut self, depth: usize) -> Result<Node, Error> {
        self.nodes += 1;
        if depth > 128 || self.nodes > 100000 {
            return Err(self.error("RESOURCE_LIMIT"));
        }
        self.space();
        let start = self.pos;
        let value = match self.source.as_bytes().get(self.pos) {
            Some(b'"') => Value::String(self.string()?),
            Some(b'{') => {
                self.pos += 1;
                let mut fields = BTreeMap::new();
                if !self.take(b'}') {
                    loop {
                        let key = self.string()?;
                        if !self.take(b':') {
                            return Err(self.error("JSON_PARSE_ERROR"));
                        }
                        let value = self.value(depth + 1)?;
                        if fields.insert(key, value).is_some() {
                            return Err(self.error("JSON_DUPLICATE_KEY"));
                        }
                        if self.take(b'}') {
                            break;
                        }
                        if !self.take(b',') {
                            return Err(self.error("JSON_PARSE_ERROR"));
                        }
                    }
                }
                Value::Object(fields, true)
            }
            Some(b'[') => {
                self.pos += 1;
                let mut items = vec![];
                if !self.take(b']') {
                    loop {
                        items.push(self.value(depth + 1)?);
                        if self.take(b']') {
                            break;
                        }
                        if !self.take(b',') {
                            return Err(self.error("JSON_PARSE_ERROR"));
                        }
                    }
                }
                Value::Array(items)
            }
            _ if self.source[self.pos..].starts_with("true") => {
                self.pos += 4;
                Value::Boolean(true)
            }
            _ if self.source[self.pos..].starts_with("false") => {
                self.pos += 5;
                Value::Boolean(false)
            }
            _ if self.source[self.pos..].starts_with("null") => {
                self.pos += 4;
                Value::Null
            }
            Some(b'-' | b'0'..=b'9') => {
                if self.source.as_bytes()[self.pos] == b'-' {
                    self.pos += 1;
                }
                if self.source.as_bytes().get(self.pos) == Some(&b'0') {
                    self.pos += 1;
                } else {
                    let before = self.pos;
                    while self
                        .source
                        .as_bytes()
                        .get(self.pos)
                        .is_some_and(u8::is_ascii_digit)
                    {
                        self.pos += 1;
                    }
                    if before == self.pos {
                        return Err(self.error("JSON_PARSE_ERROR"));
                    }
                }
                if self.source.as_bytes().get(self.pos) == Some(&b'.') {
                    self.pos += 1;
                    let before = self.pos;
                    while self
                        .source
                        .as_bytes()
                        .get(self.pos)
                        .is_some_and(u8::is_ascii_digit)
                    {
                        self.pos += 1;
                    }
                    if before == self.pos {
                        return Err(self.error("JSON_PARSE_ERROR"));
                    }
                }
                if self
                    .source
                    .as_bytes()
                    .get(self.pos)
                    .is_some_and(|b| matches!(b, b'e' | b'E'))
                {
                    self.pos += 1;
                    if self
                        .source
                        .as_bytes()
                        .get(self.pos)
                        .is_some_and(|b| matches!(b, b'+' | b'-'))
                    {
                        self.pos += 1;
                    }
                    let before = self.pos;
                    while self
                        .source
                        .as_bytes()
                        .get(self.pos)
                        .is_some_and(u8::is_ascii_digit)
                    {
                        self.pos += 1;
                    }
                    if before == self.pos {
                        return Err(self.error("JSON_PARSE_ERROR"));
                    }
                }
                let raw = &self.source[start..self.pos];
                if number_key(raw).is_none() {
                    return Err(self.error("RESOURCE_LIMIT"));
                }
                Value::JsonNumber(raw.into())
            }
            _ => return Err(self.error("JSON_PARSE_ERROR")),
        };
        let line = self.line_starts.partition_point(|p| *p <= start);
        Ok(Node {
            value,
            line,
            column: start - self.line_starts[line.saturating_sub(1)] + 1,
        })
    }
}

pub fn root(mut node: Node, input_type: &str) -> Result<Node, Error> {
    let extract = |node: Node, key: &str| -> Result<Node, Error> {
        match node.value {
            Value::Object(mut fields, _) => fields
                .remove(&key.encode_utf16().collect::<Vec<_>>())
                .ok_or_else(|| Error::new("IMPORT_SCHEMA_INVALID", "输入包装不符合已选择类型")),
            _ => Err(Error::new("IMPORT_SCHEMA_INVALID", "输入根必须为对象")),
        }
    };
    match input_type {
        "plain-object" => {}
        "path-map" => {
            if let Value::Object(fields, _) = &node.value {
                if fields
                    .iter()
                    .any(|(k, v)| k.is_empty() || !matches!(v.value, Value::Object(..)))
                {
                    return Err(Error::new(
                        "IMPORT_SCHEMA_INVALID",
                        "路径映射必须由非空路径及纯配置对象组成",
                    ));
                }
            } else {
                return Err(Error::new("IMPORT_SCHEMA_INVALID", "路径映射根必须为对象"));
            }
        }
        "kv-v1-response" => node = extract(node, "data")?,
        "kv-v2-response" => node = extract(extract(node, "data")?, "data")?,
        _ => {
            return Err(Error::new(
                "IMPORT_SCHEMA_INVALID",
                "请选择明确的 Vault JSON 输入类型",
            ));
        }
    }
    if !matches!(node.value, Value::Object(..)) {
        return Err(Error::new(
            "NO_COMPARABLE_CONTENT",
            "没有可比较的配置对象；不将删除或空响应判为缺失",
        ));
    }
    Ok(node)
}
