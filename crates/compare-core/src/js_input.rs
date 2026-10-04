use crate::{
    Error,
    model::{Node, Value},
    warnings::{Budget, SourceWarning},
};
use oxc_allocator::Allocator;
use oxc_ast::ast::*;
use oxc_parser::{ParseOptions, Parser};
use oxc_span::{GetSpan, SourceType, Span};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone)]
enum Slot {
    Node(Node),
    Ref(usize),
}
#[derive(Clone)]
struct Object {
    fields: BTreeMap<Vec<u16>, Slot>,
    array: Option<Vec<Slot>>,
    complete: bool,
    span: Span,
}
pub struct Parsed {
    pub roots: BTreeMap<String, Node>,
    pub export_used: bool,
    pub export_is_named_alias: bool,
    pub complete: bool,
    pub warnings: Vec<SourceWarning>,
}

pub fn parse(source: &str) -> Result<Parsed, Error> {
    let allocator = Allocator::default();
    // process() supplies an 8 MiB thread stack. Leave 2 MiB for diagnostics,
    // bounded work between token advances, and returning through the grammar.
    let parsed = Parser::new(&allocator, source, SourceType::cjs())
        .with_options(ParseOptions {
            stack_budget: Some(6 * 1024 * 1024),
            cursor_budget: Some(3000000),
            ..ParseOptions::default()
        })
        .parse();
    if parsed.resource_exhausted {
        return Err(Error::new(
            "RESOURCE_LIMIT",
            "JavaScript 解析超过栈或步骤预算",
        ));
    }
    if !parsed.diagnostics.is_empty() {
        return Err(Error::new(
            "JS_PARSE_ERROR",
            "JavaScript 语法错误；不会执行或自动修复输入",
        ));
    }
    let mut evaluator = Evaluator {
        source,
        bindings: BTreeMap::new(),
        constants: BTreeSet::new(),
        heap: vec![],
        complete: true,
        export_used: false,
        warnings: vec![],
        warning_budget: Budget::default(),
        steps: 0,
        pending_lexical: BTreeSet::new(),
        line_starts: line_starts(source),
    };
    let exports = evaluator.object(Span::default());
    evaluator.bindings.insert("exports".into(), exports.clone());
    evaluator.bindings.insert("@module.exports".into(), exports);
    // Hoist var declarations and reserve lexical names before sequential evaluation.
    let mut declarations = BTreeMap::<String, String>::new();
    for statement in &parsed.program.body {
        if let Statement::VariableDeclaration(declaration) = statement {
            let kind = declaration.kind.as_str();
            for item in &declaration.declarations {
                if let BindingPattern::BindingIdentifier(id) = &item.id {
                    let name = id.name.to_string();
                    if declarations
                        .get(&name)
                        .is_some_and(|previous| previous != "var" || kind != "var")
                    {
                        return Err(Error::new("JS_BINDING_ERROR", "重复或冲突的词法绑定"));
                    }
                    declarations.insert(name.clone(), kind.to_string());
                    if kind == "var" {
                        evaluator
                            .bindings
                            .entry(name)
                            .or_insert(Slot::Node(Node::new(Value::Undefined)));
                    } else {
                        evaluator.pending_lexical.insert(name);
                    }
                }
            }
        }
    }
    for statement in &parsed.program.body {
        evaluator.statement(statement, true, 0)?;
    }
    // Preserve heap identity before freezing: equal-valued independent objects
    // must not be mistaken for an export alias of a named variable.
    let export_is_named_alias = match evaluator.bindings.get("@module.exports") {
        Some(Slot::Ref(export_id)) => evaluator.bindings.iter().any(|(name, value)| {
            name != "exports"
                && name != "@module.exports"
                && matches!(value, Slot::Ref(id) if id == export_id)
        }),
        _ => false,
    };
    let mut roots = BTreeMap::new();
    let mut budget = 100000usize;
    for (name, value) in &evaluator.bindings {
        if name == "exports" {
            continue;
        }
        roots.insert(
            if name == "@module.exports" {
                "module.exports".into()
            } else {
                name.clone()
            },
            evaluator.freeze(value, &mut BTreeSet::new(), 0, &mut budget)?,
        );
    }
    evaluator
        .warnings
        .sort_by_key(|warning| (warning.line, warning.column));
    Ok(Parsed {
        roots,
        export_used: evaluator.export_used,
        export_is_named_alias,
        complete: evaluator.complete,
        warnings: evaluator.warnings,
    })
}

struct Evaluator<'a> {
    source: &'a str,
    bindings: BTreeMap<String, Slot>,
    constants: BTreeSet<String>,
    heap: Vec<Object>,
    complete: bool,
    export_used: bool,
    steps: usize,
    pending_lexical: BTreeSet<String>,
    line_starts: Vec<usize>,
    warnings: Vec<SourceWarning>,
    warning_budget: Budget,
}
impl Evaluator<'_> {
    fn location(&self, span: Span) -> (usize, usize) {
        let pos = span.start as usize;
        let line = self.line_starts.partition_point(|p| *p <= pos);
        (line, pos - self.line_starts[line.saturating_sub(1)] + 1)
    }
    fn node(&self, value: Value, span: Span) -> Slot {
        let (line, column) = self.location(span);
        Slot::Node(Node {
            value,
            line,
            column,
        })
    }
    fn unknown(&self, span: Span) -> Slot {
        self.node(Value::Unknown("UNRESOLVED_EXPRESSION".into()), span)
    }
    fn object(&mut self, span: Span) -> Slot {
        let id = self.heap.len();
        self.heap.push(Object {
            fields: BTreeMap::new(),
            array: None,
            complete: true,
            span,
        });
        Slot::Ref(id)
    }
    fn poison(&mut self) {
        self.complete = false;
        for value in self.bindings.values_mut() {
            *value = Slot::Node(Node::unknown("UNKNOWN_OBJECT_IDENTITY"));
        }
        for object in &mut self.heap {
            object.complete = false;
            for value in object.fields.values_mut() {
                *value = Slot::Node(Node::unknown("UNRESOLVED_EXPRESSION"));
            }
            if let Some(array) = &mut object.array {
                for value in array {
                    *value = Slot::Node(Node::unknown("UNRESOLVED_EXPRESSION"));
                }
            }
        }
    }
    fn statement(
        &mut self,
        statement: &Statement,
        top_level: bool,
        depth: usize,
    ) -> Result<(), Error> {
        self.steps += 1;
        if depth > 128 || self.steps > 200000 {
            return Err(Error::new(
                "RESOURCE_LIMIT",
                "JavaScript 静态求值达到资源限制",
            ));
        }
        match statement {
            Statement::VariableDeclaration(declaration) => {
                if !top_level {
                    return Err(Error::new(
                        "UNSUPPORTED_SEMANTICS",
                        "当前静态支持范围不接受嵌套变量声明",
                    ));
                }
                for item in &declaration.declarations {
                    let BindingPattern::BindingIdentifier(id) = &item.id else {
                        self.poison();
                        continue;
                    };
                    let name = id.name.to_string();
                    if matches!(name.as_str(), "undefined" | "Infinity" | "NaN") {
                        return Err(Error::new(
                            "UNSUPPORTED_SEMANTICS",
                            "不支持重声明只读全局常量",
                        ));
                    }
                    if name == "module" || name == "exports" {
                        self.poison();
                        return Err(Error::new(
                            "UNSUPPORTED_SEMANTICS",
                            "顶层 module/exports 重声明不在当前静态支持范围",
                        ));
                    }
                    if self.constants.contains(&name) {
                        return Err(Error::new("JS_BINDING_ERROR", "重复或冲突的顶层绑定"));
                    }
                    if item.init.is_none() && declaration.kind.as_str() == "var" {
                        continue;
                    }
                    let value = if let Some(expression) = &item.init {
                        self.expression(expression, 0)?
                    } else {
                        self.node(Value::Undefined, item.span)
                    };
                    if declaration.kind.as_str() == "const" {
                        self.constants.insert(name.clone());
                    }
                    self.pending_lexical.remove(&name);
                    self.bindings.insert(name, value);
                }
            }
            Statement::ExpressionStatement(statement) => {
                self.expression(&statement.expression, 0)?;
            }
            Statement::EmptyStatement(_) => {}
            Statement::IfStatement(statement) => {
                validate_branch(&statement.consequent, depth + 1)?;
                if let Some(alternate) = &statement.alternate {
                    validate_branch(alternate, depth + 1)?;
                }
                let condition = self.expression(&statement.test, 0)?;
                match condition {
                    Slot::Node(Node {
                        value: Value::Boolean(true),
                        ..
                    }) => self.statement(&statement.consequent, false, depth + 1)?,
                    Slot::Node(Node {
                        value: Value::Boolean(false),
                        ..
                    }) => {
                        if let Some(other) = &statement.alternate {
                            self.statement(other, false, depth + 1)?;
                        }
                    }
                    _ => {
                        self.poison();
                        for value in self.bindings.values_mut() {
                            *value = Slot::Node(Node::unknown("UNKNOWN_OBJECT_IDENTITY"));
                        }
                    }
                }
            }
            Statement::BlockStatement(_) => {
                self.poison();
            }
            _ => self.poison(),
        }
        Ok(())
    }
    fn key(
        &mut self,
        key: &PropertyKey,
        computed: bool,
        depth: usize,
    ) -> Result<Option<Vec<u16>>, Error> {
        match key {
            PropertyKey::StaticIdentifier(id) if !computed => {
                Ok(Some(id.name.encode_utf16().collect()))
            }
            PropertyKey::StringLiteral(value) => Ok(Some(decode_string(self.source, value.span)?)),
            PropertyKey::NumericLiteral(value) => {
                Ok(Some(js_key_number(value.value).encode_utf16().collect()))
            }
            _ => {
                if let Some(expression) = key.as_expression() {
                    let value = self.expression(expression, depth + 1)?;
                    Ok(self.scalar_key(&value))
                } else {
                    Ok(None)
                }
            }
        }
    }
    fn scalar_key(&self, value: &Slot) -> Option<Vec<u16>> {
        match value {
            Slot::Node(Node {
                value: Value::String(v),
                ..
            }) => Some(v.clone()),
            Slot::Node(Node {
                value: Value::JsNumber(v),
                ..
            }) => Some(js_key_number(*v).encode_utf16().collect()),
            _ => None,
        }
    }
    fn property(&self, object: Slot, key: Vec<u16>, span: Span) -> Slot {
        match object {
            Slot::Ref(id) => {
                let object = &self.heap[id];
                if let Some(array) = &object.array {
                    if key == "length".encode_utf16().collect::<Vec<_>>() {
                        return self.node(Value::JsNumber(array.len() as f64), span);
                    }
                    if let Some(index) = array_index(&key) {
                        let value = array.get(index).cloned();
                        return match value {
                            Some(Slot::Node(Node {
                                value: Value::Hole, ..
                            }))
                            | None => self.node(Value::Undefined, span),
                            Some(value) => value,
                        };
                    }
                }
                if object.array.is_some() {
                    if !key.is_empty() && key.iter().all(|u| (48..=57).contains(u)) {
                        return self.node(Value::Undefined, span);
                    }
                    return object
                        .fields
                        .get(&key)
                        .cloned()
                        .unwrap_or_else(|| self.unknown(span));
                }
                object.fields.get(&key).cloned().unwrap_or_else(|| {
                    if matches!(
                        String::from_utf16_lossy(&key).as_str(),
                        "constructor"
                            | "toString"
                            | "valueOf"
                            | "__proto__"
                            | "hasOwnProperty"
                            | "isPrototypeOf"
                            | "propertyIsEnumerable"
                            | "toLocaleString"
                            | "__defineGetter__"
                            | "__defineSetter__"
                            | "__lookupGetter__"
                            | "__lookupSetter__"
                    ) {
                        self.unknown(span)
                    } else if object.complete {
                        self.node(Value::Undefined, span)
                    } else {
                        self.unknown(span)
                    }
                })
            }
            _ => self.unknown(span),
        }
    }
    fn write_property(&mut self, object: Slot, key: Vec<u16>, value: Slot) {
        match object {
            Slot::Ref(id) => {
                if String::from_utf16_lossy(&key) == "__proto__" {
                    self.poison();
                    return;
                }
                if let Some(array) = &mut self.heap[id].array {
                    if let Some(index) = array_index(&key)
                        && index < 100000
                    {
                        while array.len() <= index {
                            array.push(Slot::Node(Node::new(Value::Hole)));
                        }
                        array[index] = value;
                        return;
                    }
                    self.poison();
                    return;
                }
                self.heap[id].fields.insert(key, value);
            }
            _ => self.poison(),
        }
    }
    fn expression(&mut self, expression: &Expression, depth: usize) -> Result<Slot, Error> {
        self.steps += 1;
        if depth > 128 || self.steps > 200000 {
            return Err(Error::new(
                "RESOURCE_LIMIT",
                "JavaScript 静态求值达到资源限制",
            ));
        }
        let span = expression.span();
        let result = match expression {
            Expression::NullLiteral(_) => self.node(Value::Null, span),
            Expression::BooleanLiteral(v) => self.node(Value::Boolean(v.value), span),
            Expression::NumericLiteral(v) => self.node(Value::JsNumber(v.value), span),
            Expression::BigIntLiteral(v) => self.node(Value::BigInt(v.value.to_string()), span),
            Expression::StringLiteral(_) => {
                self.node(Value::String(decode_string(self.source, span)?), span)
            }
            Expression::Identifier(id) => {
                if id.name == "exports" {
                    self.export_used = true;
                }
                if self.pending_lexical.contains(id.name.as_str()) {
                    return Err(Error::new("JS_BINDING_ERROR", "词法变量在初始化之前被读取"));
                }
                if let Some(value) = self.bindings.get(id.name.as_str()) {
                    value.clone()
                } else {
                    match id.name.as_str() {
                        "undefined" => self.node(Value::Undefined, span),
                        "NaN" => self.node(Value::JsNumber(f64::NAN), span),
                        "Infinity" => self.node(Value::JsNumber(f64::INFINITY), span),
                        _ => {
                            self.complete = false;
                            self.unknown(span)
                        }
                    }
                }
            }
            Expression::ParenthesizedExpression(v) => self.expression(&v.expression, depth + 1)?,
            Expression::ObjectExpression(v) => {
                let target = self.object(span);
                let Slot::Ref(id) = target else {
                    unreachable!()
                };
                // Track explicit definitions within this literal. Spreads may
                // intentionally override fields and do not count as duplicates.
                let mut definitions = BTreeMap::new();
                for item in &v.properties {
                    match item {
                        ObjectPropertyKind::ObjectProperty(p) => {
                            let key = self.key(&p.key, p.computed, depth + 1)?;
                            let value = if p.kind == PropertyKind::Init && !p.method {
                                self.expression(&p.value, depth + 1)?
                            } else {
                                return Err(Error::new(
                                    "UNSUPPORTED_SEMANTICS",
                                    "不支持访问器或方法属性；不会执行输入",
                                ));
                            };
                            if let Some(key) = key {
                                if String::from_utf16_lossy(&key) == "__proto__"
                                    && !p.computed
                                    && !p.shorthand
                                {
                                    return Err(Error::new(
                                        "UNSUPPORTED_SEMANTICS",
                                        "不支持修改对象原型",
                                    ));
                                } else {
                                    if let Some(previous) = definitions.insert(key.clone(), p.span)
                                    {
                                        let (line, column) = self.location(p.span);
                                        let (previous_line, previous_column) =
                                            self.location(previous);
                                        let warning = SourceWarning {
                                            code: "JS_DUPLICATE_PROPERTY",
                                            message: "对象字面量包含重复属性，按源码顺序采用最后一次定义",
                                            side: None,
                                            line,
                                            column,
                                            previous_line,
                                            previous_column,
                                        };
                                        self.warning_budget.add(&warning)?;
                                        self.warnings.push(warning);
                                    }
                                    self.heap[id].fields.insert(key, value);
                                }
                            } else {
                                self.heap[id].complete = false;
                                for value in self.heap[id].fields.values_mut() {
                                    *value = Slot::Node(Node::unknown("UNRESOLVED_EXPRESSION"));
                                }
                            }
                        }
                        ObjectPropertyKind::SpreadProperty(p) => {
                            let spread = self.expression(&p.argument, depth + 1)?;
                            if let Slot::Ref(other) = spread {
                                let copy = self.heap[other].clone();
                                if copy.complete && copy.array.is_none() {
                                    self.heap[id].fields.extend(copy.fields);
                                } else {
                                    self.heap[id].complete = false;
                                    for value in self.heap[id].fields.values_mut() {
                                        *value = Slot::Node(Node::unknown("UNRESOLVED_EXPRESSION"));
                                    }
                                }
                            } else {
                                self.heap[id].complete = false;
                                for value in self.heap[id].fields.values_mut() {
                                    *value = Slot::Node(Node::unknown("UNRESOLVED_EXPRESSION"));
                                }
                            }
                        }
                    }
                }
                Slot::Ref(id)
            }
            Expression::ArrayExpression(v) => {
                let target = self.object(span);
                let Slot::Ref(id) = target else {
                    unreachable!()
                };
                let mut items = vec![];
                for item in &v.elements {
                    match item {
                        ArrayExpressionElement::Elision(_) => {
                            items.push(self.node(Value::Hole, span))
                        }
                        ArrayExpressionElement::SpreadElement(spread) => {
                            let value = self.expression(&spread.argument, depth + 1)?;
                            if let Slot::Ref(other) = value {
                                if let Some(array) = &self.heap[other].array {
                                    items.extend(array.iter().map(|item| {
                                        if matches!(
                                            item,
                                            Slot::Node(Node {
                                                value: Value::Hole,
                                                ..
                                            })
                                        ) {
                                            self.node(Value::Undefined, span)
                                        } else {
                                            item.clone()
                                        }
                                    }));
                                } else {
                                    self.complete = false;
                                    return Ok(self.unknown(span));
                                }
                            } else {
                                self.complete = false;
                                return Ok(self.unknown(span));
                            }
                        }
                        _ => {
                            if let Some(item) = item.as_expression() {
                                items.push(self.expression(item, depth + 1)?);
                            } else {
                                items.push(self.unknown(span));
                            }
                        }
                    }
                }
                self.heap[id].array = Some(items);
                Slot::Ref(id)
            }
            Expression::StaticMemberExpression(v) => {
                if matches!(&v.object,Expression::Identifier(id) if id.name=="module")
                    && v.property.name == "exports"
                {
                    self.export_used = true;
                    self.bindings["@module.exports"].clone()
                } else {
                    let object = self.expression(&v.object, depth + 1)?;
                    self.property(object, v.property.name.encode_utf16().collect(), span)
                }
            }
            Expression::ComputedMemberExpression(v) => {
                let object = self.expression(&v.object, depth + 1)?;
                let property = self.expression(&v.expression, depth + 1)?;
                if let Some(key) = self.scalar_key(&property) {
                    self.property(object, key, span)
                } else {
                    self.unknown(span)
                }
            }
            Expression::AssignmentExpression(v) => {
                if v.operator.as_str() != "=" {
                    self.poison();
                    self.complete = false;
                    return Ok(self.unknown(span));
                }
                let captured = match &v.left {
                    AssignmentTarget::StaticMemberExpression(target)
                        if !(matches!(&target.object,Expression::Identifier(id) if id.name=="module")
                            && target.property.name == "exports") =>
                    {
                        Some((
                            self.expression(&target.object, depth + 1)?,
                            target.property.name.encode_utf16().collect::<Vec<_>>(),
                        ))
                    }
                    AssignmentTarget::ComputedMemberExpression(target) => {
                        let object = self.expression(&target.object, depth + 1)?;
                        let property = self.expression(&target.expression, depth + 1)?;
                        self.scalar_key(&property).map(|key| (object, key))
                    }
                    _ => None,
                };
                let value = self.expression(&v.right, depth + 1)?;
                match &v.left {
                    AssignmentTarget::AssignmentTargetIdentifier(id) => {
                        if matches!(
                            id.name.as_str(),
                            "undefined" | "NaN" | "Infinity" | "module"
                        ) {
                            return Err(Error::new(
                                "UNSUPPORTED_SEMANTICS",
                                "不支持重绑定特殊全局变量",
                            ));
                        }
                        if self.pending_lexical.contains(id.name.as_str()) {
                            return Err(Error::new("JS_BINDING_ERROR", "词法变量在初始化前被赋值"));
                        }
                        if !self.bindings.contains_key(id.name.as_str()) {
                            return Err(Error::new(
                                "UNSUPPORTED_SEMANTICS",
                                "不支持向未声明变量赋值",
                            ));
                        }
                        if self.constants.contains(id.name.as_str()) {
                            return Err(Error::new("JS_BINDING_ERROR", "const 绑定不能重赋值"));
                        }
                        self.bindings.insert(id.name.to_string(), value.clone());
                    }
                    AssignmentTarget::StaticMemberExpression(target) => {
                        if matches!(&target.object,Expression::Identifier(id) if id.name=="module")
                            && target.property.name == "exports"
                        {
                            self.export_used = true;
                            self.bindings
                                .insert("@module.exports".into(), value.clone());
                        } else if let Some((object, key)) = captured {
                            self.write_property(object, key, value.clone());
                        }
                    }
                    AssignmentTarget::ComputedMemberExpression(_) => {
                        if let Some((object, key)) = captured {
                            self.write_property(object, key, value.clone());
                        } else {
                            self.poison();
                        }
                    }
                    _ => self.poison(),
                }
                value
            }
            Expression::UnaryExpression(v) => {
                if v.operator.as_str() == "delete" {
                    let target = match &v.argument {
                        Expression::StaticMemberExpression(member) => Some((
                            self.expression(&member.object, depth + 1)?,
                            member.property.name.encode_utf16().collect::<Vec<_>>(),
                        )),
                        Expression::ComputedMemberExpression(member) => {
                            let object = self.expression(&member.object, depth + 1)?;
                            let property = self.expression(&member.expression, depth + 1)?;
                            self.scalar_key(&property).map(|key| (object, key))
                        }
                        _ => None,
                    };
                    if let Some((Slot::Ref(id), key)) = target {
                        if let Some(array) = &mut self.heap[id].array {
                            if let Some(index) = array_index(&key) {
                                if let Some(slot) = array.get_mut(index) {
                                    *slot = Slot::Node(Node::new(Value::Hole));
                                }
                            } else {
                                self.poison();
                            }
                        } else {
                            self.heap[id].fields.remove(&key);
                        }
                        return Ok(self.node(Value::Boolean(true), span));
                    }
                    self.poison();
                    self.complete = false;
                    return Ok(self.unknown(span));
                }
                let value = self.expression(&v.argument, depth + 1)?;
                match (value, v.operator.as_str()) {
                    (
                        Slot::Node(Node {
                            value: Value::JsNumber(n),
                            ..
                        }),
                        "-",
                    ) => self.node(Value::JsNumber(-n), span),
                    (
                        Slot::Node(Node {
                            value: Value::JsNumber(n),
                            ..
                        }),
                        "+",
                    ) => self.node(Value::JsNumber(n), span),
                    (
                        Slot::Node(Node {
                            value: Value::Boolean(n),
                            ..
                        }),
                        "!",
                    ) => self.node(Value::Boolean(!n), span),
                    (_, "void") => self.node(Value::Undefined, span),
                    _ => self.unknown(span),
                }
            }
            Expression::BinaryExpression(v) => {
                let a = self.expression(&v.left, depth + 1)?;
                let b = self.expression(&v.right, depth + 1)?;
                match (a, b) {
                    (
                        Slot::Node(Node {
                            value: Value::JsNumber(a),
                            ..
                        }),
                        Slot::Node(Node {
                            value: Value::JsNumber(b),
                            ..
                        }),
                    ) => match v.operator.as_str() {
                        "+" => self.node(Value::JsNumber(a + b), span),
                        "-" => self.node(Value::JsNumber(a - b), span),
                        "*" => self.node(Value::JsNumber(a * b), span),
                        "/" => self.node(Value::JsNumber(a / b), span),
                        _ => self.unknown(span),
                    },
                    (
                        Slot::Node(Node {
                            value: Value::String(mut a),
                            ..
                        }),
                        Slot::Node(Node {
                            value: Value::String(b),
                            ..
                        }),
                    ) if v.operator.as_str() == "+" => {
                        a.extend(b);
                        self.node(Value::String(a), span)
                    }
                    _ => self.unknown(span),
                }
            }
            Expression::ConditionalExpression(v) => {
                let condition = self.expression(&v.test, depth + 1)?;
                match condition {
                    Slot::Node(Node {
                        value: Value::Boolean(true),
                        ..
                    }) => self.expression(&v.consequent, depth + 1)?,
                    Slot::Node(Node {
                        value: Value::Boolean(false),
                        ..
                    }) => self.expression(&v.alternate, depth + 1)?,
                    _ => {
                        self.poison();
                        self.unknown(span)
                    }
                }
            }
            Expression::SequenceExpression(v) => {
                let mut value = self.node(Value::Undefined, span);
                for item in &v.expressions {
                    value = self.expression(item, depth + 1)?;
                }
                value
            }
            Expression::CallExpression(_)
            | Expression::NewExpression(_)
            | Expression::ImportExpression(_)
            | Expression::AwaitExpression(_)
            | Expression::UpdateExpression(_)
            | Expression::TaggedTemplateExpression(_) => {
                self.poison();
                self.unknown(span)
            }
            _ => {
                self.poison();
                self.unknown(span)
            }
        };
        if matches!(
            &result,
            Slot::Node(Node {
                value: Value::Unknown(_),
                ..
            })
        ) {
            self.complete = false;
        }
        Ok(result)
    }

    fn freeze(
        &self,
        value: &Slot,
        seen: &mut BTreeSet<usize>,
        depth: usize,
        budget: &mut usize,
    ) -> Result<Node, Error> {
        if depth > 128 || *budget == 0 {
            return Err(Error::new("RESOURCE_LIMIT", "引用展开达到资源限制"));
        }
        *budget -= 1;
        Ok(match value {
            Slot::Node(node) => node.clone(),
            Slot::Ref(id) => {
                if !seen.insert(*id) {
                    return Ok(Node::unknown("CYCLIC_REFERENCE"));
                }
                let object = &self.heap[*id];
                let value = if let Some(items) = &object.array {
                    Value::Array(
                        items
                            .iter()
                            .map(|item| self.freeze(item, seen, depth + 1, budget))
                            .collect::<Result<Vec<_>, _>>()?,
                    )
                } else {
                    Value::Object(
                        object
                            .fields
                            .iter()
                            .map(|(key, item)| {
                                self.freeze(item, seen, depth + 1, budget)
                                    .map(|v| (key.clone(), v))
                            })
                            .collect::<Result<BTreeMap<_, _>, _>>()?,
                        object.complete,
                    )
                };
                seen.remove(id);
                let Slot::Node(node) = self.node(value, object.span) else {
                    unreachable!()
                };
                node
            }
        })
    }
}

fn validate_branch(statement: &Statement, depth: usize) -> Result<(), Error> {
    let mut pending = vec![(statement, depth)];
    let mut visited = 0usize;
    while let Some((statement, depth)) = pending.pop() {
        visited += 1;
        if depth > 128 || visited > 200000 {
            return Err(Error::new(
                "RESOURCE_LIMIT",
                "JavaScript 条件分支达到资源限制",
            ));
        }
        match statement {
            Statement::ExpressionStatement(_) | Statement::EmptyStatement(_) => {}
            Statement::IfStatement(s) => {
                if let Some(other) = &s.alternate {
                    pending.push((other, depth + 1));
                }
                pending.push((&s.consequent, depth + 1));
            }
            Statement::BlockStatement(s) => {
                pending.extend(s.body.iter().rev().map(|item| (item, depth + 1)));
            }
            _ => {
                return Err(Error::new(
                    "UNSUPPORTED_SEMANTICS",
                    "条件分支中的声明及复杂控制语句不在静态支持范围；未执行分支也不会静默忽略",
                ));
            }
        }
    }
    Ok(())
}
fn js_key_number(n: f64) -> String {
    if n == 0.0 {
        return "0".into();
    }
    if n.is_nan() {
        return "NaN".into();
    }
    if n.is_infinite() {
        return if n.is_sign_negative() {
            "-Infinity"
        } else {
            "Infinity"
        }
        .into();
    }
    dragonbox_ecma::Buffer::new().format(n).to_string()
}
fn array_index(key: &[u16]) -> Option<usize> {
    let text = String::from_utf16(key).ok()?;
    let index: usize = text.parse().ok()?;
    (index.to_string() == text && index < 4294967295).then_some(index)
}

fn line_starts(source: &str) -> Vec<usize> {
    let mut starts = vec![0];
    let mut chars = source.char_indices().peekable();
    while let Some((index, value)) = chars.next() {
        match value {
            '\r' => {
                let end = if chars.peek().is_some_and(|(_, c)| *c == '\n') {
                    chars.next().unwrap().0 + 1
                } else {
                    index + 1
                };
                starts.push(end);
            }
            '\n' => starts.push(index + 1),
            '\u{2028}' | '\u{2029}' => starts.push(index + 3),
            _ => {}
        }
    }
    starts
}

fn decode_string(source: &str, span: Span) -> Result<Vec<u16>, Error> {
    let raw = &source[span.start as usize..span.end as usize];
    let body = &raw[1..raw.len() - 1];
    let mut units = vec![];
    let mut chars = body.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '\\' {
            let mut buffer = [0; 2];
            units.extend_from_slice(c.encode_utf16(&mut buffer));
            continue;
        }
        let escaped = chars
            .next()
            .ok_or_else(|| Error::new("JS_PARSE_ERROR", "字符串转义不完整"))?;
        match escaped {
            'n' => units.push(10),
            'r' => units.push(13),
            't' => units.push(9),
            'b' => units.push(8),
            'f' => units.push(12),
            'v' => units.push(11),
            '0' => {
                if chars.peek().is_some_and(char::is_ascii_digit) {
                    return Err(Error::new("UNSUPPORTED_SEMANTICS", "不支持旧式八进制转义"));
                }
                units.push(0)
            }
            '\n' | '\u{2028}' | '\u{2029}' => {}
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
            }
            'u' | 'x' => {
                let mut hex = String::new();
                if escaped == 'u' && chars.peek() == Some(&'{') {
                    chars.next();
                    let mut closed = false;
                    for c in chars.by_ref() {
                        if c == '}' {
                            closed = true;
                            break;
                        }
                        hex.push(c);
                    }
                    if !closed
                        || hex.is_empty()
                        || !hex.bytes().all(|byte| byte.is_ascii_hexdigit())
                    {
                        return Err(Error::new("JS_PARSE_ERROR", "Unicode 转义无效"));
                    }
                    let code_point = u32::from_str_radix(&hex, 16)
                        .ok()
                        .filter(|value| *value <= 0x10ffff)
                        .ok_or_else(|| Error::new("JS_PARSE_ERROR", "Unicode 转义无效"))?;
                    if code_point <= 0xffff {
                        // ECMAScript strings contain UTF-16 code units, including
                        // lone surrogates; Rust char cannot represent those.
                        units.push(code_point as u16);
                    } else {
                        let scalar = char::from_u32(code_point).unwrap();
                        let mut buffer = [0; 2];
                        units.extend_from_slice(scalar.encode_utf16(&mut buffer));
                    }
                } else {
                    for _ in 0..if escaped == 'u' { 4 } else { 2 } {
                        hex.push(
                            chars.next().ok_or_else(|| {
                                Error::new("JS_PARSE_ERROR", "Unicode 转义不完整")
                            })?,
                        );
                    }
                    units.push(
                        u16::from_str_radix(&hex, 16)
                            .map_err(|_| Error::new("JS_PARSE_ERROR", "Unicode 转义无效"))?,
                    );
                }
            }
            '1'..='9' => {
                return Err(Error::new(
                    "UNSUPPORTED_SEMANTICS",
                    "旧式八进制字符串转义不在支持范围",
                ));
            }
            c => {
                let mut buffer = [0; 2];
                units.extend_from_slice(c.encode_utf16(&mut buffer));
            }
        }
    }
    Ok(units)
}

#[cfg(test)]
mod string_escape_guards {
    use super::*;

    #[test]
    fn decoder_itself_requires_closed_ascii_hex_braces() {
        for source in [
            r"'\u{4'",
            r"'\u{D800'",
            r"'\u{+41}'",
            r"'\u{}'",
            r"'\u{D800 }'",
        ] {
            assert_eq!(
                decode_string(source, Span::new(0, source.len() as u32))
                    .unwrap_err()
                    .code,
                "JS_PARSE_ERROR"
            );
        }
        let source = r"'\u{D800}x'";
        assert_eq!(
            decode_string(source, Span::new(0, source.len() as u32)).unwrap(),
            vec![0xd800, 120]
        );
    }
}
