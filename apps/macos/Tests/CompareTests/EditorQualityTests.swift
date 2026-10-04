import AppKit
import SwiftUI
import Testing
@testable import CompareUI

@Suite(.serialized)
struct EditorQualityTests {
    @Test @MainActor func lineNumbersFollowNativeEditsAcrossCRLFAndUnicode() throws {
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false
        func verify() {
            editor.refreshSyntax()
            let units = Array(editor.string.utf16)
            var expected = [0], index = 0
            while index < units.count {
                if units[index] == 13 {
                    if index + 1 < units.count && units[index + 1] == 10 { index += 1 }
                    expected.append(index + 1)
                } else if units[index] == 10 { expected.append(index + 1) }
                index += 1
            }
            #expect(editor.lineStarts == expected)
            for offset in 0...units.count {
                #expect(editor.lineNumber(at: offset) == expected.filter { $0 <= offset }.count)
            }
        }
        for source in ["", "a\r\nb\nc\rd", "\r\n\r\n", "鹅🪿e\u{301}\n", "\r", "\n"] {
            editor.string = source; verify()
            for inserted in ["x", "\r", "\n", "\r\n", "鹅🪿", ""] {
                for offset in 0...(source as NSString).length {
                    editor.string = source
                    editor.textStorage?.replaceCharacters(in: NSRange(location: offset, length: 0), with: inserted)
                    verify()
                    editor.string = source
                    if offset < (source as NSString).length {
                        editor.textStorage?.replaceCharacters(in: NSRange(location: offset, length: 1), with: inserted)
                        verify()
                    }
                }
            }
        }
        editor.string = "first\r\nsecond\nthird\rlast"
        let storage = try #require(editor.textStorage)
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 2, length: 4), with: "\n\n")
        storage.replaceCharacters(in: NSRange(location: storage.length - 2, length: 1), with: "\r\n")
        storage.endEditing()
        verify()
        editor.replaceSource("replacement\n"); verify()
        // Deterministic edits accumulate instead of resetting between cases.
        // Batched storage notifications can merge widely separated edits.
        var state: UInt64 = 0xC0FFEE
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(state % UInt64(bound))
        }
        let fragments = ["", "x", "\r", "\n", "\r\n", "鹅", "e\u{301}"]
        for round in 0..<300 {
            if round.isMultiple(of: 3) { storage.beginEditing() }
            for _ in 0..<(round.isMultiple(of: 3) ? 3 : 1) {
                let location = next(storage.length + 1)
                let length = next(min(6, storage.length - location) + 1)
                storage.replaceCharacters(in: NSRange(location: location, length: length), with: fragments[next(fragments.count)])
            }
            if round.isMultiple(of: 3) { storage.endEditing() }
            verify()
        }
    }

    // A JS-only lexer must not paint legal YAML plain scalars as JS comments or
    // an unterminated JS string. Exercise the actual page's native editors.
    @Test @MainActor func yamlEditorsKeepURLsApostrophesAndHashFragmentsAsPlainText() async throws {
        let source = "endpoint: https://example.invalid/a#fragment\ncaption: it's fine\nliteral: path /* literal */\nquoted: 'it''s # quoted'\n# actual comment\n"
        let model = Workspace(clientFactory: { DirectCoreWorker() }, preferences: AppPreferences(defaults: nil))
        model.tool = .yaml; model.a = source; model.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.output.isEmpty && !model.error)
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences))
        let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.close(); window.contentView = nil; model.cancel() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func editors(_ view: NSView) -> [SourceTextView] {
            (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
        }
        let views = editors(host)
        try #require(views.count == 2)
        for (index, editor) in views.enumerated() {
            let text = editor.string as NSString
            let layout = try #require(editor.layoutManager)
            for literal in ["//", "#fragment", "'s fine", "/*"] {
                let position = text.range(of: literal).location
                try #require(position != NSNotFound)
                #expect(layout.temporaryAttributes(atCharacterIndex: position, effectiveRange: nil)[.foregroundColor] == nil, "YAML plain text was treated as JS syntax: \(literal)")
            }
            for literal in ["'it''s # quoted'", "# actual comment"] {
                let position = text.range(of: literal).location
                try #require(position != NSNotFound)
                #expect(layout.temporaryAttributes(atCharacterIndex: position, effectiveRange: nil)[.foregroundColor] != nil)
            }
            if let directory = ProcessInfo.processInfo.environment["CC_VISUAL_OUTPUT"] {
                layout.ensureLayout(for: try #require(editor.textContainer))
                let viewport = editor.visibleRect.intersection(editor.bounds)
                let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: viewport))
                editor.cacheDisplay(in: viewport, to: bitmap)
                let destination = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("yaml-editor-\(index).png"))
            }
        }
        #expect(views[0].string.utf16.elementsEqual(source.utf16))
        #expect(views[1].string.utf16.elementsEqual(model.output.utf16))
    }

    // An invalid JS single/double quote must not hide following lines as part of
    // its string. This is decoration only: the parser must still reject input.
    @Test @MainActor func unfinishedJSQuotesDoNotSwallowFollowingLines() {
        for quote in ["'", "\""] {
            let source = "const name = \(quote)unfinished\nvar env = {port:3000};"
            let tokens = SourceSyntax.tokens(in: source)
            #expect(tokens.contains { $0.kind == "keyword" && (source as NSString).substring(with: $0.range) == "var" })
            #expect(tokens.contains { $0.kind == "number" && (source as NSString).substring(with: $0.range) == "3000" })
            #expect(source.hasSuffix("var env = {port:3000};"))
        }
        let template = "const name = `first\nsecond`;"
        #expect(SourceSyntax.tokens(in: template).contains { $0.kind == "string" && (template as NSString).substring(with: $0.range) == "`first\nsecond`" })
    }

    @Test @MainActor func quoteContinuationsAndYAMLBlockBodiesRemainStrings() {
        let continued = "const name = 'first\\\r\nsecond'; var env = {port:3000};"
        let js = SourceSyntax.tokens(in: continued)
        #expect(js.contains { $0.kind == "string" && (continued as NSString).substring(with: $0.range) == "'first\\\r\nsecond'" })
        #expect(js.contains { $0.kind == "keyword" && (continued as NSString).substring(with: $0.range) == "var" })
        let yaml = "message: |\n  # literal body\n  it's https://example.invalid\nnext: true # real comment\n"
        let tokens = SourceSyntax.tokens(in: yaml, language: .yaml)
        for literal in ["# literal body", "it's https://example.invalid"] {
            let position = (yaml as NSString).range(of: literal).location
            #expect(tokens.contains { $0.kind == "string" && NSLocationInRange(position, $0.range) })
            #expect(!tokens.contains { $0.kind == "comment" && NSLocationInRange(position, $0.range) })
        }
        #expect(tokens.contains { $0.kind == "keyword" && (yaml as NSString).substring(with: $0.range) == "true" })
        #expect(tokens.contains { $0.kind == "comment" && (yaml as NSString).substring(with: $0.range) == "# real comment" })
    }

    @Test @MainActor func nativeSyntaxRefreshClearsShiftedColorsAndSupportsLanguageChanges() throws {
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false
        editor.string = "//" + String(repeating: "x", count: SourceSyntax.limit + 20)
        editor.refreshSyntax()
        let layout = try #require(editor.layoutManager)
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit - 1, effectiveRange: nil)[.foregroundColor] != nil)
        editor.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 0), with: "//shifted ")
        editor.refreshSyntax()
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 1, effectiveRange: nil)[.foregroundColor] == nil)
        editor.syntax = .json; editor.refreshSyntax()
        #expect(layout.temporaryAttributes(atCharacterIndex: 0, effectiveRange: nil)[.foregroundColor] == nil)
        editor.string = "endpoint: https://example.invalid\n"
        editor.syntax = .javascript; editor.refreshSyntax()
        let slash = (editor.string as NSString).range(of: "//").location
        #expect(layout.temporaryAttributes(atCharacterIndex: slash, effectiveRange: nil)[.foregroundColor] != nil)
        editor.syntax = .yaml; editor.refreshSyntax()
        #expect(layout.temporaryAttributes(atCharacterIndex: slash, effectiveRange: nil)[.foregroundColor] == nil)
    }

    @Test @MainActor func consecutiveEditsCannotLeaveShiftedColorsBeyondTheCap() throws {
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false
        editor.string = "//" + String(repeating: "x", count: SourceSyntax.limit + 200)
        editor.refreshSyntax()
        let storage = try #require(editor.textStorage), layout = try #require(editor.layoutManager)
        storage.replaceCharacters(in: NSRange(location: 100, length: 0), with: String(repeating: "a", count: 50))
        // No refresh between edits, as during deferred composition/merged updates.
        // Confirm native TextKit actually shifts existing temporary colors first.
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 20, effectiveRange: nil)[.foregroundColor] != nil)
        storage.replaceCharacters(in: NSRange(location: SourceSyntax.limit + 25, length: 0), with: String(repeating: "b", count: 100))
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 140, effectiveRange: nil)[.foregroundColor] != nil)
        editor.refreshSyntax()
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 140, effectiveRange: nil)[.foregroundColor] == nil)
        #expect(layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit - 1, effectiveRange: nil)[.foregroundColor] != nil)
        #expect(storage.length == SourceSyntax.limit + 352)
    }

    @Test @MainActor func fullNativeReplacementsNeverInheritColorsPastTheCap() throws {
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false
        let source = "//" + String(repeating: "x", count: SourceSyntax.limit + 50)
        let replacement = "//" + String(repeating: "y", count: SourceSyntax.limit + 50)
        let layout = try #require(editor.layoutManager), storage = try #require(editor.textStorage)
        var measurements: [[String: Any]] = []
        for mode in ["storage", "nativeInsert", "sourceReplacement"] {
            editor.string = source; editor.refreshSyntax()
            switch mode {
            case "storage": storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: replacement)
            case "nativeInsert": editor.insertText(replacement, replacementRange: NSRange(location: 0, length: storage.length))
            default: editor.replaceSource(replacement)
            }
            let before = layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 10, effectiveRange: nil)[.foregroundColor] != nil
            editor.refreshSyntax()
            let after = layout.temporaryAttributes(atCharacterIndex: SourceSyntax.limit + 10, effectiveRange: nil)[.foregroundColor] != nil
            #expect(!after)
            let exact = editor.string.utf16.elementsEqual(replacement.utf16)
            #expect(exact)
            measurements.append(["mode": mode, "coloredBeyondCapBeforeExplicitRefresh": before, "coloredBeyondCapAfterRefresh": after])
        }
        if let directory = ProcessInfo.processInfo.environment["CC_EDITOR_METRICS"] {
            let destination = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("replacement-colors.json"))
        }
    }

    // Native edits/undo on a large document, with repeatable timing evidence.
    // This measures the native input plus decoration path, not 60Hz UI frames.
    @Test @MainActor func largeDocumentEditsAndUndoRetainExactText() throws {
        let editor = SourceTextView(frame: .zero)
        editor.isRichText = false; editor.allowsUndo = true
        let source = String(repeating: "# synthetic line\n", count: 600_000)
        editor.string = source; editor.refreshSyntax()
        var samples: [Double] = []
        var insertSamples: [Double] = [], refreshSamples: [Double] = []
        func milliseconds(_ duration: Duration) -> Double {
            let elapsed = duration.components
            return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        }
        for _ in 0..<3 {
            editor.breakUndoCoalescing()
            let began = ContinuousClock.now
            editor.insertText("x", replacementRange: NSRange(location: (editor.string as NSString).length, length: 0))
            let inserted = ContinuousClock.now
            editor.refreshSyntax()
            let refreshed = ContinuousClock.now
            samples.append(milliseconds(began.duration(to: refreshed)))
            insertSamples.append(milliseconds(began.duration(to: inserted)))
            refreshSamples.append(milliseconds(inserted.duration(to: refreshed)))
            editor.undoManager?.undo(); editor.refreshSyntax()
            let exactTextRetained = editor.string.utf16.elementsEqual(source.utf16)
            #expect(exactTextRetained)
        }
        var inCapSamples: [Double] = [], inCapRefresh: [Double] = []
        for _ in 0..<2 {
            editor.breakUndoCoalescing()
            let began = ContinuousClock.now
            editor.insertText("x", replacementRange: NSRange(location: 100, length: 0))
            let inserted = ContinuousClock.now
            editor.refreshSyntax()
            let refreshed = ContinuousClock.now
            inCapSamples.append(milliseconds(began.duration(to: refreshed)))
            inCapRefresh.append(milliseconds(inserted.duration(to: refreshed)))
            editor.undoManager?.undo(); editor.refreshSyntax()
            let exact = editor.string.utf16.elementsEqual(source.utf16)
            #expect(exact)
        }
        #expect(editor.lineStarts.count == 600_001)
        if let directory = ProcessInfo.processInfo.environment["CC_EDITOR_METRICS"] {
            let destination = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let record: [String: Any] = ["syntheticUTF8Bytes": source.utf8.count, "logicalLines": 600_001, "nativeAppendAndRefreshMilliseconds": samples, "nativeInsertionMilliseconds": insertSamples, "decorationRefreshMilliseconds": refreshSamples, "inCapOffsetUTF16": 100, "nativeInCapInsertAndRefreshMilliseconds": inCapSamples, "inCapDecorationRefreshMilliseconds": inCapRefresh, "realWindowFramePerformanceMeasured": false, "fullSwiftUIBindingPathMeasured": false]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("large-edit.json"))
        }
        // Warm decorative work has a 100 ms local editing budget. It must not
        // rescan 10 MB merely because a character was appended beyond its cap.
        #expect(refreshSamples.dropFirst().allSatisfy { $0 < 100 })
    }
}
