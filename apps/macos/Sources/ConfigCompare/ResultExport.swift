import Foundation

enum ResultExportFormat: Sendable {
    case typedJSON
    case jsonArray
    case csv
    case html

    var fileExtension: String {
        switch self {
        case .typedJSON, .jsonArray: "json"
        case .csv: "csv"
        case .html: "html"
        }
    }
}

enum ResultExportRenderer {
    static func jsonArray(from report: [String: Any], vault: Bool = false) throws -> String {
        guard let rawRows = report["rows"] else {
            throw CocoaError(.coderInvalidValue, userInfo: [NSLocalizedDescriptionKey: "报告缺少结果行。"])
        }
        let rows: Any
        if let rawRows = rawRows as? [[String: Any]] {
            rows = rawRows.map { row in
                var row = row
                if let path = row["path"] as? String {
                    row["path"] = ResultPathDisplay.visible(path, vault: vault)
                }
                return row
            }
        } else {
            rows = rawRows
        }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func html(from report: [String: Any], title: String, sourceA: String, sourceB: String,
                     language: AppLanguage, vault: Bool) -> String {
        let rows = report["rows"] as? [[String: Any]] ?? []
        let summary = report["summary"] as? [String: Any] ?? [:]
        let complete = report["complete"] as? Bool ?? true
        let warningCount = report["warningCount"] as? Int ?? 0
        let rowMarkup = rows.map { row in
            let statusCode = string(row["status"])
            let status = statusLabel(statusCode, language: language)
            let path = ResultPathDisplay.visible(string(row["path"]), vault: vault)
            return """
            <tr class="status-\(htmlEscape(statusCode.lowercased()))">
              <td class="path"><code>\(htmlEscape(path))</code></td>
              <td><span class="badge">\(htmlEscape(status))</span></td>
              <td>\(valueMarkup(row["a"], language: language))</td>
              <td>\(valueMarkup(row["b"], language: language))</td>
            </tr>
            """
        }.joined()
        let summaryMarkup = [
            summaryItem("总计", key: "total", summary: summary, language: language),
            summaryItem("相同", key: "same", summary: summary, language: language),
            summaryItem("值变化", key: "valueChanged", summary: summary, language: language),
            summaryItem("类型变化", key: "typeChanged", summary: summary, language: language),
            summaryItem("仅 A", key: "onlyA", summary: summary, language: language),
            summaryItem("仅 B", key: "onlyB", summary: summary, language: language),
            summaryItem("无法比较", key: "notComparable", summary: summary, language: language)
        ].joined()
        let statusMessage = complete
            ? L10n.text("比较完成。", language: language)
            : L10n.text("结果不完整 · {0} 个诊断范围", arguments: [String((report["incompleteRanges"] as? [Any])?.count ?? 0)], language: language)
        let warningText = htmlEscape(L10n.text("源码警告 · {0} 项", arguments: [String(warningCount)], language: language))
        let warningMarkup = warningCount > 0 ? "<p class=\"warning\">\(warningText)</p>" : ""
        let locale = language == .english ? "en" : "zh-CN"
        return """
        <!doctype html>
        <html lang="\(locale)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(title))</title>
          <style>
            :root { color-scheme: light; --ink:#293044; --muted:#667085; --line:#eee7ef; --paper:#fff9f7; --card:#fff; --pink:#fde8ef; --rose:#6d2842; --mint:#eaf7ee; --peach:#fff1e6; --blue:#ebf3ff; --lavender:#f3eeff; --coral:#fff0ed; }
            * { box-sizing:border-box; }
            body { margin:0; padding:32px; background:var(--paper); color:var(--ink); font:14px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif; }
            main { max-width:1440px; margin:0 auto; }
            h1 { margin:0 0 6px; font-size:26px; }
            .meta { color:var(--muted); margin:0 0 22px; }
            .sources { display:flex; gap:12px; flex-wrap:wrap; margin:0 0 18px; }
            .source { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:10px 14px; min-width:260px; }
            .source strong { color:var(--rose); margin-right:6px; }
            .summary { display:flex; gap:8px; flex-wrap:wrap; margin:0 0 18px; }
            .metric { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:8px 12px; }
            .metric b { display:block; font-size:18px; }
            .metric span { color:var(--muted); font-size:12px; }
            .warning { color:#9c493f; background:var(--coral); border-radius:10px; padding:8px 12px; }
            .table-wrap { overflow:auto; background:var(--card); border:1px solid var(--line); border-radius:14px; }
            table { width:100%; border-collapse:separate; border-spacing:0; min-width:880px; }
            th, td { text-align:left; vertical-align:top; padding:12px 14px; border-bottom:1px solid var(--line); }
            th { color:var(--muted); font-weight:600; background:#fcfcff; position:sticky; top:0; }
            tr:last-child td { border-bottom:0; }
            td.path { width:34%; }
            code { font:13px "SF Mono",Monaco,monospace; white-space:pre-wrap; overflow-wrap:anywhere; }
            .badge { display:inline-block; border-radius:999px; padding:4px 9px; background:var(--pink); color:var(--rose); white-space:nowrap; }
            .value-type { color:var(--muted); font-size:11px; margin-bottom:3px; }
            .missing { color:var(--muted); font-style:italic; }
            .status-value_changed td { background:var(--peach); }
            .status-type_changed td { background:var(--pink); }
            .status-only_a td { background:var(--blue); }
            .status-only_b td { background:var(--lavender); }
            .status-not_comparable td { background:var(--coral); }
          </style>
        </head>
        <body>
          <main>
            <h1>\(htmlEscape(title))</h1>
            <p class="meta">\(htmlEscape(statusMessage))</p>
            <div class="sources">
              <div class="source"><strong>A</strong>\(htmlEscape(sourceA))</div>
              <div class="source"><strong>B</strong>\(htmlEscape(sourceB))</div>
            </div>
            <div class="summary">\(summaryMarkup)</div>
            \(warningMarkup)
            <div class="table-wrap">
              <table>
                <thead><tr><th>\(htmlEscape(L10n.text("路径", language: language)))</th><th>\(htmlEscape(L10n.text("状态", language: language)))</th><th>A</th><th>B</th></tr></thead>
                <tbody>\(rowMarkup)</tbody>
              </table>
            </div>
          </main>
        </body>
        </html>
        """
    }

    private static func summaryItem(_ keyText: String, key: String, summary: [String: Any], language: AppLanguage) -> String {
        let count = summary[key] as? Int ?? 0
        let label = L10n.text(keyText, language: language)
        return "<div class=\"metric\"><b>\(count)</b><span>\(htmlEscape(label))</span></div>"
    }

    private static func valueMarkup(_ raw: Any?, language: AppLanguage) -> String {
        guard let value = raw as? [String: Any] else { return "<span class=\"missing\">&lt;不存在&gt;</span>" }
        let present = value["present"] as? Bool ?? true
        let type = string(value["type"])
        let display = string(value["literal"]) == "" ? string(value["display"]) : string(value["literal"])
        let fallback = L10n.text("未知", language: language)
        let text = display.isEmpty ? (present ? fallback : "<不存在>") : display
        let typeMarkup = type.isEmpty ? "" : "<div class=\"value-type\">\(htmlEscape(type))</div>"
        return typeMarkup + (present ? "<code>\(htmlEscape(text))</code>" : "<span class=\"missing\">\(htmlEscape(text))</span>")
    }

    private static func statusLabel(_ status: String, language: AppLanguage) -> String {
        let key: String
        switch status {
        case "SAME": key = "相同"
        case "VALUE_CHANGED": key = "值变化"
        case "TYPE_CHANGED": key = "类型变化"
        case "ONLY_A": key = "仅 A"
        case "ONLY_B": key = "仅 B"
        default: key = "无法比较"
        }
        return L10n.text(key, language: language)
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value { return String(describing: value) }
        return ""
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
