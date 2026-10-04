import AppKit
import SwiftUI
import Testing
import CompareShared
@testable import CompareUI

@Suite(.serialized)
struct DesignSystemTests {
    @Test @MainActor func legacyAnimalAndDarkPreferencesMigrateWithoutTouchingOtherData() throws {
        let suite = "design-migration-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("cat", forKey: "appearance.avatar")
        defaults.set("dark", forKey: "appearance.theme")
        defaults.set("Operator", forKey: "appearance.username")
        defaults.set("untouched", forKey: "unrelated")
        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.avatar == .person && preferences.theme == .light)
        #expect(preferences.username == "Operator")
        #expect(defaults.string(forKey: "unrelated") == "untouched")
        #expect(AppAvatar.allCases == [.person, .compare, .terminal, .sparkles])
        #expect(AppTheme.allCases == [.light])
        defaults.set("John Doe", forKey: "appearance.username")
        #expect(AppPreferences(defaults: defaults).username == "John Doe") // A later deliberate local name is not a fake account.
    }
    @Test @MainActor func placeholderMigrationRunsOnceForFreshLegacyAndResetPreferences() throws {
        for legacy in [false, true] {
            let suite = "placeholder-migration-" + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            if legacy { defaults.set("John Doe", forKey: "appearance.username") }
            let preferences = AppPreferences(defaults: defaults)
            #expect(preferences.username.isEmpty)
            #expect(defaults.bool(forKey: "appearance.placeholderMigrated"))
            preferences.username = "John Doe"
            #expect(AppPreferences(defaults: defaults).username == "John Doe")
            preferences.reset()
            preferences.username = "John Doe"
            #expect(AppPreferences(defaults: defaults).username == "John Doe")
        }
    }
    @Test @MainActor func replacementSourceClearsOnlyItsOwnUndoHistory() {
        let a = SourceTextView(frame: .zero), b = SourceTextView(frame: .zero)
        a.isRichText = false; b.isRichText = false; a.allowsUndo = true; b.allowsUndo = true
        a.string = "var env={longName:1};"; b.string = "var env={b:2};"
        a.insertText("changed", replacementRange: NSRange(location: 9, length: 8))
        b.insertText("other", replacementRange: NSRange(location: 9, length: 1))
        #expect(a.undoManager?.canUndo == true && b.undoManager?.canUndo == true)
        a.replaceSource("x")
        #expect(a.string == "x" && a.undoManager?.canUndo == false)
        #expect(b.undoManager?.canUndo == true)
        b.undoManager?.undo()
        #expect(b.string == "var env={b:2};")
        a.insertText("y", replacementRange: NSRange(location: 1, length: 0))
        a.undoManager?.undo()
        #expect(a.string == "x")
    }
    @Test @MainActor func syntaxDecorationsPreserveUTF16SourceSelectionAndUndo() throws {
        let editor = SourceTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
        editor.isRichText = false; editor.allowsUndo = true
        let window = CheckedBackgroundTestWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.close(); window.contentView = nil }
        let source = "var env = {name:'配置🧪', port:123, unknown: undefined}; // comment\n"
        editor.string = source
        editor.setSelectedRange(NSRange(location: 4, length: 3))
        editor.refreshSyntax()
        #expect(Array(editor.string.utf16) == Array(source.utf16))
        #expect(editor.selectedRange() == NSRange(location: 4, length: 3))
        let tokens = SourceSyntax.tokens(in: source)
        #expect(tokens.contains { $0.kind == "string" && (source as NSString).substring(with: $0.range) == "'配置🧪'" })
        #expect(tokens.contains { $0.kind == "number" && (source as NSString).substring(with: $0.range) == "123" })
        #expect(tokens.last?.kind == "comment")
        editor.insertText("settings", replacementRange: editor.selectedRange())
        editor.refreshSyntax()
        #expect(editor.string.hasPrefix("var settings"))
        editor.undoManager?.undo()
        #expect(editor.string == source)
    }
    @Test @MainActor func lineNumbersHandleCRLFCRAndUTF16WithoutCountingWrappedLines() {
        let editor = SourceTextView(frame: .zero)
        editor.string = "a\r\n配置🧪\rthird\nlast"
        editor.refreshSyntax()
        #expect(editor.lineStarts == [0, 3, 8, 14])
        #expect(editor.lineNumber(at: 6) == 2 && editor.lineNumber(at: 8) == 3)
        editor.string = "é\nnext"; editor.refreshSyntax()
        #expect(editor.lineStarts == [0, 2])
        editor.string = "e\u{301}\nnext"; editor.refreshSyntax()
        #expect(editor.lineStarts == [0, 3])
    }
    @Test @MainActor func syntaxWorkIsBoundedAndDoesNotInterpretCode() {
        let source = String(repeating: "x", count: SourceSyntax.limit) + ";globalThis.executed=true;"
        let tokens = SourceSyntax.tokens(in: source)
        #expect(tokens.allSatisfy { NSMaxRange($0.range) <= SourceSyntax.limit })
        #expect(source.hasSuffix("globalThis.executed=true;"))
    }
    @Test @MainActor func unfinishedCommentHighlightingIsBounded() throws {
        let hostile = String(repeating: "/*x", count: 70_000)
        let began = ContinuousClock.now
        let tokens = SourceSyntax.tokens(in: hostile)
        #expect(tokens.count == 1 && tokens.first?.kind == "comment")
        #expect(tokens.first?.range.length == SourceSyntax.limit)
        #expect(began.duration(to: .now) < .seconds(2))
    }
    @Test func tableColumnsFitExactlyIncludingPaddingAndDetailEntry() {
        for width in [400.0, 620, 1008, 1168] {
            let columns = ResultColumns(width: width)
            #expect(abs(columns.path + columns.status + columns.value * 2 + 90 - width) < 0.01)
            #expect(columns.path > 0 && columns.status > 0 && columns.value > 0)
        }
    }
    @Test func emptyFilteredPageCannotClaimThatIncompleteInputsMatch() throws {
        let summary = try JSONDecoder().decode(Summary.self, from: Data(#"{"total":1,"same":1,"valueChanged":0,"typeChanged":0,"onlyA":0,"onlyB":0,"notComparable":0,"differences":0}"#.utf8))
        #expect(ComparisonPresentation.emptyTitle(summary: summary, complete: false, stale: false, error: false, search: "", filter: "differences") != "检查完成，内容一致。")
        #expect(ComparisonPresentation.emptyTitle(summary: summary, complete: true, stale: false, error: false, search: "not-found", filter: "differences") == "这里暂时没有匹配项。")
        #expect(ComparisonPresentation.emptyTitle(summary: summary, complete: true, stale: true, error: false, search: "", filter: "differences") == "输入已改变，请重新比较。")
        #expect(ComparisonPresentation.emptyTitle(summary: summary, complete: true, stale: false, error: false, search: "", filter: "differences") == "检查完成，内容一致。")
    }
}

// A review host can render beyond this Mac's 1512-point display without the
// system silently clamping the requested viewport. Production windows stay native.
@MainActor private final class ReviewWindow: CheckedBackgroundTestWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@Suite(.serialized)
struct LayoutTests {
    private let sizes: [NSSize] = [NSSize(width: 1280, height: 800), NSSize(width: 1440, height: 900), NSSize(width: 1720, height: 1000)]
    @MainActor private func settled(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(6)
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
    @MainActor private func render(_ model: Workspace, name: String, validateInputs: Bool = true, settingsSection: SettingsSection? = nil) async throws {
        AppAppearance.apply(.light)
        for size in sizes {
            let content: AnyView
            if let settingsSection { content = AnyView(SettingsView(section: settingsSection) {}.environmentObject(model.preferences).preferredColorScheme(.light)) }
            else { content = AnyView(WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light)) }
            let host = NSHostingView(rootView: content)
            let window = ReviewWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            host.sizingOptions = []
            window.contentView = host
            window.setContentSize(size)
            #expect(!window.isVisible && !window.isKeyWindow)
            defer { window.close(); window.contentView = nil }
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            #expect(abs(host.bounds.width - size.width) < 1)
            #expect(abs(host.bounds.height - size.height) < 1)
            func editors(_ view: NSView) -> [SourceTextView] {
                (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
            }
            let views = editors(host)
            for editor in views {
                if let layout = editor.layoutManager, let container = editor.textContainer { layout.ensureLayout(for: container) }
                editor.needsDisplay = true
                editor.displayIfNeeded()
            }
            if validateInputs && model.tool != .yaml && !(model.tool == .vault && model.vaultLive) && !model.showingSettings {
                try #require(views.count >= 2)
                #expect(views[0].string.utf16.elementsEqual(model.a.utf16))
                #expect(views[1].string.utf16.elementsEqual(model.b.utf16))
                let a = try #require(views[0].enclosingScrollView)
                let b = try #require(views[1].enclosingScrollView)
                let af = host.convert(a.bounds, from: a), bf = host.convert(b.bounds, from: b)
                #expect(abs(af.width - bf.width) < 1)
                #expect(abs(af.height - bf.height) < 1)
                #expect(abs(af.minY - bf.minY) < 1)
                #expect(af.minX >= 224 && bf.maxX <= size.width)
                #expect(af.height >= 60)
                #expect(bf.minX - af.maxX >= 40)
            }
            if let directory = ProcessInfo.processInfo.environment["CC_VISUAL_OUTPUT"] {
                let destination = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: destination.appendingPathComponent("\(name)-\(Int(size.width))x\(Int(size.height)).png"))
                if name == "incomplete-long", size.width == 1440 {
                    for (i, editor) in views.enumerated() {
                        let viewport = editor.visibleRect.intersection(editor.bounds)
                        let image = try #require(editor.bitmapImageRepForCachingDisplay(in: viewport))
                        editor.cacheDisplay(in: viewport, to: image)
                        try #require(image.representation(using: .png, properties: [:])).write(to: destination.appendingPathComponent("editor-viewport-\(i).png"))
                    }
                }
            }
        }
    }
    @Test @MainActor func pendingRealComparisonAndActualFileReadFailureFitThreeSizes() async throws {
        let worker = ReviewHeldCompare()
        let model = Workspace(clientFactory: { worker })
        model.a = "var env={sample:1};"; model.b = "var env={sample:2};"
        model.run()
        try await settled { worker.pending != nil }
        #expect(model.busy && model.canStop && model.summary == nil)
        try await render(model, name: "comparing")
        worker.finish(); try await settled { !model.busy && model.summary != nil }
        model.importFile(FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), side: true)
        try await settled { model.error && !model.importing }
        try await render(model, name: "read-error")
        model.cancel()
    }
    @Test @MainActor func emptyAndReadyInputsFitThreeWindowSizes() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        try await render(model, name: "empty")
        model.a = "var env={sample:1};"
        try await render(model, name: "one-side")
        model.b = "var env={sample:2};"
        try await render(model, name: "ready")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent(String(repeating: "synthetic-long-file-", count: 10) + ".js")
        try Data(model.a.utf8).write(to: file)
        model.importFile(file, side: true)
        try await settled { !model.importing && model.fileA == file }
        try await render(model, name: "long-file-name")
        model.cancel()
    }
    @Test @MainActor func actualIncompleteAndSearchResultsFitThreeWindowSizes() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        let long = String(repeating: "synthetic-long-value-", count: 120)
        let nested = String(repeating: "syntheticNested_", count: 14)
        model.a = "var env={same:'shared',change:1,kind:1,onlyA:true,unknown:unresolved,\(nested):{path:'\(long)'}};"
        model.b = "var env={same:'shared',change:2,kind:'1',onlyB:true,unknown:unresolved,\(nested):{path:'short'}};"
        model.run()
        try await settled { !model.busy && !model.rows.isEmpty }
        let summary = try #require(model.summary)
        #expect(summary.typeChanged == 1 && summary.onlyA == 1 && summary.onlyB == 1 && summary.notComparable == 1)
        #expect(!model.complete)
        try await render(model, name: "incomplete-long")
        model.selected = model.rows.first?.id; model.inspectSelection()
        try await settled { model.detail != nil }
        try await render(model, name: "selected-detail")
        model.search = "there-is-no-such-variable"; model.loadRows(reset: true)
        try await settled { model.rows.isEmpty && model.matched == 0 }
        try await render(model, name: "no-search-results")
        model.cancel()
    }
    @Test @MainActor func sameParseFailureAndManyResultsFitThreeWindowSizes() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a = "var env={sample:1};"; model.b = model.a; model.run()
        try await settled { !model.busy && model.summary != nil }
        try await render(model, name: "same")
        model.a = "var env={"; model.changed(); model.run()
        try await settled { !model.busy && model.error }
        try await render(model, name: "parse-error")
        model.a = "var env={" + (0..<401).map { "k\($0):\($0)" }.joined(separator: ",") + "};"
        model.b = "var env={" + (0..<401).map { "k\($0):\($0+1)" }.joined(separator: ",") + "};"
        model.run(); try await settled { !model.busy && model.matched == 401 && model.rows.count == 200 }
        try await render(model, name: "many-results")
        model.cancel()
    }
    @Test @MainActor func vaultYamlAndFullPageSettingsFitThreeWindowSizes() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.tool = .vault; model.vaultLive = true
        try await render(model, name: "vault-live", validateInputs: false)
        model.vaultLive = false; model.a = #"{"endpoint":"synthetic-A","port":123}"#; model.b = #"{"endpoint":"synthetic-B","port":"123"}"#
        model.run(); try await settled { !model.busy && model.matched == 2 }
        try await render(model, name: "vault-json")
        model.tool = .yaml; model.switchTool(); model.a = "# synthetic only\nname:  'shared'\nitems: [a,b]\n"; model.run()
        try await settled { !model.busy && !model.output.isEmpty }
        try await render(model, name: "yaml", validateInputs: false)
        model.showSettings()
        try await render(model, name: "settings", validateInputs: false)
        try await render(model, name: "settings-profile", validateInputs: false, settingsSection: .profile)
        try await render(model, name: "settings-appearance", validateInputs: false, settingsSection: .appearance)
        model.preferences.language = .english
        try await render(model, name: "settings-english", validateInputs: false)
        model.cancel()
    }
}

@MainActor private final class ReviewHeldCompare: WorkerSending {
    let core = DirectCoreWorker()
    var pending: (String, CheckedContinuation<String, any Error>)?
    func send(_ request: String) async throws -> String {
        let response = try await core.send(request)
        let operation = (try JSONSerialization.jsonObject(with: Data(request.utf8)) as? [String: Any])?["op"] as? String
        if operation == "compare" {
            return try await withCheckedThrowingContinuation { pending = (response, $0) }
        }
        return response
    }
    func finish() { let old = pending; pending = nil; old?.1.resume(returning: old!.0) }
    func abort() { core.abort(); let old = pending; pending = nil; old?.1.resume(throwing: CancellationError()) }
}
