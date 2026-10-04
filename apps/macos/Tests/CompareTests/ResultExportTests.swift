import Foundation
import Testing
@testable import CompareUI

@Suite(.serialized) struct ResultExportTests {
    @Test func jsonArrayContainsOnlyResultRows() throws {
        let report: [String: Any] = [
            "summary": ["total": 1, "same": 0],
            "rows": [[
                "id": 0,
                "path": #"$["."].auth.PORT"#,
                "status": "VALUE_CHANGED",
                "a": ["type": "Number", "literal": "1", "present": true],
                "b": ["type": "Number", "literal": "2", "present": true]
            ]]
        ]
        let output = try ResultExportRenderer.jsonArray(from: report, vault: true)
        let value = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]])
        #expect(value.count == 1)
        #expect(value[0]["path"] as? String == "$.auth.PORT")
        #expect(value[0]["status"] as? String == "VALUE_CHANGED")
        #expect(value[0]["a"] as? [String: Any] != nil)
        #expect(value[0]["summary"] == nil)
    }

    @Test func htmlReportIsReadableEscapedAndHidesVaultRootMarker() {
        let report: [String: Any] = [
            "complete": true,
            "summary": ["total": 1, "same": 0, "valueChanged": 1, "typeChanged": 0, "onlyA": 0, "onlyB": 0, "notComparable": 0],
            "rows": [[
                "path": #"$["."].auth.PORT"#,
                "status": "VALUE_CHANGED",
                "a": ["type": "String", "literal": "<script>alert(1)</script>", "present": true],
                "b": ["type": "String", "literal": "2", "present": true]
            ]]
        ]
        let html = ResultExportRenderer.html(from: report, title: "Vault 比较", sourceA: "A", sourceB: "B", language: .simplifiedChinese, vault: true)
        #expect(html.contains("$.auth.PORT"))
        #expect(!html.contains(#"$["."].auth.PORT"#))
        #expect(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        #expect(html.contains("<table"))
    }
}
