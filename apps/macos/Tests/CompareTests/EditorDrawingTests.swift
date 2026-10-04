import AppKit
import SwiftUI
import Testing
@testable import CompareUI

@Suite(.serialized)
struct EditorDrawingTests {
    private let source = "var env = {hello: 123};\nvar happy = {nested: {value: 456}};"

    // Inspect actual pixels in the code region of a complete parent capture.
    // A local editor capture alone misses an overlapping ruler background.
    @MainActor private func assertCodeVisible(_ parent: NSView, editor: SourceTextView, name: String) throws {
        let viewport = editor.visibleRect.intersection(editor.bounds)
        let textRect = NSRect(x: viewport.minX + 12, y: viewport.minY + 12,
                              width: min(330, viewport.width - 24), height: min(50, viewport.height - 24))
        try #require(textRect.width > 30 && textRect.height > 20)
        let box = parent.convert(textRect, from: editor)
        let bitmap = try #require(parent.bitmapImageRepForCachingDisplay(in: parent.bounds))
        parent.cacheDisplay(in: parent.bounds, to: bitmap)
        let sx = CGFloat(bitmap.pixelsWide) / parent.bounds.width
        let sy = CGFloat(bitmap.pixelsHigh) / parent.bounds.height
        let left = Int(floor((box.minX - parent.bounds.minX) * sx))
        let top = Int(floor((parent.isFlipped ? box.minY - parent.bounds.minY : parent.bounds.maxY - box.maxY) * sy))
        var ink = 0
        for y in max(0, top)..<min(bitmap.pixelsHigh, top + Int(box.height * sy)) {
            for x in max(0, left)..<min(bitmap.pixelsWide, left + Int(box.width * sx)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if color.alphaComponent > 0.8 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.75 { ink += 1 }
            }
        }
        if let output = ProcessInfo.processInfo.environment["CC_VISUAL_OUTPUT"] {
            let folder = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent(name + ".png"))
            try Data("\(ink)\n".utf8).write(to: folder.appendingPathComponent(name + ".ink.txt"))
        }
        #expect(ink > 200, "\(name): neighboring code must remain visible in the complete capture")
    }

    @Test @MainActor func lineNumberBackgroundNeverErasesSourceAfterResize() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 220))
        let scroll = NSScrollView(frame: NSRect(x: 40, y: 40, width: 360, height: 140))
        scroll.wantsLayer = true
        scroll.layer?.masksToBounds = true
        scroll.drawsBackground = true
        scroll.backgroundColor = AppPalette.codeNS
        let editor = SourceTextView(frame: NSRect(origin: .zero, size: scroll.bounds.size))
        editor.isRichText = false
        editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        editor.textColor = AppPalette.inkNS
        editor.backgroundColor = AppPalette.codeNS
        editor.textContainerInset = NSSize(width: 12, height: 12)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.textContainer?.widthTracksTextView = true
        editor.string = source
        scroll.documentView = editor
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.verticalRulerView = LineNumberRuler(textView: editor)
        editor.refreshSyntax()
        parent.addSubview(scroll)
        let window = CheckedBackgroundTestWindow(contentRect: parent.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = parent
        #expect(!window.isVisible)
        defer { window.close(); window.contentView = nil }
        try await Task.sleep(for: .milliseconds(100))
        parent.layoutSubtreeIfNeeded()
        try assertCodeVisible(parent, editor: editor, name: "ruler-native-initial")
        scroll.frame.size = NSSize(width: 320, height: 120)
        scroll.tile()
        parent.layoutSubtreeIfNeeded()
        try assertCodeVisible(parent, editor: editor, name: "ruler-native-resized")
        #expect(editor.string.utf16.elementsEqual(source.utf16))
    }

    @Test @MainActor func hostedCodeRemainsVisibleAfterSourceReplacementAndNativeInsertion() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppAppearance.apply(.light)
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.a = source; model.b = source
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
        let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        #expect(!window.isVisible)
        defer { window.close(); window.contentView = nil; model.cancel() }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        func editors(_ view: NSView) -> [SourceTextView] {
            (view as? SourceTextView).map { [$0] } ?? view.subviews.flatMap { editors($0) }
        }
        let views = editors(host)
        try #require(views.count == 2)
        for (index, editor) in views.enumerated() { try assertCodeVisible(host, editor: editor, name: "ruler-hosted-initial-\(index)") }
        let replacement = "var changed = {hello: 123};\nvar happy = {nested: {value: 456}};"
        model.a = replacement
        let deadline = ContinuousClock.now + .seconds(2)
        while !views[0].string.utf16.elementsEqual(model.a.utf16) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(views[0].string.utf16.elementsEqual(model.a.utf16))
        try assertCodeVisible(host, editor: views[0], name: "ruler-hosted-replaced")
        window.makeFirstResponder(views[0])
        views[0].insertText("\nvar next = {ordinary: 789};", replacementRange: NSRange(location: (views[0].string as NSString).length, length: 0))
        try assertCodeVisible(host, editor: views[0], name: "ruler-hosted-inserted")
        #expect(views[0].string.utf16.elementsEqual((replacement + "\nvar next = {ordinary: 789};").utf16))
        #expect(views[1].string.utf16.elementsEqual(source.utf16))
    }
}
