import AppKit

@MainActor
enum AppAppearance {
    static func apply(_ theme: AppTheme) {
        // Native controls, title bars and code editors must also stay light.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }
}
