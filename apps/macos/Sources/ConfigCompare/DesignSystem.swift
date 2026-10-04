import SwiftUI
import AppKit
import CompareShared

// Shared light design tokens. The application icon is supplied only to the
// macOS bundle; the working interface uses neutral system symbols.
enum AppPalette {
    static let background = Color(hex: 0xFFF9F7), sidebar = Color(hex: 0xFFF5F2)
    static let card = Color.white, code = Color(hex: 0xFCFCFF), line = Color(hex: 0xEEE7EF)
    static let pink = Color(hex: 0xF2A0B9), selection = Color(hex: 0xFDE8EF), rose = Color(hex: 0x6D2842)
    static let ink = Color(hex: 0x293044), secondary = Color(hex: 0x667085)
    static let mint = Color(hex: 0xEAF7EE), peach = Color(hex: 0xFFF1E6), blue = Color(hex: 0xEBF3FF)
    static let lavender = Color(hex: 0xF3EEFF), coral = Color(hex: 0xFFF0ED)
    static let codeNS = NSColor(srgbRed: 252/255, green: 252/255, blue: 1, alpha: 1)
    static let inkNS = NSColor(srgbRed: 41/255, green: 48/255, blue: 68/255, alpha: 1)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1)
    }
}

struct ProfileIconView: View {
    let icon: String
    var size: CGFloat = 64
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(AppPalette.rose)
            .frame(width: size, height: size)
            .background(AppPalette.selection, in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

struct AppButtonStyle: ButtonStyle {
    var primary = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, primary: primary, compact: compact, enabled: enabled, reduceMotion: reduceMotion)
    }
    private struct ButtonBody: View {
        let configuration: Configuration
        let primary: Bool, compact: Bool, enabled: Bool, reduceMotion: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: compact ? 12 : 13, weight: primary ? .semibold : .medium))
                .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 7 : 10)
                .foregroundStyle(primary ? AppPalette.rose : AppPalette.ink)
                .background(primary ? AppPalette.pink.opacity(configuration.isPressed ? 0.95 : (hovered ? 0.86 : 0.70)) : (hovered || configuration.isPressed ? AppPalette.selection : AppPalette.card), in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(primary ? AppPalette.pink : AppPalette.line, lineWidth: 1))
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

struct AppCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content.padding(padding).background(AppPalette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(AppPalette.line, lineWidth: 1))
    }
}
extension View { func appCard(padding: CGFloat = 16) -> some View { modifier(AppCard(padding: padding)) } }

struct SourceMark: View {
    let name: String
    var body: some View {
        Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(name == "B" ? Color(hex: 0x335E92) : AppPalette.rose)
            .frame(width: 28, height: 28).background(name == "B" ? AppPalette.blue : AppPalette.lavender, in: RoundedRectangle(cornerRadius: 8))
    }
}

enum ResultTone: String, CaseIterable {
    case SAME, VALUE_CHANGED, TYPE_CHANGED, ONLY_A, ONLY_B, NOT_COMPARABLE
    var background: Color { switch self { case .SAME: AppPalette.mint; case .VALUE_CHANGED: AppPalette.peach; case .TYPE_CHANGED: AppPalette.selection; case .ONLY_A: AppPalette.blue; case .ONLY_B: AppPalette.lavender; case .NOT_COMPARABLE: AppPalette.coral } }
    var ink: Color { switch self { case .SAME: Color(hex: 0x32674D); case .VALUE_CHANGED: Color(hex: 0x8C5323); case .TYPE_CHANGED: AppPalette.rose; case .ONLY_A: Color(hex: 0x335E92); case .ONLY_B: Color(hex: 0x655094); case .NOT_COMPARABLE: Color(hex: 0x9C493F) } }
    var symbol: String { switch self { case .SAME: "checkmark"; case .VALUE_CHANGED: "arrow.left.arrow.right"; case .TYPE_CHANGED: "textformat.abc"; case .ONLY_A: "plus"; case .ONLY_B: "plus"; case .NOT_COMPARABLE: "questionmark" } }
}

struct StatusPill: View {
    let status: String, title: String
    var body: some View {
        let tone = ResultTone(rawValue: status) ?? .NOT_COMPARABLE
        Label(title, systemImage: tone.symbol).font(.system(size: 11, weight: .medium)).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 6).foregroundStyle(tone.ink).background(tone.background, in: Capsule()).help(title)
    }
}

struct EmptyStateView: View {
    let title: String
    var subtitle = ""
    var symbol = "doc.text.magnifyingglass"
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 38, weight: .regular)).foregroundStyle(AppPalette.rose)
                .frame(width: 76, height: 76).background(AppPalette.selection, in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(AppPalette.ink)
            if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(AppPalette.secondary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }
}

// Conclusions depend on completeness and freshness, never on an empty filtered page.
enum ComparisonPresentation {
    static func emptyTitle(summary: Summary?, complete: Bool, stale: Bool, error: Bool, search: String, filter: String) -> String {
        guard let summary else { return "放入两份配置，开始查找差异。" }
        if stale { return "输入已改变，请重新比较。" }
        if error { return "操作未完成，请查看上方提示。" }
        if complete && summary.differences == 0 && summary.notComparable == 0 && search.isEmpty && filter == "differences" { return "检查完成，内容一致。" }
        return "这里暂时没有匹配项。"
    }
}

struct AppNavigationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { NavigationBody(configuration: configuration) }
    private struct NavigationBody: View {
        let configuration: Configuration
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label.background(hovered || configuration.isPressed ? AppPalette.selection.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45).onHover { hovered = $0 }
        }
    }
}

struct AppRowHover: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.overlay(RoundedRectangle(cornerRadius: 10).stroke(hovered ? AppPalette.pink.opacity(0.6) : .clear))
            .onHover { hovered = $0 }
    }
}
