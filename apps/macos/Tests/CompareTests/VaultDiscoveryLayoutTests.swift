import AppKit
import SwiftUI
import Testing
@testable import CompareUI

@Suite(.serialized) struct VaultDiscoveryLayoutTests {
    @MainActor private func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
    }
    @Test @MainActor func initialPanelsOnlyAskForLinkAndTokenAtThreeSizesInBothLanguages() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        for language in AppLanguage.allCases {
            for (width, height) in [(1280.0, 800.0), (1440, 900), (1720, 1000)] {
                let model = Workspace(clientFactory: { DirectCoreWorker() })
                model.tool = .vault; model.preferences.language = language
                let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
                let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.animationBehavior = .none
                host.sizingOptions = []; window.contentView = host; window.setContentSize(NSSize(width: width, height: height))
                defer { model.cancel(); window.close(); window.contentView = nil }
                try await Task.sleep(for: .milliseconds(80)); host.layoutSubtreeIfNeeded()
                let inputs = fields(host)
                #expect(inputs.count == 5, "Four source fields plus the existing result search; manual fields belong in collapsed advanced settings")
                for field in inputs {
                    #expect(field.visibleRect.height >= field.bounds.height - 1)
                    #expect(field.visibleRect.width >= field.bounds.width - 1)
                }
                #expect(!window.isVisible && !window.isKeyWindow)
            }
        }
    }
}

extension VaultDiscoveryLayoutTests {
    @MainActor private func settle(_ model: Workspace) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!model.busy && !model.error)
    }
    @Test @MainActor func discoveredAndManualStatesRenderAtThreeSizesWithoutPresenting() async throws {
        for language in AppLanguage.allCases {
            let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: DiscoveryFixture(), validate: $0) })
            model.tool = .vault; model.preferences.language = language
            var settings = VaultSettings(); settings.url = "https://uat.example.invalid/ui/"; settings.token = "synthetic-token"; settings.confirmedNonProduction = true
            model.vaultA = settings; model.vaultB = settings
            model.discoverVault(side: true); try await settle(model)
            model.discoverVault(side: false); try await settle(model)
            model.vaultA.mount = "FPMS-NT-V2"; model.vaultB.mount = "FPMS-NT-V2"
            model.discoverVault(side: true, contents: true); try await settle(model)
            model.discoverVault(side: false, contents: true); try await settle(model)
            model.vaultA.environment = "uat-swim"; model.vaultB.environment = "qat-other"
            for expanded in [false, true] {
                model.vaultAdvancedA = expanded; model.vaultAdvancedB = expanded
                for (width, height) in [(1280.0, 800.0), (1440, 900), (1720, 1000)] {
                    let host = NSHostingView(rootView: WorkspaceView(model: model).environmentObject(model.preferences).preferredColorScheme(.light))
                    let window = CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
                    host.sizingOptions = []; window.contentView = host; window.setContentSize(NSSize(width: width, height: height))
                    defer { window.close(); window.contentView = nil }
                    try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded()
                    #expect(abs(host.bounds.width - width) < 1 && abs(host.bounds.height - height) < 1)
                    #expect(!window.isVisible && !window.isKeyWindow)
                    #expect(model.vaultContentsA?.directories(for: "uat-swim") == ["auth", "auth/nested", "payment", "promotion"])
                    if let output = ProcessInfo.processInfo.environment["CC_DISCOVERY_IMAGES"] {
                        let folder = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("discovered-\(expanded ? "advanced" : "simple")-\(language.rawValue)-\(Int(width))x\(Int(height)).png"))
                    }
                }
            }
            model.cancel()
        }
    }
}
