import SwiftUI
import AppKit
import CompareShared
import Darwin

public struct ConfigCompareApp: App {
    @NSApplicationDelegateAdaptor(ConfigCompareAppDelegate.self) private var appDelegate
    @StateObject private var preferences: AppPreferences
    @StateObject private var workspace: Workspace
    public init() {
        let preferences = AppPreferences(defaults: .standard)
        _preferences = StateObject(wrappedValue: preferences)
        _workspace = StateObject(wrappedValue: Workspace(preferences: preferences))

    }
    public var body: some Scene {
        WindowGroup("Config Compare") { WorkspaceView(model: workspace).environmentObject(preferences)
            .tint(preferences.accent.color).accentColor(preferences.accent.color)
            .preferredColorScheme(.light)
            .onChange(of: preferences.theme, initial: true) { _, theme in AppAppearance.apply(theme) }
            .environment(\.locale, Locale(identifier: preferences.language.rawValue))
            .frame(minWidth: 1050, minHeight: 700) }
            .defaultSize(width: 1440, height: 900)
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(preferences.text("设置") + "…") { workspace.showSettings() }.keyboardShortcut(",")
                }
                CommandGroup(after: .newItem) {
                    Button(preferences.text("打开 A 文件…")) { workspace.open(side: true) }.keyboardShortcut("o").disabled(workspace.showingSettings)
                    Button(preferences.text("运行")) { workspace.run() }.keyboardShortcut(.return, modifiers: .command).disabled(workspace.showingSettings || workspace.busy || workspace.importing)
                    Button(preferences.text("交换 A/B")) { workspace.swapSides() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(workspace.showingSettings || workspace.busy || workspace.importing || workspace.tool == .yaml)
                    Button(preferences.text("停止当前操作")) { workspace.cancel() }.keyboardShortcut(.cancelAction).disabled(workspace.showingSettings || !workspace.canStop)
                    Button(preferences.text("清空输入和结果")) { workspace.switchTool() }.disabled(workspace.showingSettings)
                }
            }
    }
}

let statusNames: [String: String] = ["SAME":"相同", "VALUE_CHANGED":"值变化", "TYPE_CHANGED":"类型变化", "ONLY_A":"仅 A", "ONLY_B":"仅 B", "NOT_COMPARABLE":"无法比较"]

struct WorkspaceView: View {
    @ObservedObject var model: Workspace
    @EnvironmentObject private var preferences: AppPreferences
    @State private var detailOpen = false
    @State private var sourcesOpen = false
    @State private var resultTableOpen = false
    private func tr(_ key: String, _ arguments: String...) -> String { L10n.text(key, arguments: arguments, language: preferences.language) }
    var body: some View {
        ZStack {
            toolWorkspace
                .opacity(model.showingSettings ? 0 : 1)
                .allowsHitTesting(!model.showingSettings).disabled(model.showingSettings)
                .accessibilityElement(children: model.showingSettings ? .ignore : .contain)
                .accessibilityHidden(model.showingSettings)
            if model.showingSettings { SettingsView { model.closeSettings() }.background(AppPalette.background) }
        }
        .font(.system(size: 13)).foregroundStyle(AppPalette.ink)
        .buttonStyle(AppButtonStyle()).background(AppPalette.background)
        .onAppear { NSApp.windows.forEach { $0.isRestorable = false }; if model.selected != nil { detailOpen = true } }
        .onChange(of: model.showingSettings) { _, showing in
            if showing { sourcesOpen = false; resultTableOpen = false; NSApp.windows.forEach { $0.makeFirstResponder(nil) } }
        }
        .onChange(of: model.tool) { _, _ in model.switchTool(); detailOpen = false; sourcesOpen = false; resultTableOpen = false }
        .onChange(of: model.stale) { _, stale in if stale { detailOpen = false; sourcesOpen = false; resultTableOpen = false } }
        .onChange(of: model.busy) { _, busy in if busy { detailOpen = false; sourcesOpen = false; resultTableOpen = false } }
        .onChange(of: SourceTextSnapshot(value: model.a)) { _, _ in model.changed(side: true) }
        .onChange(of: SourceTextSnapshot(value: model.b)) { _, _ in model.changed(side: false) }
        .onChange(of: model.rootA) { _, _ in model.changed() }
        .onChange(of: model.rootB) { _, _ in model.changed() }
        .onChange(of: model.inputTypeA) { _, _ in model.changed() }
        .onChange(of: model.inputTypeB) { _, _ in model.changed() }
        .onChange(of: model.indent) { _, _ in model.changed() }
        .onChange(of: model.vaultLive) { _, _ in model.switchTool() }
        .onChange(of: model.vaultA) { old, new in model.vaultChanged(side: true, old: old, new: new) }
        .onChange(of: model.vaultB) { old, new in model.vaultChanged(side: false, old: old, new: new) }
        .sheet(isPresented: $resultTableOpen) {
            resultTableSheet
                .environmentObject(preferences)
                .preferredColorScheme(.light)
                .onDisappear { detailOpen = false }
        }
    }
    private var toolWorkspace: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(AppPalette.line).frame(width: 1)
            GeometryReader { geometry in
                if model.tool == .vault && model.vaultLive {
                    VStack(alignment: .leading, spacing: geometry.size.height < 800 ? 10 : 14) {
                        pageHeader
                        GeometryReader { bodyGeometry in
                            ScrollView {
                                workspaceContent(height: geometry.size.height, includeHeader: false)
                                    .frame(minHeight: bodyGeometry.size.height, alignment: .top)
                            }.scrollIndicators(.visible)
                        }
                    }.padding(24)
                } else {
                    workspaceContent(height: geometry.size.height).padding(24)
                }
            }
        }.background(AppPalette.background)
    }
    private func workspaceContent(height: CGFloat, includeHeader: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: height < 800 ? 10 : 14) {
            if includeHeader { pageHeader }
            if model.tool == .vault {
                Picker(tr("Vault 来源"), selection: $model.vaultLive) {
                    Text(tr("URL + Token 直连")).tag(true); Text(tr("已有 JSON（可选）")).tag(false)
                }.pickerStyle(.segmented).frame(maxWidth: 440)
            }
            if model.tool == .vault && model.vaultLive {
                vaultInputs(viewportHeight: model.summary == nil
                    ? min(360, max(294, height * 0.42))
                    : min(250, max(160, height * 0.22)))
            }
            else { inputs.frame(height: min(230, max(168, height * 0.255))) }
            noticeBar
            if model.tool == .yaml { yamlResult } else { compareResult(compact: height < 800) }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppPalette.rose).frame(width: 40, height: 40)
                    .background(AppPalette.selection, in: RoundedRectangle(cornerRadius: 12))
                Text("Config Compare").font(.system(size: 16, weight: .bold))
            }.padding(.bottom, 28).padding(.top, 6)
            ForEach(Tool.allCases) { tool in
                navigation(tr(tool.rawValue), icon: tool.icon, selected: model.tool == tool) { model.showTool(tool) }
            }
            Spacer(minLength: 16)
            Image(systemName: "doc.text.magnifyingglass").font(.system(size: 42, weight: .light))
                .foregroundStyle(AppPalette.pink.opacity(0.65)).frame(width: 150, height: 100).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Label(tr("SRE 配置小工具"), systemImage: "desktopcomputer")
                Text(tr("Vault 仅手动读取非生产")).font(.system(size: 11))
            }.foregroundStyle(AppPalette.secondary).font(.system(size: 12)).padding(.horizontal, 10).padding(.bottom, 18)
            navigation(tr("设置"), icon: "gearshape", selected: false) { model.showSettings() }
            Button { model.copyMCPConfiguration() } label: { Label(tr("复制 MCP 配置"), systemImage: "link").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(AppButtonStyle(compact: true)).padding(.top, 2)
        }.padding(16).frame(width: 224).background(AppPalette.sidebar)
    }
    private func navigation(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium)).frame(width: 22)
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 12).frame(height: 44)
                .foregroundStyle(selected ? AppPalette.rose : AppPalette.secondary)
                .background(selected ? AppPalette.selection : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? AppPalette.pink.opacity(0.45) : .clear))
        }.buttonStyle(AppNavigationStyle()).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr(model.tool.rawValue)).font(.system(size: 25, weight: .bold))
                Text(tr(model.tool == .yaml ? "只调整排版，保留注释、引号和引用。" : "按键和类型比较；对象键顺序不会产生差异。"))
                    .font(.system(size: 12)).foregroundStyle(AppPalette.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            if model.canStop { ProgressView().controlSize(.small); Button(tr("停止")) { model.cancel() } }
            Button { model.run() } label: {
                Label(tr(model.tool == .yaml ? "格式化" : (model.tool == .vault && model.vaultLive ? "读取并比较" : "开始比较")), systemImage: model.tool == .yaml ? "text.alignleft" : "arrow.left.arrow.right")
            }.buttonStyle(AppButtonStyle(primary: true))
                .disabled(model.busy || model.importing || (model.tool == .vault && model.vaultLive ? model.vaultPlanA == nil || model.vaultPlanB == nil : model.a.isEmpty || (model.tool != .yaml && model.b.isEmpty)))
        }
    }
    private var noticeBar: some View {
        HStack(spacing: 8) {
            Image(systemName: model.error ? "exclamationmark.triangle" : (model.stale || !model.complete ? "info.circle" : "checkmark.circle"))
            Text(model.noticeLocalized).textSelection(.enabled).lineLimit(2)
            Spacer(minLength: 0)
        }.font(.system(size: 12)).foregroundStyle(model.error ? Color(hex: 0x9C493F) : AppPalette.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(model.error || !model.complete ? AppPalette.coral : AppPalette.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }
    private func vaultInputs(viewportHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    VaultConnectionPanel(title: "A", settings: $model.vaultA, advanced: $model.vaultAdvancedA, namespaces: model.vaultNamespacesA, plan: model.vaultPlanA, catalog: model.vaultCatalogA, contents: model.vaultContentsA, busy: model.busy, discover: { model.discoverVault(side: true, contents: $0) }) { model.unpackVaultLink(side: true) }
                    VaultConnectionPanel(title: "B", settings: $model.vaultB, advanced: $model.vaultAdvancedB, namespaces: model.vaultNamespacesB, plan: model.vaultPlanB, catalog: model.vaultCatalogB, contents: model.vaultContentsB, busy: model.busy, discover: { model.discoverVault(side: false, contents: $0) }) { model.unpackVaultLink(side: false) }
                }.padding(1)
            }.scrollIndicators(.visible).frame(height: viewportHeight)
            HStack {
                Text(tr("两侧配置名称可不同；按相对 namespace / 目录配对。* 一层，** 任意层，. 当前范围。"))
                    .font(.system(size: 11)).foregroundStyle(AppPalette.secondary)
                Spacer(minLength: 8)
                Button(tr("预览匹配范围")) { model.previewVault() }.disabled(model.busy)
                Button { model.swapSides() } label: { Image(systemName: "arrow.left.arrow.right") }.help(tr("交换 A/B")).accessibilityLabel(tr("交换 A/B")).disabled(model.busy || model.importing)
            }
            DisclosureGroup("MCP") {
                HStack {
                    Text(tr("MCP：Token 保存在本机钥匙串；已保存授权不随界面编辑或 A/B 交换改变。使用新范围需重新预览授权。")).font(.caption).foregroundStyle(AppPalette.secondary)
                    Spacer()
                    Button(tr("授权 MCP 使用当前范围")) { model.authorizeMCP() }.disabled(model.busy || model.vaultPlanA == nil || model.vaultPlanB == nil)
                    Button(tr("撤销 MCP 授权")) { model.revokeMCP() }
                }
            }.font(.caption)
        }
    }
    private var inputs: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 48) {
                input(side: true)
                if model.tool != .yaml { input(side: false) }
            }
            if model.tool != .yaml {
                Button { model.swapSides() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(AppButtonStyle(compact: true)).offset(y: 14)
        .help(tr("交换两侧输入和设置；需要重新比较，Vault 需要重新读取选项和预览。"))
                    .accessibilityLabel(tr("交换 A/B")).disabled(model.busy || model.importing)
            }
        }
    }
    private func inputDescription(side: Bool) -> String {
        let label = model.inputLabel(side: side)
        let prefix = side ? "A · " : "B · "
        return label.hasPrefix(prefix) ? String(label.dropFirst(prefix.count)) : label
    }
    private func input(side: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SourceMark(name: side ? "A" : "B")
                Text(inputDescription(side: side)).lineLimit(1).truncationMode(.middle).help(model.inputLabel(side: side)).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if side ? model.importingA : model.importingB { ProgressView().controlSize(.mini) }
                Button { model.open(side: side) } label: { Image(systemName: "folder").font(.system(size: 14)) }
                    .buttonStyle(AppButtonStyle(compact: true)).help(tr("打开文件…")).accessibilityLabel((side ? "A " : "B ") + tr("打开文件…")).disabled(model.busy)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(AppPalette.line).frame(height: 1)
            SourceEditor(text: side ? $model.a : $model.b, editable: true, syntax: model.tool == .yaml ? .yaml : (model.tool == .vault ? .json : .javascript))
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
                .accessibilityLabel(side ? tr("A 输入编辑器") : tr("B 输入编辑器"))
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    guard !model.busy, let provider = providers.first else { return false }
                    _ = provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                        guard let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return }
                        Task { @MainActor in model.importFile(url, side: side) }
                    }
                    return true
                }
            Rectangle().fill(AppPalette.line).frame(height: 1)
            inputControls(side: side).padding(.horizontal, 12).frame(height: 40)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.line))
    }
    @ViewBuilder private func inputControls(side: Bool) -> some View {
        if model.tool == .env {
            HStack(spacing: 8) {
                Text(tr("比较范围")).font(.system(size: 11)).foregroundStyle(AppPalette.secondary)
                Picker(tr("比较范围"), selection: side ? $model.rootA : $model.rootB) {
                    Text(tr("全部变量")).tag("*")
                    ForEach(side ? model.rootsA : model.rootsB, id: \.self) { root in Text(root).tag(root) }
                    let selected = side ? model.rootA : model.rootB
                    if selected != "*", !(side ? model.rootsA : model.rootsB).contains(selected) { Text(selected + " " + tr("（未找到）")).tag(selected) }
                }.labelsHidden().help(tr("按名称比较文件中的所有顶层变量；也可选择单一变量。"))
                Spacer(minLength: 0)
                // Identical control footprint on both sides; either refresh inspects both inputs.
                Button { model.inspectRoots() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(AppButtonStyle(compact: true))
                    .help(tr("刷新变量列表")).accessibilityLabel(tr("刷新变量列表")).disabled(model.busy || model.importing)
            }
        } else if model.tool == .vault {
            Picker(tr("输入格式"), selection: side ? $model.inputTypeA : $model.inputTypeB) {
                Text(tr("纯配置对象")).tag("plain-object"); Text(tr("路径映射：路径 → 配置对象")).tag("path-map")
                Text(tr("KV v1 响应：data")).tag("kv-v1-response"); Text(tr("KV v2 响应：data.data")).tag("kv-v2-response")
            }
        } else {
            Picker(tr("缩进"), selection: $model.indent) { Text(tr("2 空格")).tag(2); Text(tr("4 空格")).tag(4) }.frame(width: 190)
        }
    }
    private var yamlResult: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("格式化结果")).font(.system(size: 14, weight: .semibold)); Spacer()
                Button(tr("复制结果")) { model.copy(model.output) }.disabled(model.output.isEmpty || model.stale || model.busy)
                Button(tr("导出 YAML…")) { model.export() }.disabled(model.output.isEmpty || model.stale || model.busy)
            }
            if model.output.isEmpty {
                EmptyStateView(title: tr("格式化后，结果会出现在这里。"), symbol: "text.alignleft").appCard(padding: 0)
            } else {
                SourceEditor(text: .constant(model.output), editable: false, syntax: .yaml).accessibilityLabel(tr("只读 YAML 格式化结果"))
                    .clipShape(RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.line))
            }
        }.frame(maxHeight: .infinity)
    }
    private func compareResult(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            if let summary = model.summary {
                if model.stale { Text(tr("上一轮结果（已过期）")).font(.caption.bold()).foregroundStyle(Color(hex: 0x8C5323)) }
                statistics(summary, height: compact ? 52 : 62)
                if !model.warnings.isEmpty {
                    DisclosureGroup(tr(model.stale ? "源码警告 · {0} 项（已过期）" : "源码警告 · {0} 项", String(model.warningCount))) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(model.warnings.prefix(200).enumerated()), id: \.offset) { _, warning in
                                    Text(tr("{0} · 第 {1} 行，UTF-8 字节列 {2}；上次定义在第 {3} 行，列 {4}", warning.side ?? "", String(warning.line), String(warning.column), String(warning.previousLine), String(warning.previousColumn)) + "\n" + tr(warning.message))
                                }
                                if model.warningCount > model.warnings.count {
                                    Text(tr("此处显示前 200 项；完整警告可在 JSON 报告查看。"))
                                }
                            }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 90)
                    }.font(.caption).foregroundStyle(Color(hex: 0x8C5323)).opacity(model.stale ? 0.55 : 1)
                }
                if !model.complete {
                    DisclosureGroup(tr("结果不完整 · {0} 个诊断范围", String(model.incomplete.count))) {
                        ScrollView { Text(model.incomplete.map { tr($0) }.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 70)
                    }.font(.caption).foregroundStyle(Color(hex: 0x8C5323))
                }

            }
            if model.summary != nil {
                resultToolbar
            }
            HStack(spacing: 12) {
                Group {
                    if model.rows.isEmpty {
                        EmptyStateView(title: emptyTitle, subtitle: emptySubtitle, symbol: model.busy ? "hourglass" : "doc.text.magnifyingglass")
                    } else {
                        ResultTableView(model: model) { detailOpen = true }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).appCard(padding: 10)
                if detailOpen {
                    inspector.frame(width: 290).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.line))
                }
            }.frame(minHeight: model.tool == .vault && model.vaultLive ? 148 : nil)
                .opacity(model.stale ? 0.60 : 1).disabled(model.stale || model.busy)
            if model.summary != nil { resultFooter }
        }
        .onChange(of: model.filter) { _, _ in model.loadRows(reset: true) }
        .onChange(of: model.search) { _, _ in model.loadRows(reset: true) }
        .onChange(of: model.searchScope) { _, _ in model.loadRows(reset: true) }
        .onChange(of: model.selected) { _, selected in model.inspectSelection(); if selected != nil { detailOpen = true } else { detailOpen = false } }
    }
    private var emptyTitle: String {
        if model.busy { return tr("正在检查配置…") }
        if model.tool == .vault && model.vaultLive && model.summary == nil && !model.error {
            return tr("填写两侧 Vault 来源，并预览非生产范围。")
        }
        if model.error { return tr("操作未完成，请查看上方提示。") }
        if model.summary == nil {
            if model.a.isEmpty && !model.b.isEmpty { return tr("先放入 A 侧配置。") }
            if !model.a.isEmpty && model.b.isEmpty { return tr("再放入 B 侧配置，即可开始比较。") }
            if !model.a.isEmpty && !model.b.isEmpty { return tr("两份配置已就绪。") }
        }
        return tr(ComparisonPresentation.emptyTitle(summary: model.summary, complete: model.complete, stale: model.stale, error: model.error, search: model.search, filter: model.filter))
    }
    private var emptySubtitle: String {
        if model.tool == .vault && model.vaultLive && model.summary == nil { return tr("确认匹配目录后，只读获取配置并比较。") }
        if model.tool == .vault && model.summary == nil { return tr("两侧按 JSON 键和类型比较。") }
        return model.summary == nil ? tr("两侧按变量名和类型比较，安全解析，不运行配置代码。") : (model.matched == 0 && (model.filter != "differences" || !model.search.isEmpty) ? tr("调整搜索或筛选条件。") : "")
    }
    private func statistics(_ summary: Summary, height: CGFloat) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { statisticItems(summary, height: height) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) { statisticItems(summary, height: height) }
        }
    }
    @ViewBuilder private func statisticItems(_ s: Summary, height: CGFloat) -> some View {
        statistic("总计", s.total, background: AppPalette.card, ink: AppPalette.ink, symbol: "square.grid.2x2", height: height)
        statistic("相同", s.same, tone: .SAME, height: height)
        statistic("值变化", s.valueChanged, tone: .VALUE_CHANGED, height: height)
        statistic("类型变化", s.typeChanged, tone: .TYPE_CHANGED, height: height)
        statistic("仅 A", s.onlyA, tone: .ONLY_A, height: height)
        statistic("仅 B", s.onlyB, tone: .ONLY_B, height: height)
        statistic("无法比较", s.notComparable, tone: .NOT_COMPARABLE, height: height)
    }
    private func statistic(_ title: String, _ count: Int, tone: ResultTone, height: CGFloat) -> some View {
        statistic(title, count, background: tone.background, ink: tone.ink, symbol: tone.symbol, height: height)
    }
    private func statistic(_ title: String, _ count: Int, background: Color, ink: Color, symbol: String, height: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(String(count)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                Text(tr(title)).font(.system(size: 11)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.foregroundStyle(ink).padding(.horizontal, 12).frame(minWidth: 94, maxWidth: .infinity).frame(height: height)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppPalette.line.opacity(0.6)))
            .accessibilityElement(children: .ignore).accessibilityLabel(tr(title) + " " + String(count))
    }
    private var resultToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { searchField; statusFilter; scopeFilter; viewFilter; resultTableButton; sourcesButton }
            VStack(spacing: 8) { searchField; HStack(spacing: 10) { statusFilter; scopeFilter; viewFilter; resultTableButton; Spacer(); sourcesButton } }
        }.disabled(model.resultControlsDisabled)
    }
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppPalette.secondary)
            TextField(tr(model.tool == .env ? "搜索变量或值（区分大小写）" : "搜索路径或值（区分大小写）"), text: $model.search).textFieldStyle(.plain)
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel(tr("清除搜索"))
            }
        }.padding(.horizontal, 12).frame(minWidth: 180, maxWidth: .infinity).frame(height: 34)
            .background(AppPalette.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(AppPalette.line))
    }
    private var statusFilter: some View {
        Picker(tr("状态"), selection: $model.filter) {
            Text(tr("差异与无法比较")).tag("differences"); Text(tr("全部")).tag("all")
            ForEach(ResultTone.allCases, id: \.rawValue) { tone in Text(tr(statusNames[tone.rawValue]!)).tag(tone.rawValue) }
        }.labelsHidden().accessibilityLabel(tr("状态")).frame(width: 175)
    }
    private var resultTableButton: some View {
        Button {
            resultTableOpen = true
        } label: {
            Label(tr("弹出结果表"), systemImage: "rectangle.expand.vertical")
        }
        .buttonStyle(AppButtonStyle(compact: true))
        .help(tr("在更大的窗口查看完整结果表"))
        .accessibilityLabel(tr("弹出结果表"))
    }
    private var scopeFilter: some View {
        Picker(tr("范围"), selection: $model.searchScope) { Text(tr("键和值")).tag("all"); Text(tr(model.tool == .env ? "变量" : "路径")).tag("key"); Text(tr("值")).tag("value") }
            .labelsHidden().accessibilityLabel(tr("范围")).frame(width: 105)
    }
    private var viewFilter: some View {
        Picker(tr("显示"), selection: $model.treeMode) { Text(tr("平面")).tag(false); Text(tr("当前页树")).tag(true) }
            .pickerStyle(.segmented).labelsHidden().accessibilityLabel(tr("显示")).frame(width: 160)
    }
    @ViewBuilder private var sourcesButton: some View {
        if model.tool == .vault && !model.vaultSources.isEmpty {
            Button(tr("Vault 来源")) { sourcesOpen.toggle() }.buttonStyle(AppButtonStyle(compact: true))
                .popover(isPresented: $sourcesOpen) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(tr("Vault 来源")).font(.headline)
                            Spacer()
                            Button { sourcesOpen = false } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("关闭详情"))
                        }
                        ScrollView { VaultSourcesView(sources: model.vaultSources, preferences: preferences) }
                    }.padding(16).frame(width: 480, height: 400)
                        .foregroundStyle(AppPalette.ink).background(AppPalette.card)
                        .buttonStyle(AppButtonStyle(compact: true)).preferredColorScheme(.light)
            }
        }
    }
    private var resultTableSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("比较结果表")).font(.system(size: 22, weight: .bold))
                    Text(tr("整张结果表在独立弹出窗口中显示；筛选、搜索、分页和详情与主页面同步。"))
                        .font(.caption).foregroundStyle(AppPalette.secondary)
                }
                Spacer(minLength: 12)
                Button { resultTableOpen = false; detailOpen = false } label: {
                    Label(tr("关闭"), systemImage: "xmark")
                }.buttonStyle(AppButtonStyle(compact: true)).accessibilityLabel(tr("关闭"))
            }
            resultToolbar
            HStack(spacing: 12) {
                Group {
                    if model.rows.isEmpty {
                        EmptyStateView(title: emptyTitle, subtitle: emptySubtitle, symbol: model.busy ? "hourglass" : "doc.text.magnifyingglass")
                    } else {
                        ResultTableView(model: model) { detailOpen = true }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).appCard(padding: 10)
                if detailOpen {
                    inspector.frame(width: 340).clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppPalette.line))
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            resultFooter
        }
        .padding(20)
        .frame(minWidth: 1180, minHeight: 720)
        .background(AppPalette.background)
    }
    private var resultFooter: some View {
        HStack(spacing: 8) {
            Button { model.changePage(by: -1) } label: { Image(systemName: "chevron.left") }.help(tr("上一页")).accessibilityLabel(tr("上一页")).disabled(model.page == 0)
            Text(tr("{0} 项匹配 · 第 {1} 页（每页 200 项）", String(model.matched), String(model.page + 1))).font(.system(size: 11)).foregroundStyle(AppPalette.secondary)
            Button { model.changePage(by: 1) } label: { Image(systemName: "chevron.right") }.help(tr("下一页")).accessibilityLabel(tr("下一页")).disabled((model.page + 1) * 200 >= model.matched)
            Spacer(minLength: 8)
            Toggle(tr("仅当前筛选"), isOn: $model.exportFiltered).toggleStyle(.checkbox)
            Toggle(tr("包含配置值"), isOn: $model.exportValues).toggleStyle(.checkbox)
            Menu(tr("导出…")) {
                Button(tr("类型化 JSON 报告")) { model.export(.typedJSON) }
                Button(tr("JSON 数组（结果行）")) { model.export(.jsonArray) }
                Button(tr("HTML 可读报告")) { model.export(.html) }
                Button(tr("CSV 报告")) { model.export(.csv) }
            }
                .disabled(model.summary == nil || model.stale || model.busy)
        }.font(.system(size: 11)).buttonStyle(AppButtonStyle(compact: true)).disabled(model.resultControlsDisabled)
    }
    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(tr("详情")).font(.headline)
                    Spacer()
                    Button { detailOpen = false } label: { Image(systemName: "xmark") }.help(tr("关闭详情")).accessibilityLabel(tr("关闭详情"))
                }
                if let row = model.detail {
                    Text(model.resultName(row.path)).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    Button(tr(model.tool == .env ? "复制变量" : "复制路径")) { model.copy(model.resultName(row.path)) }
                    sideDetail("A", row.a)
                    if !model.stale, !model.busy, row.a.present, let source = model.vaultSources.first(where: { $0.side == "A" }), let observation = source.observation(for: row) {
                        VaultObservationView(source: source, observation: observation, preferences: preferences)
                    }
                    Divider()
                    sideDetail("B", row.b)
                    if !model.stale, !model.busy, row.b.present, let source = model.vaultSources.first(where: { $0.side == "B" }), let observation = source.observation(for: row) {
                        VaultObservationView(source: source, observation: observation, preferences: preferences)
                    }
                } else {
                    Text(tr("选择一行查看完整值与类型")).foregroundStyle(.secondary).padding(.top, 20)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }.background(AppPalette.card)
    }
    private func sideDetail(_ name: String, _ side: Side) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(name + " · " + L10n.typeName(side.type, language: preferences.language)).font(.headline)
            if let line = side.line, line > 0 { Text(tr("第 {0} 行 · UTF-8 字节列 {1}", String(line), String(side.column ?? 0))).font(.caption).foregroundStyle(.secondary) }
            Text(["Missing", "Hole", "Unknown"].contains(side.type)
                 ? L10n.valuePreview(type: side.type, display: side.literal ?? side.display, language: preferences.language)
                 : (side.literal ?? side.display)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            ValueOutlineView(side: side, variableNames: model.tool == .env)
            Button(tr("复制 {0} 完整值", String(name))) { model.copy(side.literal ?? side.display) }.disabled(!side.present)
        }
    }
}
