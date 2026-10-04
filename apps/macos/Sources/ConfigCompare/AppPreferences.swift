import Foundation
import SwiftUI
import Darwin

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var nativeName: String { self == .english ? "English" : "简体中文" }
    static func preferred(from languages: [String]) -> Self {
        for language in languages {
            let base = language.lowercased().split(separator: "-").first
            if base == "zh" { return .simplifiedChinese }
            if base == "en" { return .english }
        }
        return .english
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    // Older values remain decodable so reopening the app cannot break saved
    // preferences. The product exposes one calm, light presentation.
    static var allCases: [Self] { [.light] }
    var id: String { rawValue }
    var title: String { switch self { case .system: "跟随系统"; case .light: "奶油白"; case .dark: "深色" } }
    var subtitle: String {
        switch self {
        case .system, .dark: "浅色工作区"
        case .light: "奶油白与柔粉，安静清晰。"
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable, Sendable {
    case blue, green, orange, purple, pink, gray
    var id: String { rawValue }
    var title: String { switch self { case .blue: "蓝色"; case .green: "绿色"; case .orange: "橙色"; case .purple: "紫色"; case .pink: "粉色"; case .gray: "灰色" } }
    var color: Color { switch self { case .blue: Color(hex: 0x587FAF); case .green: Color(hex: 0x498060); case .orange: Color(hex: 0xA86B38); case .purple: Color(hex: 0x8165A7); case .pink: AppPalette.rose; case .gray: AppPalette.secondary } }
}

enum AppAvatar: String, CaseIterable, Identifiable, Sendable {
    case person, compare, terminal, sparkles
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .person: "person.crop.circle.fill"
        case .compare: "arrow.left.arrow.right.circle.fill"
        case .terminal: "terminal.fill"
        case .sparkles: "sparkles"
        }
    }
    var title: String {
        switch self {
        case .person: "个人图标"
        case .compare: "比较工具"
        case .terminal: "终端工具"
        case .sparkles: "状态标记"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults?
    private let defaultLanguage: AppLanguage
    @Published var language: AppLanguage { didSet { defaults?.set(language.rawValue, forKey: "appearance.language") } }
    @Published var theme: AppTheme {
        didSet {
            defaults?.set(theme.rawValue, forKey: "appearance.theme")
        }
    }
    @Published var accent: AppAccent { didSet { defaults?.set(accent.rawValue, forKey: "appearance.accent") } }
    @Published var avatar: AppAvatar { didSet { defaults?.set(avatar.rawValue, forKey: "appearance.avatar") } }
    @Published var username: String {
        didSet {
            let normalized = Self.normalizedName(username)
            if username != normalized { username = normalized }
            defaults?.set(username, forKey: "appearance.username")
        }
    }
    var displayName: String { username.isEmpty ? text("SRE 用户") : username }
    init(defaults: UserDefaults?, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        defaultLanguage = AppLanguage.preferred(from: preferredLanguages)
        language = defaults?.string(forKey: "appearance.language").flatMap(AppLanguage.init(rawValue:)) ?? defaultLanguage
        theme = .light
        accent = defaults?.string(forKey: "appearance.accent").flatMap(AppAccent.init(rawValue:)) ?? .pink
        avatar = defaults?.string(forKey: "appearance.avatar").flatMap(AppAvatar.init(rawValue:)) ?? .person
        let savedName = defaults?.string(forKey: "appearance.username") ?? ""
        let migratePlaceholder = savedName == "John Doe" && defaults?.bool(forKey: "appearance.placeholderMigrated") != true
        username = Self.normalizedName(migratePlaceholder ? "" : savedName)
        if migratePlaceholder { defaults?.set("", forKey: "appearance.username") }
        // Record the first check even when no legacy placeholder was present.
        // A later explicit local name must survive reopening and reset.
        if defaults?.bool(forKey: "appearance.placeholderMigrated") != true {
            defaults?.set(true, forKey: "appearance.placeholderMigrated")
        }
    }
    private static func normalizedName(_ input: String) -> String {
        boundedNameDraft(input.trimmingCharacters(in: .whitespacesAndNewlines)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func boundedNameDraft(_ input: String) -> String {
        let scalars = input.unicodeScalars.filter { $0.properties.generalCategory != .control }
        return String(String(String.UnicodeScalarView(scalars)).prefix(40))
    }
    func text(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments, language: language) }
    func reset() { language = defaultLanguage; theme = .light; accent = .pink; avatar = .person; username = "" }
}

indirect enum LocalizedMessage: Equatable, Sendable {
    case text(String, [String] = [])
    case literal(String)
    case joined([LocalizedMessage])
    func render(in language: AppLanguage) -> String {
        switch self {
        case .text(let key, let arguments): L10n.text(key, arguments: arguments, language: language)
        case .literal(let value): value
        case .joined(let parts): parts.map { $0.render(in: language) }.joined()
        }
    }
}

enum L10n {
    static func localError(_ failure: NSError) -> LocalizedMessage {
        if let controlled = failure.userInfo[NSLocalizedDescriptionKey] as? String, english[controlled] != nil {
            return .text(controlled)
        }
        var key: String?
        if failure.domain == NSPOSIXErrorDomain {
            switch Int32(failure.code) {
            case ENOENT: key = "本地文件不存在。"
            case EACCES, EPERM: key = "没有读取或写入这个文件的权限。"
            case EINVAL: key = "请选择有效的普通本地文件。"
            case ENOSPC: key = "磁盘空间不足，操作未完成。"
            default: break
            }
        } else if failure.domain == NSCocoaErrorDomain {
            switch failure.code {
            case CocoaError.fileReadTooLarge.rawValue: key = "文件超过 20 MiB 限制。"
            case CocoaError.fileReadInapplicableStringEncoding.rawValue: key = "文件不是有效的 UTF-8。"
            case CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue: key = "没有读取或写入这个文件的权限。"
            case CocoaError.fileWriteFileExists.rawValue: key = "目标文件已存在；请另选新文件名。"
            case CocoaError.fileReadNoSuchFile.rawValue: key = "本地文件不存在。"
            case CocoaError.fileReadUnknown.rawValue: key = "文件无法可靠读取；它可能已改变或不是普通文件。"
            default: break
            }
        }
        return key.map { .text($0) } ?? .text("本机操作未完成（{0}）。", [String(failure.code)])
    }
    static func typeName(_ type: String, language: AppLanguage) -> String {
        if language == .english { return type }
        return ["Number":"数字", "String":"字符串", "Boolean":"布尔值", "Object":"对象", "Array":"数组", "Null":"null", "Undefined":"undefined", "BigInt":"BigInt", "Missing":"缺失", "Unknown":"未知", "Hole":"空槽"][type] ?? type
    }
    static func valuePreview(type: String, display: String, language: AppLanguage) -> String {
        guard language == .english else { return display }
        switch type {
        case "Missing": return "<Missing>"
        case "Hole": return "<Hole>"
        case "Unknown":
            if display.hasPrefix("<无法比较：") { return "<Not comparable: " + display.dropFirst(6) }
        case "Object":
            if display.hasPrefix("{ "), display.hasSuffix(" 个键 }"), let count = Int(display.dropFirst(2).dropLast(5)), count >= 0 { return "{ \(count) keys }" }
        case "Array":
            if display.hasPrefix("[ "), display.hasSuffix(" 项 ]"), let count = Int(display.dropFirst(2).dropLast(4)), count >= 0 { return "[ \(count) items ]" }
        default: break
        }
        return display
    }
    // Only explicit UI/controlled diagnostic keys are translated. Arguments stay literal.
    static func text(_ key: String, arguments: [String] = [], language: AppLanguage) -> String {
        let template = language == .english ? (english[key] ?? key) : key
        var output = "", cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]), arguments.indices.contains(index) {
                output += arguments[index]; cursor = template.index(after: end)
            } else { output.append(template[cursor]); cursor = template.index(after: cursor) }
        }
        return output
    }
    static let english: [String: String] = [
        "全部目录": "All directories", "当前 namespace：{0}": "Current namespace: {0}",
        "读取选项": "Load options",
        "namespace 范围已改变；请重新读取选项。": "Namespace scope changed. Reload options.",
        "连接输入已改变；请重新读取选项。": "Connection input changed. Reload options.",
        "网页链接的 namespace 与当前范围不同；请在高级设置拆解链接并重新读取。": "The browser link namespace differs from the current scope. Parse the link in Advanced settings and reload.",
        "网页链接包含重复的 namespace 参数。": "The browser link contains duplicate namespace parameters.",
        "网页链接的 namespace 参数无效。": "The browser link namespace parameter is invalid.",
        "读取配置名称": "Load configuration names",
        "正在读取选项；尚未读取配置值…": "Loading options; configuration values have not been read…",
        "先选 KV mount，再读取配置名称。": "Select a KV mount, then load configuration names.",
        "无法列举 namespace；可使用当前范围或在高级设置中指定。": "Namespace listing is unavailable; use the current scope or specify one in Advanced settings.",
        "没有可见的 KV mount；可在高级设置中手动输入。": "No visible KV mounts; enter one manually in Advanced settings.",
        "没有可选配置；可在高级设置中手动输入。": "No configuration options; enter a name manually in Advanced settings.",
        "配置选项已读取；选择名称和目录范围后预览。": "Configuration options loaded. Select a name and directory scope, then preview.",
        "连接选项已读取；请选择 KV mount，再读取配置名称。": "Connection options loaded. Select a KV mount, then load configuration names.",
        "高级设置 · 手动输入与通配符": "Advanced settings · Manual input and wildcards",
        "目录范围": "Directory scope",
        "全部目录（含子目录）": "All directories (including subdirectories)",
        "当前目录": "Current directory",
        "请选择…": "Select…",
        "已排除带生产标识的选项；没有读取这些配置。": "Options with production labels were excluded; their configurations were not read.",
        "无法列举选项，请使用高级设置手动输入。": "Options cannot be listed. Enter them manually in Advanced settings.",
        "未取得可靠的 KV mount 列表，请使用高级设置手动输入。": "A reliable KV mount list is unavailable. Enter a mount manually in Advanced settings.",
        "mount 列表格式无效。": "The mount list format is invalid.",
        "mount 列表路径格式无效。": "The mount list path format is invalid.",
        "两侧按 JSON 键和类型比较。": "Compare JSON keys and types on both sides.",
        "填写两侧 Vault 来源，并预览非生产范围。": "Fill in both Vault sources and preview the non-production scope.",
        "确认匹配目录后，只读获取配置并比较。": "Confirm the matching paths, then read and compare configurations.",
        "奶油白": "Cream white", "浅色工作区": "Light workspace",
        "奶油白与柔粉，安静清晰。": "Cream white and soft pink, calm and clear.",
        "奶油白与柔粉，所有页面保持浅色。": "Cream white and soft pink, with a light appearance throughout.",
        "本机个性化": "Personalize this Mac", "未设置显示名称": "No display name set",
        "开始比较": "Compare configurations", "粘贴": "Paste", "详情": "Details", "关闭详情": "Close details",
        "输入配置": "Configuration input", "两侧按变量名和类型比较，安全解析，不运行配置代码。": "Compare variables and types using static parsing, without running configuration code.",
        "放入两份配置，开始查找差异。": "Add two configurations to find differences.",
        "输入已改变，请重新比较。": "Inputs changed. Compare again.",
        "操作未完成，请查看上方提示。": "The operation could not finish. See the message above.",
        "检查完成，内容一致。": "Check complete. The configurations match.",
        "这里暂时没有匹配项。": "No matching results here yet.",
        "调整搜索或筛选条件。": "Adjust the search or status filter.",
        "先放入 A 侧配置。": "Add configuration A first.", "再放入 B 侧配置，即可开始比较。": "Add configuration B to start comparing.",
        "两份配置已就绪。": "Both configurations are ready.", "正在检查配置…": "Checking configurations…",
        "格式化后，结果会出现在这里。": "Your formatted YAML will appear here.",
        "总计": "Total", "结果": "Results", "清除搜索": "Clear search", "复制": "Copy",
        "Vault 只读比较": "Read-only Vault comparison", "需要匹配的非生产范围": "Non-production scope to match",

        "上一轮结果（已过期）": "Previous results (out of date)",
        "Vault 读取来源 · {0} 条": "Vault read sources · {0}",
        "namespace：{0} · secret：{1}": "Namespace: {0} · Secret: {1}",
        "KV v{0} · secret 版本：{1}": "KV v{0} · Secret version: {1}",
        "创建时间：{0}": "Created: {0}",
        "删除时间：{0}": "Deleted: {0}",
        "删除／计划删除时间：{0}": "Deletion / scheduled deletion: {0}",
        "销毁：{0}": "Destroyed: {0}",
        "本机读取：{0} → {1}": "Local read: {0} → {1}",
        "未知": "Unknown",
        "是": "Yes",
        "否": "No",
        "未删除": "Not deleted",
        "各条读取不是原子快照；版本不同不会计为业务配置差异。": "Individual reads are not an atomic snapshot; different versions do not count as business configuration differences.",
        "此处显示前 200 条来源；完整记录可在 JSON 报告查看。": "First 200 read sources shown here; the JSON report contains all records.",
        "Vault 版本来源格式无效；没有输出可比较结果。": "Invalid Vault version metadata; no comparable result was returned.",
        "读取版本已删除或销毁；整批停止，不生成缺失或相同结论。": "The read version is deleted or destroyed; the entire batch stopped without missing or identical conclusions.",
        "响应没有可比较配置。": "The response has no comparable configuration.",
        "Vault 读取必须提供明确的 HTTP 状态。": "Vault reads require an explicit HTTP status.",
        "源码警告 · {0} 项": "Source warnings · {0}",
        "源码警告 · {0} 项（已过期）": "Source warnings · {0} (out of date)",
        "源码警告超过 100000 项或 20 MiB，请缩小输入。": "Source warnings exceed 100000 entries or 20 MiB; reduce the input.",
        "源码警告分页参数无效。": "Invalid source warning pagination parameters.",
        "{0} · 第 {1} 行，UTF-8 字节列 {2}；上次定义在第 {3} 行，列 {4}": "{0} · Line {1}, UTF-8 byte column {2}; previous definition at line {3}, column {4}",
        "对象字面量包含重复属性，按源码顺序采用最后一次定义": "Duplicate property in an object literal; the last definition in source order is used",
        "此处显示前 200 项；完整警告可在 JSON 报告查看。": "Showing the first 200 warnings; the JSON report contains all warnings.",
        "设置": "Settings", "通用": "General", "个人资料": "Profile", "外观": "Appearance",
        "界面语言": "Interface language", "立即生效，重启后保留。": "Applies immediately and is remembered after restart.",
        "显示名称": "Display name", "仅在本机显示，无需账号。最多 40 个字符。": "Shown locally; no account required. Up to 40 characters.",
        "头像": "Avatar", "选择内置图标": "Choose a built-in icon", "主题": "Theme", "强调色": "Accent color",
        "跟随系统": "System", "浅色": "Light", "深色": "Dark", "蓝色": "Blue", "绿色": "Green", "橙色": "Orange", "紫色": "Purple", "粉色": "Pink", "灰色": "Gray",
        "个人图标": "Profile icon", "比较工具": "Compare tool", "终端工具": "Terminal tool", "状态标记": "Status marker",
        "SRE 用户": "SRE user", "返回工具": "Back to tools", "恢复默认设置": "Restore defaults",
        "只重置语言、显示名称、头像和外观。": "Resets only language, display name, avatar and appearance.",
        "显示偏好仅保存在本机。": "Presentation preferences are stored on this Mac only.",
        "打开 A 文件…": "Open file A…", "运行": "Run", "交换 A/B": "Swap A/B", "停止当前操作": "Stop current operation", "清空输入和结果": "Clear inputs and results",
        "相同": "Same", "值变化": "Value changed", "类型变化": "Type changed", "仅 A": "Only A", "仅 B": "Only B", "无法比较": "Not comparable",
        "env.js 比较": "env.js comparison", "Vault 比较": "Vault comparison", "YAML 格式化": "YAML formatter",
        "SRE 配置小工具": "SRE configuration helper", "Vault 仅手动读取非生产": "Manual, non-production Vault reads only", "复制 MCP 配置": "Copy MCP configuration",
        "只调整排版，保留注释、引号和引用。": "Format while preserving comments, quotes and references.",
        "按键和类型比较；对象键顺序不会产生差异。": "Compare keys and types; object key order does not create differences.",
        "交换两侧输入和设置；需要重新比较，Vault 需要重新读取选项和预览。": "Swap inputs and settings. Compare again; Vault requires loading options and previewing again.",
        "停止": "Stop", "格式化": "Format", "读取并比较": "Read and compare", "比较": "Compare",
        "Vault 来源": "Vault source", "URL + Token 直连": "Connect with URL + Token", "已有 JSON（可选）": "Existing JSON (optional)",
        "两侧配置名称可不同；按相对 namespace / 目录配对。* 一层，** 任意层，. 当前范围。": "Names may differ between sides; pair relative namespaces / directories. * one level, ** any level, . current scope.",
        "预览匹配范围": "Preview matching scope",
        "MCP：Token 保存在本机钥匙串；已保存授权不随界面编辑或 A/B 交换改变。使用新范围需重新预览授权。": "MCP: Tokens stay in the local Keychain. Editing or swapping A/B does not change saved authorization. Preview and authorize a new scope explicitly.",
        "授权 MCP 使用当前范围": "Authorize this scope for MCP", "撤销 MCP 授权": "Revoke MCP authorization",
        "读取中…": "Reading…", "打开文件…": "Open file…", "A 输入编辑器": "Input editor A", "B 输入编辑器": "Input editor B",
        "比较根": "Comparison root", "所有顶层变量（不含导出根）": "All top-level variables (excluding export roots)", "检查根候选": "Inspect root candidates",
        "比较范围": "Comparison scope", "全部变量": "All variables", "刷新变量列表": "Refresh variable list", "按名称比较文件中的所有顶层变量；也可选择单一变量。": "Compare all top-level variables by name, or select a single variable.",
        "输入格式": "Input format", "纯配置对象": "Plain configuration object", "路径映射：路径 → 配置对象": "Path map: path → configuration object",
        "KV v1 响应：data": "KV v1 response: data", "KV v2 响应：data.data": "KV v2 response: data.data",
        "缩进": "Indentation", "2 空格": "2 spaces", "4 空格": "4 spaces", "格式化结果": "Formatted output", "复制结果": "Copy output", "导出 YAML…": "Export YAML…", "只读 YAML 格式化结果": "Read-only formatted YAML output",
        "总计 {0}": "Total {0}", "相同 {0}": "Same {0}", "值变化 {0}": "Value changed {0}", "类型变化 {0}": "Type changed {0}", "仅 A {0}": "Only A {0}", "仅 B {0}": "Only B {0}", "无法比较 {0}": "Not comparable {0}",
        "结果不完整 · {0} 个诊断范围": "Incomplete result · {0} diagnostic scopes", "状态": "Status", "差异与无法比较": "Differences and not comparable", "全部": "All", "搜索路径或值（区分大小写）": "Search paths or values (case-sensitive)", "比较结果表": "Comparison results", "整张结果表在独立弹出窗口中显示；筛选、搜索、分页和详情与主页面同步。": "The full results table opens in a separate window; filters, search, pagination and details stay in sync.", "弹出结果表": "Pop out results table", "在更大的窗口查看完整结果表": "View the full results table in a larger window", "关闭": "Close",
        "范围": "Scope", "键和值": "Keys and values", "路径": "Path", "变量": "Variable", "变量 · 当前页树": "Variable · Current-page tree", "复制变量": "Copy variable", "搜索变量或值（区分大小写）": "Search variables or values (case-sensitive)", "值": "Values", "显示": "View", "平面": "Flat", "当前页树": "Current-page tree",
        "上一页": "Previous", "{0} 项匹配 · 第 {1} 页（每页 200 项）": "{0} matches · Page {1} (200 per page)", "下一页": "Next",
        "仅当前筛选": "Current filter only", "包含配置值": "Include configuration values", "导出…": "Export…", "类型化 JSON 报告": "Typed JSON report", "JSON 数组（结果行）": "JSON array (result rows)", "HTML 可读报告": "Readable HTML report", "CSV 报告": "CSV report",
        "复制路径": "Copy path", "选择一行查看完整值与类型": "Select a row to inspect its full value and type",
        "第 {0} 行 · UTF-8 字节列 {1}": "Line {0} · UTF-8 byte column {1}", "复制 {0} 完整值": "Copy full value {0}",
        "路径 · 当前页树": "Path · Current-page tree", "分组 · 本页 {0} 项": "Group · {0} results on this page", "结构 · 只读内容，不增加差异计数": "Structure · Read-only, does not increase difference counts", "对象范围不完整": "Incomplete object scope",
        "来源 {0}": "Source {0}", "Vault URL 或网页链接": "Vault URL or web link", "拆解链接": "Parse link", "Token（仅本次会话）": "Token (this session only)",
        "Namespace 根（空 = root）": "Namespace root (empty = root)", "Namespace 根": "Namespace root", "选择": "Choose", "Namespace 匹配": "Namespace pattern", ". 或 team-* / **": ". or team-* / **",
        "例如 FPMS-NT-V2，可编辑": "e.g. FPMS-NT-V2, editable", "目录根": "Directory root", "空 = mount 根；例如 auth": "Empty = mount root; e.g. auth", "目录匹配": "Directory pattern", "配置名称": "Configuration name", "例如 uat-swim；两侧独立编辑": "e.g. uat-swim; each side is editable",
        "已匹配 {0} 个配置 · 展开核对": "{0} configurations matched · Expand to verify",
        "A · 粘贴或打开文件": "A · Paste or open a file", "B · 粘贴或打开文件": "B · Paste or open a file",
        "完全离线 · 手动输入 · 原文件不覆盖": "Fully offline · Manual input · Original files are preserved",
        "输入已改变，结果已过期；请重新运行。": "Input changed; results are stale. Run again.",
        "已交换 A/B 输入和设置；旧结果已过期，请重新比较。": "Inputs and settings swapped. Previous results are stale; compare again.",
        "手动只读连接非生产 Vault · 先预览范围再读取": "Manual read-only connection to non-production Vault · Preview the scope before reading",
        "文件导入已停止；输入和已有结果保留。": "File import stopped; inputs and existing results are preserved.", "操作已停止，输入仍保留。": "Operation stopped; inputs are preserved.",
        "（第 {0} 行，UTF-8 字节列 {1}）": " (line {0}, UTF-8 byte column {1})", "本地计算已停止。": "Local computation stopped.", "正在本机处理…": "Processing locally…",
        "格式化完成：已核对标量、注释、引用和文档顺序。": "Formatting complete: scalars, comments, references and document order verified.", "比较完成。": "Comparison complete.",
        "结果不完整：存在无法静态确认的内容，不能判定整体相同。": "Incomplete result: some content cannot be resolved statically. Overall equality cannot be confirmed.",
        "链接已拆解。要匹配各目录的同名配置，将目录匹配改为 **；名称和 mount 均可编辑。": "Link parsed. Use ** to match the same name in all directories; names and mounts remain editable.",
        "请先预览两侧非生产范围，才能授权 MCP。": "Preview both non-production scopes before authorizing MCP.",
        "已授权 MCP 使用当前两侧范围；Token 只保存到本机钥匙串。更改界面字段不会自动修改这份授权，可重新授权或撤销。": "MCP authorized for both current scopes; Tokens are saved only in the local Keychain. Editing fields does not alter this authorization. Authorize again or revoke it explicitly.",
        "已撤销 Vault MCP 授权并删除钥匙串中的这份凭证。": "Vault MCP authorization revoked and its credentials removed from Keychain.",
        "正在列举确认范围；尚未读取 secret 值…": "Listing the confirmed scope; secret values have not been read…",
        "预览完成：A {0} 个、B {1} 个配置。核对范围后点击读取并比较。": "Preview complete: {0} configurations in A and {1} in B. Verify the scope, then read and compare.",
        "请先预览并核对两侧匹配范围。": "Preview and verify both matching scopes first.", "正在只读取得两侧配置；Token 不进入比较核心…": "Reading both sides without writes; Tokens do not enter the comparison core…",
        "已比较 A {0} / B {1} 个配置，按相对 namespace 和目录配对；各条读取不是原子快照。": "Compared {0} configurations in A / {1} in B, paired by relative namespaces and directories. Individual reads are not an atomic snapshot.",
        " 本次整批未完成，不生成缺失或相同结论。": " This batch did not complete; no missing or equal conclusion is produced.",
        "正在检查静态根候选…": "Inspecting static root candidates…", "变量列表已更新。": "Variable list updated.",
        "所选变量不存在，请重新选择比较范围。": "The selected variable is missing. Choose a comparison scope again.", "（未找到）": "(not found)",
        "读取本地文件；内容不会发送到任何服务。": "Read a local file; its contents are not sent to any service.", "仅接受本地文件。": "Only local files are accepted.", "文件已载入；比较使用当前编辑内容。": "File loaded; comparison uses the current edited content.", "已复制；剪贴板会保留内容，直至被替换。": "Copied; clipboard contents remain until replaced.",
        "仅保存到新文件。原输入和已有文件不会覆盖。报告可能包含敏感配置值。": "Save to a new file only. Inputs and existing files are preserved. Reports may contain sensitive configuration values.", "已导出到新文件：{0}": "Exported to a new file: {0}",
        "本地计算服务已中断，请重新运行。": "The local computation service was interrupted. Run again.", "本地计算超过 30 秒，已停止；请缩小输入后重试。": "Local computation exceeded 30 seconds and stopped. Reduce the input and retry.", "本地请求无效。": "Invalid local request.",
        "本机操作未完成（{0}）。": "Local operation did not complete (error {0}).",
        "本地文件不存在。": "The local file does not exist.", "文件不是有效的 UTF-8。": "The file is not valid UTF-8.",
        "没有读取或写入这个文件的权限。": "Permission to read or write this file was denied.", "请选择有效的普通本地文件。": "Choose a valid regular local file.",
        "磁盘空间不足，操作未完成。": "The disk is full; the operation did not complete.", "文件超过 20 MiB 限制。": "The file exceeds the 20 MiB limit.",
        "目标文件已存在；请另选新文件名。": "The destination already exists; choose a new filename.",
        "文件无法可靠读取；它可能已改变或不是普通文件。": "The file could not be read reliably; it may have changed or is not a regular file.",
        "根级静态执行范围无法完全确认": "The root-level static execution scope cannot be fully confirmed",
        "路径必须是相对路径，不能包含转义、控制字符或首尾斜杠。": "Use a relative path without escapes, control characters, or leading/trailing slashes.",
        "路径包含空段、越级路径或不允许的通配符。": "The path contains empty segments, traversal, or disallowed wildcards.",
        "** 必须独占一个路径段；* 匹配一层，** 匹配任意层。": "** must be a complete path segment; * matches one level and ** matches any depth.",
        "请输入 Vault 服务地址或网页链接，不带账号、密码或 fragment。": "Enter a Vault service URL or web link without a username, password, or fragment.",
        "地址格式错误。": "Invalid URL format.", "服务地址不能包含 query。": "The service URL must not contain a query.",
        "请使用服务根地址，或 /ui/vault/secrets/<mount>/kv/... 网页链接。": "Use the service root URL or a /ui/vault/secrets/<mount>/kv/... web link.",
        "网页路径编码错误。": "Invalid web path encoding.",
        "生产标识被阻止；仅允许非生产来源。": "Production identifiers are blocked; only non-production sources are allowed.",
        "请先点击拆解网页链接，并核对 mount 和范围。": "Parse the web link first and verify the mount and scope.",
        "Token 必须非空且不包含空白或控制字符。": "Token must be nonempty and contain no whitespace or control characters.",
        "配置名称必须是一个可编辑的末级名称，例如 uat-swim；目录另填。": "Use a single editable leaf name, e.g. uat-swim; enter its directory separately.",
        "匹配清单与 App 授权时不同；不会扩大读取范围。请回到 App 重新预览并授权。": "The inventory differs from the App authorization. Reads will not expand. Preview and authorize again in the App.",
        "预览过期或设置已改变，请重新预览再授权 MCP。": "Preview expired or settings changed. Preview again before authorizing MCP.",
        "未取得本机钥匙串授权。请在 App 中预览两侧非生产范围，再点击授权 MCP；凭证不会由 MCP 参数接收。": "No local Keychain authorization. Preview both non-production scopes in the App and authorize MCP; credentials are not accepted through MCP parameters.",
        "响应超过 20 MiB。": "Response exceeds 20 MiB.", "响应不是 HTTP。": "Response is not HTTP.",
        "网络、TLS 或超时错误；未绕过证书验证。": "Network, TLS, or timeout error; certificate validation was not bypassed.",
        "本次读取超过 500 个请求，范围未完成。": "Read exceeded 500 requests; the scope is incomplete.",
        "匹配范围出现生产 namespace，已停止。": "A production namespace appeared in the matching scope; stopped.",
        "本次来源响应总量超过 20 MiB。": "Total source responses exceed 20 MiB.",
        "Vault 重定向已阻止；请填写最终的非生产服务地址。": "Vault redirect blocked. Enter the final non-production service URL.",
        "列举未完成；403/404 不代表配置不存在。": "Listing did not complete; 403/404 does not prove absence.",
        "读取未完成；403/404 不代表配置不存在。": "Reading did not complete; 403/404 does not prove absence.",
        "响应不是完整 UTF-8 JSON。": "Response is not complete UTF-8 JSON.", "响应不是 JSON 对象。": "Response is not a JSON object.",
        "范围无法确认；未将 404 当作缺失。": "Scope could not be confirmed; 404 was not treated as absence.",
        "列举结果没有可靠的 keys，或包含重复路径。": "Listing has unreliable keys or duplicate paths.",
        "服务器列举结果不是相对单层路径。": "Server listing is not a relative single-level path.",
        "namespace 超过 100 个或 8 层，范围未完成。": "Namespace count exceeds 100 or depth exceeds 8; scope is incomplete.",
        "列举范围出现生产 namespace；请收窄非生产 namespace 根。": "Listing contains a production namespace. Narrow the non-production namespace root.",
        "所选 mount 未被服务器确认为 KV；不会尝试读取其他 engine。": "The server did not confirm the selected mount as KV; other engines will not be read.",
        "KV 版本未确认。": "KV version is unconfirmed.", "namespace 模式没有匹配；未读取 secret。": "No namespace matches; no secrets were read.",
        "目录超过 1000 个或 16 层，范围未完成。": "Directory count exceeds 1000 or depth exceeds 16; scope is incomplete.",
        "匹配 secret 超过 1000 个。": "More than 1000 secrets matched.",
        "没有匹配的配置名称；请修改两侧各自的名称或目录模式。": "No configuration names matched. Adjust each side's name or directory pattern.",
        "范围预览已超过 5 分钟，请重新预览。": "Scope preview is older than 5 minutes. Preview again.", "KV 版本已改变，请重新预览。": "KV version changed. Preview again.",
        "缺少必需的输入": "Required input is missing", "单侧输入超过 20 MiB": "One input exceeds 20 MiB",
        "所选对象不存在；请从实际候选中选择": "Selected object does not exist; choose an actual candidate",
        "缺少已读取条目": "Captured entries are missing", "读取条目须为 1–1000 个": "Captured entries must number 1–1000",
        "配对键不能为空": "Pairing keys must not be empty", "来源响应总量超过 20 MiB": "Total source responses exceed 20 MiB", "读取条目配对键重复": "Captured entries have duplicate pairing keys",
        "两侧必须同时选择单根或全部变量模式": "Both sides must use either single-root mode or all-variable mode",
        "不支持的输入方式": "Unsupported input kind", "结果超过 100000 项": "Results exceed 100000 items", "结果存储不可用": "Result storage is unavailable",
        "结果已释放，请重新比较": "Results were released; compare again", "结果项不存在": "Result item does not exist",
        "不支持的本地操作": "Unsupported local operation", "请求超过资源限制": "Request exceeds resource limits", "本地计算中断；可以重新比较": "Local computation interrupted; compare again", "请求格式无效": "Invalid request format", "请求编码不受支持": "Unsupported request encoding",
        "别名必须引用同一文档中先前声明的 anchor": "An alias must reference a previously declared anchor in the same document",
        "YAML 节点或深度超过限制": "YAML node count or depth exceeds limits",
        "当前格式化仅支持字符串 Key；不会自动改变 Key 类型": "Formatting supports string keys only; key types will not be changed",
        "YAML 有重复 Key；未生成覆盖后的结果": "YAML contains duplicate keys; no overwritten output was generated",
        "当前不格式化集合或别名形式的 Key": "Collection and alias keys are not supported for formatting",
        "YAML 语法错误；原内容已保留": "YAML syntax error; original content is preserved", "YAML CST 解析失败": "YAML CST parsing failed", "无法安全格式化 YAML": "YAML could not be formatted safely",
        "格式化改变了字符串表示，已阻止输出": "Formatting changed a string representation; output blocked",
        "格式化前后内容、引用或注释不一致，已阻止输出": "Content, references, or comments differed after formatting; output blocked",
        "JSON 输入无法可靠解析": "JSON input could not be parsed reliably", "输入包装不符合已选择类型": "Input wrapper does not match the selected type", "输入根必须为对象": "Input root must be an object",
        "路径映射必须由非空路径及纯配置对象组成": "A path map must contain nonempty paths and plain configuration objects", "路径映射根必须为对象": "Path map root must be an object", "请选择明确的 Vault JSON 输入类型": "Select an explicit Vault JSON input type",
        "没有可比较的配置对象；不将删除或空响应判为缺失": "No comparable configuration object; deleted or empty responses are not treated as absence",
        "JavaScript 解析超过栈或步骤预算": "JavaScript parsing exceeds the stack or step budget",
        "JavaScript 语法错误；不会执行或自动修复输入": "JavaScript syntax error; input will not be executed or automatically repaired",
        "重复或冲突的词法绑定": "Duplicate or conflicting lexical bindings", "JavaScript 静态求值达到资源限制": "JavaScript static evaluation reached resource limits",
        "当前静态支持范围不接受嵌套变量声明": "Nested variable declarations are outside static support",
        "不支持重声明只读全局常量": "Redeclaring read-only global constants is unsupported",
        "顶层 module/exports 重声明不在当前静态支持范围": "Redeclaring top-level module/exports is outside static support", "重复或冲突的顶层绑定": "Duplicate or conflicting top-level bindings",
        "词法变量在初始化之前被读取": "Lexical variable read before initialization",
        "不支持访问器或方法属性；不会执行输入": "Accessor and method properties are unsupported; input will not be executed",
        "不支持修改对象原型": "Changing an object prototype is unsupported", "不支持重绑定特殊全局变量": "Rebinding special global variables is unsupported",
        "词法变量在初始化前被赋值": "Lexical variable assigned before initialization", "不支持向未声明变量赋值": "Assignment to undeclared variables is unsupported", "const 绑定不能重赋值": "A const binding cannot be reassigned", "引用展开达到资源限制": "Reference expansion reached resource limits",
        "JavaScript 条件分支达到资源限制": "JavaScript conditional branches reached resource limits",
        "条件分支中的声明及复杂控制语句不在静态支持范围；未执行分支也不会静默忽略": "Declarations and complex control flow in branches are outside static support; unvisited branches are not silently ignored",
        "字符串转义不完整": "Incomplete string escape", "不支持旧式八进制转义": "Legacy octal escapes are unsupported", "Unicode 转义无效": "Invalid Unicode escape", "Unicode 转义不完整": "Incomplete Unicode escape", "旧式八进制字符串转义不在支持范围": "Legacy octal string escapes are outside support",
        "导出失败；新文件可能不完整，请检查后另选文件名重新导出。": "Export failed; the new file may be incomplete. Check it and export under another filename."
    ]
}
