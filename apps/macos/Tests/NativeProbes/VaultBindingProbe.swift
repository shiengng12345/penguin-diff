// Owned synchronous AppKit probe: no global events, real Vault or saved credentials.
import AppKit
import SwiftUI
@testable import CompareUI

private enum Failure: Error { case failed(String) }
@MainActor private final class ProbeWorker: WorkerSending {
    private(set) var requests = 0
    func send(_ request: String) async throws -> String { requests += 1; throw Failure.failed("unexpected worker request") }
    func abort() {}
}
@main struct VaultBindingProbe {
    @MainActor private static var checks = 0
    @MainActor private static func check(_ condition: Bool, _ name: String) throws {
        checks += 1
        if !condition { throw Failure.failed(name) }
    }
    @MainActor private static func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
    }
    @MainActor private static func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    @MainActor private static func pump(_ host: NSView) {
        for _ in 0..<8 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor private static func click(_ button: NSButton, in window: NSWindow, host: NSView) throws {
        let frame = button.convert(button.bounds, to: nil)
        let point = NSPoint(x: frame.midX, y: frame.midY)
        guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)
        else { throw Failure.failed("create owned-window events") }
        // Queue mouse-up before mouse-down so a native tracking loop can consume
        // it. NSApplication.sendEvent supplies the real application event path.
        // Both events target only this probe's own window; never activate NSApp.
        NSApplication.shared.postEvent(up, atStart: true)
        NSApplication.shared.sendEvent(down)
        NSApplication.shared.sendEvent(up)
        pump(host)
    }
    @MainActor private static func run(_ language: AppLanguage) throws -> Int {
        let worker = ProbeWorker(), model = Workspace(clientFactory: { worker })
        model.tool = .vault; model.switchTool(); model.preferences.language = language
        model.vaultAdvancedA = true; model.vaultAdvancedB = true
        model.vaultA.environment = "synthetic-config-A"; model.vaultB.environment = "synthetic-config-B"
        model.vaultA.mount = "synthetic-mount-A"; model.vaultB.mount = "synthetic-mount-B"
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
        let window = BackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        host.sizingOptions = []; window.contentView = host; window.setContentSize(NSSize(width: 1280, height: 800)); window.prepareForNativeEventDispatch(); try check(window.alphaValue == 0 && !window.isKeyWindow && !window.isMainWindow && window.ignoresMouseEvents && BackgroundTestWindow.presentationAttempts == 0, "native event surface stays transparent and refuses focus")
        defer { model.cancel(); window.close(); window.contentView = nil }
        pump(host)
        let controls = buttons(host).sorted { host.convert($0.bounds, from: $0).minX < host.convert($1.bounds, from: $1).minX }
        try check(controls.isEmpty, "manual confirmation checkbox removed")
        guard let field = fields(host).first(where: { $0.stringValue == "synthetic-config-A" }) else { throw Failure.failed("name field") }
        try check(window.makeFirstResponder(field), "focus name"); field.selectText(nil)
        guard let editor = field.currentEditor() as? NSTextView else { throw Failure.failed("name field editor") }
        let replacement = String(repeating: "synthetic-long-editable-name-", count: 9) + "中文-e\u{301}"
        editor.insertText(replacement, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        window.makeFirstResponder(nil); pump(host)
        try check(model.vaultA.environment.utf16.elementsEqual(replacement.utf16), "long name exact UTF16 binding")
        try check(model.vaultB.environment == "synthetic-config-B", "B name isolation")
        guard let initialA = fields(host).first(where: { $0.stringValue.utf16.elementsEqual(replacement.utf16) }),
              let initialB = fields(host).first(where: { $0.stringValue == "synthetic-config-B" }) else { throw Failure.failed("initial name fields") }
        let initialAFrame = host.convert(initialA.bounds, from: initialA), initialBFrame = host.convert(initialB.bounds, from: initialB)
        try check(abs(initialAFrame.width - initialBFrame.width) < 1 && abs(initialAFrame.minY - initialBFrame.minY) < 1, "long name preserves A/B alignment")
        guard let mount = fields(host).first(where: { $0.stringValue == "synthetic-mount-B" }) else { throw Failure.failed("mount field") }
        try check(window.makeFirstResponder(mount), "focus mount"); mount.selectText(nil)
        guard let mountEditor = mount.currentEditor() as? NSTextView else { throw Failure.failed("mount field editor") }
        mountEditor.insertText("synthetic-new-mount-B", replacementRange: NSRange(location: 0, length: (mountEditor.string as NSString).length))
        window.makeFirstResponder(nil); pump(host)
        try check(model.vaultB.mount == "synthetic-new-mount-B" && model.vaultA.mount == "synthetic-mount-A" && model.vaultB.environment.isEmpty, "mount binding clears stale B name and preserves A isolation")
        let all = fields(host)
        try check(all.allSatisfy { let rect = $0.bounds.intersection($0.visibleRect); return rect.width >= $0.bounds.width - 1 && rect.height >= $0.bounds.height - 1 }, "all fields remain visible")
        try check(worker.requests == 0, "editing must not request worker/network work")
        return worker.requests
    }
    @MainActor static func main() {
        do {
            NSApplication.shared.setActivationPolicy(.prohibited); NSApplication.shared.finishLaunching()
            var requests = 0
            for language in AppLanguage.allCases { requests += try run(language) }
            guard BackgroundTestWindow.presentationAttempts == 0 else { throw Failure.failed("unexpected window presentation") }
            let data = try JSONSerialization.data(withJSONObject: ["completed": true, "workerRequests": requests, "cases": AppLanguage.allCases.count, "checks": checks], options: [.sortedKeys])
            print("VAULT_NATIVE_BINDING_RESULT " + String(decoding: data, as: UTF8.self))
        } catch { print("VAULT_NATIVE_BINDING_FAILED \(error)"); exit(1) }
    }
}
