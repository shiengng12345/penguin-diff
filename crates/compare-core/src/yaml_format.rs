use crate::Error;
use pretty_yaml::{
    config::{FormatOptions, LineBreak},
    format_text,
};
use std::collections::BTreeSet;
use yaml_parser::SyntaxKind;
use yaml_rust2::{
    Yaml,
    parser::{Event, MarkedEventReceiver, Parser},
    scanner::{Marker, TScalarStyle},
};

struct Frame {
    mapping: bool,
    key: bool,
    keys: BTreeSet<String>,
}
#[derive(Default)]
struct Events {
    events: Vec<Event>,
    stack: Vec<Frame>,
    error: Option<Error>,
    anchors: BTreeSet<usize>,
}
impl MarkedEventReceiver for Events {
    fn on_event(&mut self, event: Event, marker: Marker) {
        if event == Event::DocumentStart {
            self.anchors.clear();
        }
        match &event {
            Event::Scalar(_, _, anchor, _)
            | Event::MappingStart(anchor, _)
            | Event::SequenceStart(anchor, _)
                if *anchor > 0 =>
            {
                self.anchors.insert(*anchor);
            }
            Event::Alias(anchor) if !self.anchors.contains(anchor) => {
                self.error = Some(Error::new(
                    "YAML_PARSE_ERROR",
                    "别名必须引用同一文档中先前声明的 anchor",
                ));
                return;
            }
            _ => {}
        }
        if self.events.len() > 200000 || self.stack.len() > 128 {
            self.error = Some(Error::new("RESOURCE_LIMIT", "YAML 节点或深度超过限制"));
            return;
        }
        let starts = matches!(
            event,
            Event::Scalar(..)
                | Event::Alias(..)
                | Event::MappingStart(..)
                | Event::SequenceStart(..)
        );
        if starts
            && let Some(frame) = self.stack.last_mut()
            && frame.mapping
        {
            if frame.key {
                if let Event::Scalar(value, style, _, tag) = &event {
                    let string_key = *style != TScalarStyle::Plain
                        || matches!(Yaml::from_str(value), Yaml::String(_));
                    if !string_key || tag.is_some() {
                        self.error = Some(Error::new(
                            "YAML_KEY_UNSUPPORTED",
                            "当前格式化仅支持字符串 Key；不会自动改变 Key 类型",
                        ));
                    }
                    if !frame.keys.insert(value.clone()) {
                        self.error = Some(Error {
                            code: "YAML_DUPLICATE_KEY".into(),
                            message: "YAML 有重复 Key；未生成覆盖后的结果".into(),
                            line: marker.line(),
                            column: marker.col() + 1,
                        });
                    }
                } else {
                    self.error = Some(Error::new(
                        "YAML_KEY_UNSUPPORTED",
                        "当前不格式化集合或别名形式的 Key",
                    ));
                }
            }
            frame.key = !frame.key;
        }
        match event {
            Event::MappingStart(..) => self.stack.push(Frame {
                mapping: true,
                key: true,
                keys: BTreeSet::new(),
            }),
            Event::SequenceStart(..) => self.stack.push(Frame {
                mapping: false,
                key: false,
                keys: BTreeSet::new(),
            }),
            Event::MappingEnd | Event::SequenceEnd => {
                self.stack.pop();
            }
            _ => {}
        }
        self.events.push(event);
    }
}
fn events(source: &str) -> Result<Vec<Event>, Error> {
    let mut sink = Events::default();
    let mut parser = Parser::new_from_str(source);
    loop {
        let (event, marker) = parser.next_token().map_err(|e| Error {
            code: "YAML_PARSE_ERROR".into(),
            message: "YAML 语法错误；原内容已保留".into(),
            line: e.marker().line(),
            column: e.marker().col() + 1,
        })?;
        let done = event == Event::StreamEnd;
        sink.on_event(event, marker);
        if sink.error.is_some() || done {
            break;
        }
    }
    if let Some(error) = sink.error {
        return Err(error);
    }
    Ok(sink.events)
}
fn tokens(
    source: &str,
    kind: fn(SyntaxKind) -> bool,
) -> Result<Vec<(std::ops::Range<usize>, String)>, Error> {
    let tree = yaml_parser::parse(source)
        .map_err(|_| Error::new("YAML_PARSE_ERROR", "YAML CST 解析失败"))?;
    Ok(tree
        .descendants_with_tokens()
        .filter_map(|element| element.into_token())
        .filter(|token| kind(token.kind()))
        .map(|token| {
            let r = token.text_range();
            (
                u32::from(r.start()) as usize..u32::from(r.end()) as usize,
                token.text().to_string(),
            )
        })
        .collect())
}
fn comment_contexts(source: &str) -> Result<Vec<(String, usize, bool)>, Error> {
    let comments = tokens(source, |kind| kind == SyntaxKind::COMMENT)?;
    let meaningful = tokens(source, |kind| {
        !matches!(
            kind,
            SyntaxKind::WHITESPACE | SyntaxKind::COMMENT | SyntaxKind::COMMA
        )
    })?;
    Ok(comments
        .into_iter()
        .map(|(range, text)| {
            let prior = meaningful
                .iter()
                .filter(|(r, _)| r.end <= range.start)
                .count();
            let line_start = source[..range.start].rfind('\n').map_or(0, |p| p + 1);
            let inline = !source[line_start..range.start].trim().is_empty();
            (text, prior, inline)
        })
        .collect())
}
pub fn format(source: &str, indent: usize) -> Result<String, Error> {
    let before = events(source)?;
    let quote = |kind| {
        matches!(
            kind,
            SyntaxKind::SINGLE_QUOTED_SCALAR | SyntaxKind::DOUBLE_QUOTED_SCALAR
        )
    };
    let original_quotes = tokens(source, quote)?;
    let original_comments = comment_contexts(source)?;
    let mut options = FormatOptions::default();
    options.layout.indent_width = indent.clamp(2, 8);
    options.layout.print_width = 100;
    if source.contains("\r\n") {
        options.layout.line_break = LineBreak::Crlf;
    }
    options.language.format_comments = false;
    options.language.trim_trailing_whitespaces = false;
    options.language.trim_trailing_zero = false;
    let mut output = format_text(source, &options)
        .map_err(|_| Error::new("YAML_PARSE_ERROR", "无法安全格式化 YAML"))?;
    let formatted_quotes = tokens(&output, quote)?;
    if original_quotes.len() != formatted_quotes.len() {
        return Err(Error::new(
            "YAML_SEMANTICS_CHANGED",
            "格式化改变了字符串表示，已阻止输出",
        ));
    }
    for ((range, _), (_, original)) in formatted_quotes.into_iter().zip(original_quotes).rev() {
        output.replace_range(range, &original);
    }
    let after = events(&output)?;
    let comments = comment_contexts(&output)?;
    if before != after || original_comments != comments {
        return Err(Error::new(
            "YAML_SEMANTICS_CHANGED",
            "格式化前后内容、引用或注释不一致，已阻止输出",
        ));
    }
    Ok(output)
}
