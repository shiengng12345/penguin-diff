use compare_core::process;
use serde_json::{Value, json};

fn compare(a: &str, b: &str) -> Value {
    serde_json::from_str(&process(
        &json!({"op":"compare","kind":"js","a":a,"b":b}).to_string(),
    ))
    .unwrap()
}

#[test]
fn braced_surrogate_and_astral_escapes_preserve_utf16_identity() {
    for (a, b) in [
        (
            r"var env={'\u{D800}':'\u{DFFF}'};",
            r"var env={'\uD800':'\uDFFF'};",
        ),
        (
            r"var env={'\u{0000D800}':1,['\uD800']:2};",
            r"var env={'\uD800':2};",
        ),
        (
            r"var env={s:'\u{D83D}\u{DE00}',last:'\u{10FFFF}',zero:'\u{0}'};",
            r"var env={s:'\u{1F600}',last:'\uDBFF\uDFFF',zero:'\x00'};",
        ),
        (r"var env={s:'\u{D800}x'};", r"var env={s:'\uD800x'};"),
    ] {
        let result = compare(a, b);
        assert_eq!(result["ok"], true, "{result}");
        assert_eq!(result["complete"], true);
        assert_eq!(result["summary"]["differences"], 0);
    }
    for source in [
        r"var env={s:'\u{110000}'};",
        r"var env={s:'\u{4'};",
        r"var env={s:'\u{D800'};",
        r"var env={s:'\u{}'};",
        r"var env={s:'\u{D800 }'};",
        r"var env={s:'\u{+41}'};",
    ] {
        assert_eq!(
            compare(source, "var env={};")["error"]["code"],
            "JS_PARSE_ERROR"
        );
    }
}

#[test]
fn every_ecmascript_line_terminator_uses_utf8_byte_columns() {
    for separator in ["\n", "\r\n", "\r", "\u{2028}", "\u{2029}"] {
        let source =
            format!("\u{feff}var env={{{separator}  中文:1,{separator}  中文:2{separator}}};");
        let result = compare(&source, "var env={中文:2};");
        assert_eq!(result["ok"], true);
        assert_eq!(result["warnings"][0]["line"], 3, "{separator:?}: {result}");
        assert_eq!(result["warnings"][0]["column"], 3);
        assert_eq!(result["warnings"][0]["previousLine"], 2);
        assert_eq!(result["warnings"][0]["previousColumn"], 3);
        // Values start after the six UTF-8 key bytes and one colon.
        assert_eq!(result["rows"][0]["a"]["line"], 3);
        assert_eq!(result["rows"][0]["a"]["column"], 10);
    }
    let mixed = compare(
        "var env={\r  x:1,\u{2028}  x:2,\u{2029} y:3,\r\n y:4\n};",
        "var env={x:2,y:4};",
    );
    assert_eq!(mixed["warnings"][1]["line"], 5);
    assert_eq!(mixed["warnings"][1]["previousLine"], 4);
}
