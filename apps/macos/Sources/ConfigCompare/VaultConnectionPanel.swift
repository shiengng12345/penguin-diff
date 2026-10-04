import SwiftUI

struct VaultConnectionPanel: View {
    @EnvironmentObject private var preferences: AppPreferences
    private func tr(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments, language: preferences.language) }
    let title: String
    @Binding var settings: VaultSettings
    @Binding var advanced: Bool
    let namespaces: [String]
    let plan: VaultPlan?
    let catalog: VaultCatalog?
    let contents: VaultContents?
    let busy: Bool
    let discover: (Bool) -> Void
    let unpack: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SourceMark(name: title); Text(tr("来源 {0}", title)).font(.headline); Spacer()
                Button(tr("读取选项")) { discover(false) }
                    .buttonStyle(AppButtonStyle(compact: true)).disabled(cannotDiscover)
            }
            TextField(tr("Vault URL 或网页链接"), text: $settings.url).accessibilityLabel(title + " Vault URL")
            SecureField(tr("Token（仅本次会话）"), text: $settings.token).accessibilityLabel(title + " Vault Token")
            if catalog == nil, !settings.namespace.isEmpty {
                Text(tr("当前 namespace：{0}", settings.namespace)).font(.caption).foregroundStyle(AppPalette.secondary).lineLimit(1).help(settings.namespace)
            }
            if let catalog {
                HStack(alignment: .top, spacing: 12) {
                    choice("Namespace", selection: Binding(get: { settings.namespace }, set: { settings.updateNamespace($0) }), options: catalog.namespaces, emptyLabel: "root")
                    choice("KV mount", selection: Binding(get: { settings.mount }, set: {
                        settings.updateMount($0)
                    }), options: catalog.mounts)
                }
                HStack {
                    Text(tr("先选 KV mount，再读取配置名称。")).font(.caption).foregroundStyle(AppPalette.secondary)
                    Spacer(minLength: 4)
                    Button(tr("读取配置名称")) { discover(true) }.buttonStyle(AppButtonStyle(compact: true))
                        .disabled(cannotDiscover || settings.mount.isEmpty)
                }
                if catalog.namespaceListingUnavailable {
                    Text(tr("无法列举 namespace；可使用当前范围或在高级设置中指定。")).font(.caption).foregroundStyle(AppPalette.secondary)
                }
                if catalog.mounts.isEmpty {
                    Text(tr("没有可见的 KV mount；可在高级设置中手动输入。")).font(.caption).foregroundStyle(AppPalette.secondary)
                }
            }
            if let contents {
                HStack(alignment: .top, spacing: 12) {
                    choice(tr("目录范围"), selection: directoryPatternBinding,
                           options: ["**"] + contents.directories, emptyLabel: nil, allDirectories: true, preserveUnlistedSelection: false)
                    choice(tr("配置名称"), selection: Binding(get: { settings.environment }, set: {
                        settings.selectConfiguration($0, contents: contents)
                    }), options: contents.configurations(forDirectory: settings.directoryPattern), preserveUnlistedSelection: false)
                }
                if contents.configurations(forDirectory: settings.directoryPattern).isEmpty {
                    Text(tr("没有可选配置；可在高级设置中手动输入。")).font(.caption).foregroundStyle(AppPalette.secondary)
                }
            }
            if catalog?.excludedProduction == true || contents?.excludedProduction == true {
                Text(tr("已排除带生产标识的选项；没有读取这些配置。")).font(.caption).foregroundStyle(AppPalette.secondary)
            }
            DisclosureGroup(tr("高级设置 · 手动输入与通配符"), isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        field("KV mount", text: mountBinding, hint: tr("例如 FPMS-NT-V2，可编辑"))
                        field(tr("配置名称"), text: $settings.environment, hint: tr("例如 uat-swim；两侧独立编辑"))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        field(tr("Namespace 根"), text: Binding(get: { settings.namespace }, set: { settings.updateNamespace($0) }), hint: tr("Namespace 根（空 = root）"))
                        field(tr("Namespace 匹配"), text: Binding(get: { settings.namespacePattern }, set: { settings.updateNamespacePattern($0) }), hint: tr(". 或 team-* / **"))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        field(tr("目录根"), text: directoryRootBinding, hint: tr("空 = mount 根；例如 auth"))
                        field(tr("目录匹配"), text: directoryPatternBinding, hint: ". / * / ** / auth*")
                    }
                    Button(tr("拆解链接"), action: unpack).buttonStyle(AppButtonStyle(compact: true))
                    if catalog == nil, !settings.mount.isEmpty {
                        Button(tr("读取配置名称")) { discover(true) }.buttonStyle(AppButtonStyle(compact: true)).disabled(cannotDiscover)
                    }
                }.padding(.top, 6)
            }.font(.caption)
            if let plan {
                DisclosureGroup(tr("已匹配 {0} 个配置 · 展开核对", String(plan.secrets.count))) {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(Array(plan.secrets.enumerated()), id: \.offset) { _, secret in Text(secret.label).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 90)
                }.font(.caption)
            }
        }.textFieldStyle(.roundedBorder).frame(maxWidth: .infinity).appCard()
    }
    private var cannotDiscover: Bool { busy || settings.url.isEmpty || settings.token.isEmpty }
    private var mountBinding: Binding<String> {
        Binding(get: { settings.mount }, set: { value in
            settings.updateMount(value)
        })
    }
    private var directoryRootBinding: Binding<String> {
        Binding(get: { settings.directory }, set: { value in
            settings.updateDirectory(value)
        })
    }
    private var directoryPatternBinding: Binding<String> {
        Binding(get: { settings.directoryPattern }, set: { value in
            settings.updateDirectoryPattern(value, contents: contents)
        })
    }
    private func choice(_ name: String, selection: Binding<String>, options: [String], emptyLabel: String? = nil, allDirectories: Bool = false, preserveUnlistedSelection: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).lineLimit(1)
            Picker(name, selection: selection) {
                if !options.contains("") { Text(tr("请选择…")).tag("") }
                if preserveUnlistedSelection, !selection.wrappedValue.isEmpty, !options.contains(selection.wrappedValue) {
                    Text(selection.wrappedValue).tag(selection.wrappedValue)
                }
                ForEach(options, id: \.self) { value in
                    Text(allDirectories && value == "**" ? tr("全部目录") : (value.isEmpty ? (emptyLabel ?? "root") : (allDirectories && value == "." ? tr("当前目录") : value))).tag(value)
                }
            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(title + " " + name).help(allDirectories && selection.wrappedValue == "**" ? tr("全部目录（含子目录）") : selection.wrappedValue).disabled(busy)
        }.frame(maxWidth: .infinity)
    }
    private func field(_ name: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).lineLimit(1)
            TextField(hint, text: text).accessibilityLabel(title + " " + name).frame(height: 28)
        }.frame(maxWidth: .infinity)
    }
}
