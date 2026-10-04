import AppKit
import Testing
@testable import CompareUI

@Suite(.serialized)
struct AppearanceTests {
    @Test @MainActor func legacyThemesKeepEveryNativeWindowLight() {
        let application = NSApplication.shared
        let original = application.appearance
        defer { application.appearance = original }
        application.appearance = nil
        let windows = (0..<2).map { _ in CheckedBackgroundTestWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false) }
        for theme in [AppTheme.dark, .light, .system, ] {
            AppAppearance.apply(theme)
            #expect(application.appearance?.name == .aqua)
            for window in windows { #expect(window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua) }
        }
        #expect(windows.allSatisfy { !$0.isVisible })
    }
}
