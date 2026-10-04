import AppKit
import SwiftUI
import Testing
@testable import CompareUI

@Suite(.serialized)
struct UnicodeWorkspaceTests {
    @MainActor private func nativeEventTurn() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    @MainActor private func pump() async throws {
        for _ in 0..<5 {
            nativeEventTurn()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    @MainActor private func settle(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await pump() }
        try #require(condition())
    }
    @MainActor private func editors(_ view: NSView) -> [SourceTextView] {
        (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
    }
    @MainActor private func withWorkspace(nativeEdit: Bool, side: Bool = true, composedValue: String = "é", decomposedValue: String = "e\u{301}", settingsCover: Bool = false) async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let worker = DirectCoreWorker()
        let model = Workspace(clientFactory: { worker })
        let composed = "var env={label:'\(composedValue)'};"
        let decomposed = "var env={label:'\(decomposedValue)'};"
        // Swift equality deliberately treats these as the same. The existing
        // comparison core and native text input preserve the actual code units.
        try #require(composed == decomposed)
        try #require(!composed.utf16.elementsEqual(decomposed.utf16))
        model.a = composed; model.b = composed
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
        let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        window.contentView = host; #expect(!window.isVisible && !window.isKeyWindow)
        defer { model.cancel(); window.close(); window.contentView = nil }
        try await pump(); host.layoutSubtreeIfNeeded()
        let views = editors(host)
        try #require(views.count == 2)
        model.run()
        try await settle { !model.busy && model.summary != nil }
        try #require(model.summary?.same == 1 && !model.stale && model.complete)
        if settingsCover {
            model.filter = "all"
            try await settle { model.rows.count == 1 }
            model.selected = model.rows[0].id
            try await settle { model.detail != nil }
            model.showSettings(); try await pump()
            #expect(editors(host).count == 2)
            #expect(views.allSatisfy { !$0.isEditable && !$0.acceptsFirstResponder })
            #expect(!model.stale && model.summary?.same == 1)
            model.closeSettings(); try await pump()
            #expect(editors(host).elementsEqual(views, by: { $0 === $1 }))
        }
        let editor = views[side ? 0 : 1]
        if nativeEdit {
            let range = (editor.string as NSString).range(of: composedValue)
            try #require(range.location != NSNotFound)
            try #require(window.makeFirstResponder(editor))
            #expect(editor.enclosingScrollView?.layer?.borderWidth == 1)
            editor.insertText(decomposedValue, replacementRange: range)
        } else if side { model.a = decomposed } else { model.b = decomposed }
        try await pump(); host.layoutSubtreeIfNeeded()
        #expect((side ? model.a : model.b).utf16.elementsEqual(decomposed.utf16))
        #expect(editor.string.utf16.elementsEqual(decomposed.utf16), "The visible native editor must reflect the exact external source")
        #expect(model.stale, "A distinct UTF-16 source must invalidate the old comparison")
        #expect(model.resultControlsDisabled)
        #expect((side ? model.b : model.a).utf16.elementsEqual(composed.utf16))
        #expect(model.selected == nil && model.detail == nil)
        if nativeEdit {
            editor.undoManager?.undo(); try await pump()
            #expect(editor.string.utf16.elementsEqual(composed.utf16))
            #expect((side ? model.a : model.b).utf16.elementsEqual(composed.utf16) && model.stale)
            editor.undoManager?.redo(); try await pump()
            #expect(editor.string.utf16.elementsEqual(decomposed.utf16))
            #expect((side ? model.a : model.b).utf16.elementsEqual(decomposed.utf16) && model.stale)
        }
        model.run()
        try await settle { !model.busy && model.summary?.valueChanged == 1 }
        #expect(!model.stale && model.complete && model.summary?.same == 0)
        #expect(model.rows.count == 1 && model.rows.first?.status == "VALUE_CHANGED")
    }
    @Test @MainActor func externalCanonicalSourceChangeInvalidatesRealWorkspace() async throws {
        try await withWorkspace(nativeEdit: false)
    }
    @Test @MainActor func nativeCanonicalSourceEditInvalidatesRealWorkspace() async throws {
        try await withWorkspace(nativeEdit: true)
    }
    @Test @MainActor func settingsReturnAndNativeBEditPreserveExactUndoAndInvalidateSelection() async throws {
        try await withWorkspace(nativeEdit: true, side: false, settingsCover: true)
    }
    @Test @MainActor func equalLengthCanonicalSourceChangeInvalidatesRealWorkspace() async throws {
        try await withWorkspace(nativeEdit: false, composedValue: "\u{1e0a}\u{323}", decomposedValue: "\u{1e0c}\u{307}")
    }
    @Test @MainActor func canonicalYamlInputChangeInvalidatesFormattedOutput() async throws {
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.tool = .yaml; model.a = "label: 'é'\n"
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
        let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        window.contentView = host; #expect(!window.isVisible && !window.isKeyWindow)
        defer { model.cancel(); window.close(); window.contentView = nil }
        try await pump(); model.run()
        try await settle { !model.busy && !model.output.isEmpty }
        let oldOutput = model.output
        let input = try #require(editors(host).first)
        let exact = "label: 'e\u{301}'\n"
        model.a = exact; try await pump()
        #expect(input.string.utf16.elementsEqual(exact.utf16))
        #expect(model.stale && model.resultControlsDisabled)
        #expect(model.output.utf16.elementsEqual(oldOutput.utf16))
        model.run()
        try await settle { !model.busy && !model.stale }
        #expect(model.output.contains("e\u{301}"))
        #expect(!model.output.utf16.elementsEqual(oldOutput.utf16))
        #expect(editors(host).count == 2 && !editors(host)[1].isEditable)
    }
}
