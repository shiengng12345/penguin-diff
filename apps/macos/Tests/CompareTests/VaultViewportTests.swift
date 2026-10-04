import AppKit
import SwiftUI
import Testing
import Darwin
import CompareShared
@testable import CompareUI

@MainActor private final class VaultReviewWindow: CheckedBackgroundTestWindow {
    private static var launched = false
    static func prepareApplication() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        if !launched { NSApplication.shared.finishLaunching(); launched = true }
    }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@Suite(.serialized)
struct VaultViewportTests {
    private let sizes = [NSSize(width: 1280, height: 800), NSSize(width: 1440, height: 900), NSSize(width: 1720, height: 1000)]
    @MainActor private func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
    }
    @MainActor private func buttons(_ view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
    }
    @MainActor private func scrolls(_ view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrolls($0) }
    }
    @MainActor private func assertReachable(_ field: NSTextField, host: NSView) async throws {
        field.scrollToVisible(field.bounds)
        try await pump(host)
        assertVisible(field)
    }
    @MainActor private func nativeEventTurn() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    @MainActor private func pump(_ host: NSView) async throws {
        for _ in 0..<8 { nativeEventTurn(); try await Task.sleep(for: .milliseconds(10)) }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    }
    @MainActor private func mount(_ model: Workspace, size: NSSize) -> (VaultReviewWindow, NSView) {
        VaultReviewWindow.prepareApplication()
        let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
        let window = VaultReviewWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.animationBehavior = .none
        host.sizingOptions = []; window.contentView = host; window.setContentSize(size); #expect(!window.isVisible && !window.isKeyWindow)
        return (window, host)
    }
    @MainActor private func assertVisible(_ view: NSView) {
        let visible = view.bounds.intersection(view.visibleRect)
        #expect(visible.height >= view.bounds.height - 1 && visible.width >= view.bounds.width - 1)
    }
    @MainActor private func capture(_ host: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["CC_VAULT_FORM_IMAGES"] else { return }
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: out.appendingPathComponent(name + ".png"))
    }
    @Test @MainActor func requiredVaultFieldsFitInitialViewportAtThreeSizes() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        var measurements: [[String: Any]] = []
        for language in AppLanguage.allCases {
            for size in sizes {
                let model = Workspace(clientFactory: { DirectCoreWorker() })
                model.tool = .vault; model.switchTool(); model.preferences.language = language
                model.vaultAdvancedA = true; model.vaultAdvancedB = true
                model.vaultA.environment = "synthetic-config-A"
                model.vaultB.environment = "synthetic-config-B"
                let (window, host) = mount(model, size: size)
                defer { model.cancel(); window.close(); window.contentView = nil }
                try await pump(host)
                let allFields = fields(host)
                let names = allFields.filter { $0.stringValue.hasPrefix("synthetic-config-") }
                try #require(names.count == 2, "Both real native configuration-name fields must exist")
                for field in names {
                    let frame = host.convert(field.bounds, from: field)
                    let visible = field.bounds.intersection(field.visibleRect)
                    measurements.append(["language": language.rawValue, "windowWidth": size.width, "windowHeight": size.height,
                                         "field": field.stringValue, "x": frame.minX, "y": frame.minY,
                                         "width": frame.width, "height": frame.height, "visibleHeight": visible.height,
                                         "visibleWidth": visible.width])
                    #expect(visible.height >= field.bounds.height - 1 && visible.width >= field.bounds.width - 1, "Configuration name must be visible without initial scrolling")
                }
                let confirmations = buttons(host)
                #expect(confirmations.isEmpty, "The manual non-production checkbox is removed")
                measurements.append(["language": language.rawValue, "windowWidth": size.width, "nativeCheckboxes": 0])
                for field in allFields { assertVisible(field) }
                let a = host.convert(names[0].bounds, from: names[0]), b = host.convert(names[1].bounds, from: names[1])
                #expect(abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1 && abs(a.minY - b.minY) < 1)
                try capture(host, name: "initial-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
            }
        }
        if let path = ProcessInfo.processInfo.environment["CC_VAULT_VIEWPORT_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }
    @Test func nativeFieldsRemainBoundWithLongValues() throws {
        // AppKit event tracking can stop the async main run loop used by
        // SwiftPM's Swift Testing helper before its completion record. Run the
        // real CompareUI module in an owned synchronous AppKit process instead.
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let debug = package.appendingPathComponent(".build/debug")
        let fixture = package.appendingPathComponent("Tests/NativeProbes/VaultBindingProbe.swift")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("config-compare-vault-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let list = try String(contentsOf: debug.appendingPathComponent("ConfigCompare.product/Objects.LinkFileList"), encoding: .utf8)
        let objects = list.split(separator: "\n").map(String.init).filter { !$0.contains("ConfigCompare.build/") }
        try #require(!objects.isEmpty)
        let executable = output.appendingPathComponent("VaultBindingProbe")
        let build = try runProcess(["rtk", "proxy", "xcrun", "swiftc", "-parse-as-library", "-enable-testing", "-I", debug.appendingPathComponent("Modules").path,
                                    fixture.path, package.appendingPathComponent("Tests/NativeProbes/BackgroundTestWindow.swift").path, "-o", executable.path] + objects, log: output.appendingPathComponent("build.log"))
        try #require(build.status == 0, "Native probe must build: \(build.log)")
        let result = try runProcess(["rtk", "proxy", executable.path], log: output.appendingPathComponent("probe.log"))
        try #require(result.status == 0, "Native interaction probe must complete successfully: \(result.log)")
        let json = try #require(result.log.split(separator: "\n").first { $0.hasPrefix("VAULT_NATIVE_BINDING_RESULT ") })
        let report = try JSONSerialization.jsonObject(with: Data(json.dropFirst("VAULT_NATIVE_BINDING_RESULT ".count).utf8)) as? [String: Any]
        #expect(report?["completed"] as? Bool == true && report?["workerRequests"] as? Int == 0)
        #expect(report?["cases"] as? Int == AppLanguage.allCases.count)
        #expect(report?["checks"] as? Int == 20)
        if let path = ProcessInfo.processInfo.environment["CC_VAULT_BINDING_OUTPUT"] {
            try Data(json.dropFirst("VAULT_NATIVE_BINDING_RESULT ".count).utf8).write(to: URL(fileURLWithPath: path))
        }
    }
    private func runProcess(_ arguments: [String], log: URL) throws -> (status: Int32, log: String) {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments; process.standardOutput = handle; process.standardError = handle
        try process.run()
        let deadline = Date(timeIntervalSinceNow: 30)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            let terminateDeadline = Date(timeIntervalSinceNow: 1)
            while process.isRunning && Date() < terminateDeadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        return (process.terminationStatus, try String(contentsOf: log, encoding: .utf8))
    }
    @Test @MainActor func minimumWindowVaultInputAndRealResultsStayReachable() async throws {
        var measurements: [[String: Any]] = []
        for language in AppLanguage.allCases {
            for size in [NSSize(width: 1050, height: 700)] + sizes {
                let model = Workspace(clientFactory: { DirectCoreWorker() })
                model.tool = .vault; model.switchTool(); model.preferences.language = language
                model.vaultAdvancedA = true; model.vaultAdvancedB = true
                model.vaultA.environment = "synthetic-config-A"; model.vaultB.environment = "synthetic-config-B"
                let (window, host) = mount(model, size: size)
                defer { model.cancel(); window.close(); window.contentView = nil }
                try await pump(host)
                try capture(host, name: "minimum-initial-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
                let names = fields(host).filter { $0.stringValue.hasPrefix("synthetic-config-") }
                try #require(names.count == 2)
                for name in names { assertVisible(name) }
                let worker = DirectCoreWorker()
                let session = UUID().uuidString
                let request = try JSONSerialization.data(withJSONObject: ["op":"compare", "kind":"json", "a":"{\"synthetic\":1}", "b":"{\"synthetic\":2}", "session":session])
                let response = try CoreResponse.decode(try await worker.send(String(decoding: request, as: UTF8.self)))
                let release = try JSONSerialization.data(withJSONObject: ["op":"release", "session":session])
                let released = try CoreResponse.decode(try await worker.send(String(decoding: release, as: UTF8.self)))
                try #require(released.ok)
                try #require(response.ok)
                // Rendering fixture: genuine core output, not a live Vault run.
                model.summary = response.summary; model.rows = response.rows ?? []; model.matched = response.summary?.differences ?? 0
                model.complete = response.complete ?? false; model.stale = false
                try await pump(host)
                try capture(host, name: "minimum-results-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
                #expect(model.summary?.valueChanged == 1 && model.rows.count == 1)
                let resultScrolls = scrolls(host).filter { view in
                    guard let document = view.documentView else { return false }
                    return fields(document).isEmpty
                }
                try #require(resultScrolls.count == 1, "One actual result scroll viewport must exist")
                for scroll in resultScrolls {
                    scroll.scrollToVisible(scroll.bounds); try await pump(host)
                    let visible = scroll.contentView.bounds.intersection(scroll.contentView.visibleRect)
                    measurements.append(["language": language.rawValue, "width": size.width, "height": size.height,
                                         "resultViewportWidth": visible.width, "resultViewportHeight": visible.height,
                                         "rowHeight": 62])
                    try capture(host, name: "minimum-results-reachable-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
                    #expect(visible.height >= 62, "One complete real result row must fit the viewport")
                }
                for field in fields(host) { try await assertReachable(field, host: host) }
                let form = try #require(scrolls(host).first { view in view.documentView.map { fields($0).count == 16 } ?? false })
                let formDocument = try #require(form.documentView)
                let confirmations = buttons(formDocument)
                #expect(confirmations.isEmpty, "The manual non-production controls are removed")
                #expect(model.vaultA.environment == "synthetic-config-A" && model.vaultB.environment == "synthetic-config-B")
                #expect(!model.vaultA.confirmedNonProduction && !model.vaultB.confirmedNonProduction)
                try capture(host, name: "minimum-results-scrolled-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
            }
        }
        if let path = ProcessInfo.processInfo.environment["CC_MINIMUM_VIEWPORT_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }
    @Test @MainActor func oneSidedNamespaceChooserAndPlansKeepBothFormsAligned() async throws {
        for language in AppLanguage.allCases {
            for size in sizes {
                let worker = ViewportWorker()
                let model = Workspace(clientFactory: { worker })
                model.tool = .vault; model.switchTool(); model.preferences.language = language
                model.vaultAdvancedA = true; model.vaultAdvancedB = true
                var settings = VaultSettings()
                settings.url = "https://uat.example.invalid"; settings.token = "synthetic-only-token"
                settings.mount = "synthetic-kv"; settings.environment = "synthetic-config-A"
                settings.confirmedNonProduction = true
                model.vaultA = settings; settings.environment = "synthetic-config-B"; model.vaultB = settings
                model.vaultNamespacesA = ["team-a/uat", "team-b/uat"]
                func plan(_ settings: VaultSettings) throws -> VaultPlan {
                    let target = try VaultTarget(settings)
                    let secrets = (0..<24).map { VaultSecret(namespace: "team-a/uat", namespaceKey: "team-a/uat", path: "synthetic-long-service-\($0)/" + settings.environment, directoryKey: "service-\($0)", kvVersion: 2) }
                    return VaultPlan(target: target, secrets: secrets, discoveredNamespaces: ["team-a/uat"], created: Date())
                }
                model.vaultPlanA = try plan(model.vaultA); model.vaultPlanB = try plan(model.vaultB)
                let (window, host) = mount(model, size: size)
                defer { model.cancel(); window.close(); window.contentView = nil }
                try await pump(host)
                let all = fields(host)
                let names = all.filter { $0.stringValue.hasPrefix("synthetic-config-") }
                try #require(names.count == 2)
                for field in all { assertVisible(field) }
                let a = host.convert(names[0].bounds, from: names[0]), b = host.convert(names[1].bounds, from: names[1])
                #expect(abs(a.width - b.width) < 1 && abs(a.minY - b.minY) < 1)
                #expect(worker.requests == 0)
                try capture(host, name: "plans-chooser-\(language.rawValue)-\(Int(size.width))x\(Int(size.height))")
            }
        }
    }
}

@MainActor private final class ViewportWorker: WorkerSending {
    private let core = DirectCoreWorker()
    private(set) var requests = 0
    func send(_ request: String) async throws -> String { requests += 1; return try await core.send(request) }
    func abort() { core.abort() }
}
