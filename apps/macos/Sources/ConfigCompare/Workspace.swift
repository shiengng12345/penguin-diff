import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CompareShared
import Darwin

enum Tool: String, CaseIterable, Identifiable {
    case env = "env.js 比较", vault = "Vault 比较", yaml = "YAML 格式化"
    var id: String { rawValue }
    var icon: String { switch self { case .env: "curlybraces"; case .vault: "doc.on.doc"; case .yaml: "text.alignleft" } }
}

@MainActor
final class Workspace: ObservableObject {
    @Published var tool: Tool = .env
    @Published var a = ""
    @Published var b = ""
    @Published var labelA = "A · 粘贴或打开文件"
    @Published var labelB = "B · 粘贴或打开文件"
    @Published var rootA = "*"
    @Published var rootB = "*"
    @Published var rootsA = ["env", "module.exports"]
    @Published var rootsB = ["env", "module.exports"]
    @Published var inputTypeA = "plain-object"
    @Published var inputTypeB = "plain-object"
    @Published var indent = 2
    @Published var rows: [ResultRow] = []
    @Published var summary: Summary?
    @Published var complete = true
    @Published var incomplete: [String] = []
    @Published var warnings: [SourceWarning] = []
    @Published var warningCount = 0
    @Published var output = ""
    @Published var busy = false
    @Published private(set) var importingA = false
    @Published private(set) var importingB = false
    var importing: Bool { importingA || importingB }
    var canStop: Bool { busy || importing }
    @Published var treeMode = false
    @Published var stale = false
    @Published private(set) var noticeMessage: LocalizedMessage = .text("完全离线 · 手动输入 · 原文件不覆盖")
    var notice: String { noticeMessage.render(in: .simplifiedChinese) }
    var noticeLocalized: String { noticeMessage.render(in: preferences.language) }
    let preferences: AppPreferences
    @Published var showingSettings = false
    func showSettings() { showingSettings = true }
    func closeSettings() { showingSettings = false }
    func showTool(_ next: Tool) { showingSettings = false; tool = next }
    func resultName(_ path: String) -> String {
        if tool == .vault {
            return ResultPathDisplay.visible(path, vault: true)
        }
        guard tool == .env else { return path }
        let rootName = rootA == "*" && rootB == "*" ? preferences.text("全部变量")
            : rootA == rootB ? rootA : preferences.text("比较根")
        return OutlinePath.variableDisplay(path, rootName: rootName)
    }
    func inputLabel(side: Bool) -> String {
        let label = side ? labelA : labelB, file = side ? fileA : fileB
        return file == nil && label == (side ? "A · 粘贴或打开文件" : "B · 粘贴或打开文件") ? preferences.text(label) : label
    }
    @Published var error = false
    @Published var selected: Int? {
        didSet {
            selectedGroup = nil
            if oldValue != selected { selectionToken = UUID(); detail = nil }
        }
    }
    @Published private(set) var selectedGroup: ResultOutlineID?
    var outlineSelection: ResultOutlineID? { selected.map { .result($0) } ?? selectedGroup }
    @Published var detail: ResultRow?
    @Published var filter = "differences"
    @Published var search = ""
    @Published var searchScope = "all"
    @Published var page = 0
    @Published var matched = 0
    @Published var exportFiltered = false
    @Published var exportValues = true
    @Published var vaultLive = true
    @Published var vaultA = VaultSettings()
    @Published var vaultB = VaultSettings()
    @Published var vaultPlanA: VaultPlan?
    @Published var vaultPlanB: VaultPlan?
    @Published var vaultNamespacesA: [String] = []
    @Published var vaultNamespacesB: [String] = []
    @Published var vaultAdvancedA = false
    @Published var vaultAdvancedB = false
    @Published private(set) var vaultCatalogA: VaultCatalog?
    @Published private(set) var vaultCatalogB: VaultCatalog?
    @Published private(set) var vaultContentsA: VaultContents?
    @Published private(set) var vaultContentsB: VaultContents?
    @Published var vaultCaptureInfo: [[String:String]] = []
    @Published var vaultSources: [VaultSourceSnapshot] = []
    private let vaultFactory: ((@escaping VaultReader.Validator) -> any VaultReading)
    private var generation = RequestGeneration()
    private var client: any WorkerSending
    private let clientFactory: () -> any WorkerSending
    private let fileReader: @Sendable (URL) async throws -> String
    private let reportDestination: @MainActor (String, String) -> URL?
    private(set) var fileA: URL?
    private(set) var fileB: URL?
    private var session: String?
    private var operation: Task<Void, Never>?
    private var rowsToken = UUID()
    private struct RowsRequestKey: Equatable {
        let session: String
        let page: Int
        let filter: String
        let search: String
        let searchScope: String
    }
    private var activeRowsRequest: RowsRequestKey?
    private var rowFailurePending = false
    private var comparisonNotice: LocalizedMessage = .text("比较完成。")
    private var selectionToken = UUID()
    private var importTokenA = UUID()
    private var importTokenB = UUID()
    private let importFinished: @MainActor () -> Void
    init(clientFactory: @escaping () -> any WorkerSending = { WorkerClient() },
         vaultFactory: @escaping (@escaping VaultReader.Validator) -> any VaultReading = { VaultReader(validate: $0) },
         fileReader: @escaping @Sendable (URL) async throws -> String = { url in
             try await Task.detached(priority: .userInitiated) { try InputFiles.read(url) }.value
         }, reportDestination: @escaping @MainActor (String, String) -> URL? = { extensionName, message in
             let panel = NSSavePanel()
             panel.nameFieldStringValue = "config-result." + extensionName
             panel.allowedContentTypes = [UTType(filenameExtension: extensionName) ?? .plainText]
             panel.message = message
             return panel.runModal() == .OK ? panel.url : nil
         }, preferences: AppPreferences? = nil,
         importFinished: @escaping @MainActor () -> Void = {}) {
        self.preferences = preferences ?? AppPreferences(defaults: nil, preferredLanguages: ["zh-Hans"])
        self.clientFactory = clientFactory
        self.vaultFactory = vaultFactory
        self.client = clientFactory()
        self.fileReader = fileReader
        self.reportDestination = reportDestination
        self.importFinished = importFinished
    }

    func changed(side: Bool? = nil) {
        if let side {
            if side { importTokenA = UUID(); importingA = false }
            else { importTokenB = UUID(); importingB = false }
        }
        _ = generation.begin()
        if busy { stopComputation() }
        stale = summary != nil || !output.isEmpty
        if stale { publishNotice(.text("输入已改变，结果已过期；请重新运行。")) }
        detail = nil
        selected = nil
    }
    func swapSides() {
        guard !busy, !importing, tool != .yaml else { return }
        changed()
        selectionToken = UUID()
        swap(&a, &b)
        swap(&fileA, &fileB)
        let firstLabel = labelA, secondLabel = labelB
        labelA = "A · " + (secondLabel.hasPrefix("B · ") ? String(secondLabel.dropFirst(4)) : secondLabel)
        labelB = "B · " + (firstLabel.hasPrefix("A · ") ? String(firstLabel.dropFirst(4)) : firstLabel)
        swap(&rootA, &rootB)
        swap(&rootsA, &rootsB)
        swap(&inputTypeA, &inputTypeB)
        swap(&vaultA, &vaultB)
        vaultA.confirmedNonProduction = false; vaultB.confirmedNonProduction = false
        vaultPlanA = nil; vaultPlanB = nil
        vaultCatalogA = nil; vaultCatalogB = nil; vaultContentsA = nil; vaultContentsB = nil
        vaultNamespacesA = []; vaultNamespacesB = []; vaultCaptureInfo = []; vaultSources = []
        publishNotice(.text(tool == .vault && vaultLive
            ? "已交换 A/B；请重新读取选项并预览。MCP 已保存的授权不随界面交换而改变。"
            : "已交换 A/B 输入和设置；旧结果已过期，请重新比较。"))
    }
    func switchTool() {
        stopImports()
        stopComputation()
        a = ""; b = ""; output = ""; fileA = nil; fileB = nil
        vaultA.token = ""; vaultB.token = ""; vaultA.confirmedNonProduction = false; vaultB.confirmedNonProduction = false
        vaultCatalogA = nil; vaultCatalogB = nil; vaultContentsA = nil; vaultContentsB = nil
        vaultPlanA = nil; vaultPlanB = nil; vaultNamespacesA = []; vaultNamespacesB = []; vaultCaptureInfo = []; vaultSources = []
        labelA = "A · 粘贴或打开文件"; labelB = "B · 粘贴或打开文件"
        publishNotice(.text(tool == .vault && vaultLive ? "手动只读连接非生产 Vault · 先预览范围再读取" : "完全离线 · 手动输入 · 原文件不覆盖")); stale = false
    }
    func cancel() {
        let onlyImports = importing && !busy
        stopImports()
        if onlyImports { publishNotice(.text("文件导入已停止；输入和已有结果保留。")) }
        else { stopComputation() }
    }
    private func stopImports() {
        importTokenA = UUID(); importTokenB = UUID()
        importingA = false; importingB = false
    }
    private func stopComputation() {
        _ = generation.begin()
        operation?.cancel()
        client.abort()
        client = clientFactory()
        activeRowsRequest = nil
        busy = false; session = nil; rows = []; summary = nil; detail = nil; selected = nil
        vaultCaptureInfo = []; vaultSources = []
        matched = 0; page = 0; complete = true; incomplete = []; warnings = []; warningCount = 0
        if !output.isEmpty { stale = true }
        publishNotice(.text("操作已停止，输入仍保留。"))
    }
    private func encode(_ request: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
    }
    private func perform(_ request: String) async throws -> CoreResponse {
        try CoreResponse.decode(try await client.send(request))
    }
    private func publishNotice(_ message: LocalizedMessage, isError: Bool = false) {
        rowFailurePending = false
        error = isError
        noticeMessage = message
    }
    private func describe(_ failure: any Error) {
        let message: LocalizedMessage
        if let failure = failure as? CoreError {
            message = .joined([.literal(failure.code + "："), .text(failure.message), failure.line > 0 ? .text("（第 {0} 行，UTF-8 字节列 {1}）", [String(failure.line), String(failure.column)]) : .literal("")])
        } else if failure is CancellationError { message = .text("本地计算已停止。") }
        else if let failure = failure as? VaultFailure { message = .joined([.literal(failure.code + "："), .text(failure.message)]) }
        else if let failure = failure as? WorkerFailure { message = .text(failure.localizedDescription) }
        else { message = L10n.localError(failure as NSError) }
        publishNotice(message, isError: true)
    }
    func run() {
        guard !busy, !importing else { return }
        if tool == .vault, vaultLive { compareVault(); return }
        let token = generation.begin()
        let id = UUID().uuidString
        var request: [String: Any] = ["op": "compare", "kind": tool == .env ? "js" : "json", "a": a, "b": b, "rootA": rootA, "rootB": rootB, "inputTypeA": inputTypeA, "inputTypeB": inputTypeB, "session": id]
        if tool == .yaml { request = ["op": "formatYaml", "source": a, "indent": indent] }
        guard let encoded = try? encode(request) else { describe(WorkerFailure.invalidRequest); return }
        let oldSession = session
        session = nil; rows = []; summary = nil; output = ""; detail = nil; selected = nil; warnings = []; warningCount = 0
        busy = true; stale = false; publishNotice(.text("正在本机处理…"))
        operation = Task {
            do {
                if let oldSession { _ = try? await perform(encode(["op": "release", "session": oldSession])) }
                let result = try await perform(encoded)
                guard generation.accepts(token), !Task.isCancelled else { return }
                if tool == .yaml { output = result.text ?? ""; publishNotice(.text("格式化完成：已核对标量、注释、引用和文档顺序。")) }
                else {
                    session = result.session; summary = result.summary; complete = result.complete ?? false; incomplete = result.incompleteRanges ?? []
                    warnings = result.warnings ?? []
                    warningCount = result.warningCount ?? warnings.count
                    rows = result.rows ?? []; filter = "differences"; page = 0
                    publishNotice(.text(complete ? "比较完成。" : "结果不完整：存在无法静态确认的内容，不能判定整体相同。"))
                    comparisonNotice = noticeMessage
                }
                busy = false
                if tool != .yaml { loadRows() }
            } catch {
                guard generation.accepts(token) else { return }
                busy = false; describe(error)
                client.abort(); client = clientFactory()
            }
        }
    }
    func vaultChanged(side: Bool, old: VaultSettings, new: VaultSettings) {
        if old.url != new.url || old.token != new.token || old.namespace != new.namespace || old.namespacePattern != new.namespacePattern {
            if side { vaultCatalogA = nil; vaultContentsA = nil; vaultNamespacesA = [] } else { vaultCatalogB = nil; vaultContentsB = nil; vaultNamespacesB = [] }
        } else if old.mount != new.mount || old.directory != new.directory {
            if side { vaultContentsA = nil } else { vaultContentsB = nil }
        }
        if old.url != new.url || old.namespace != new.namespace || old.namespacePattern != new.namespacePattern {
            if side { vaultA.confirmedNonProduction = false; vaultNamespacesA = [] }
            else { vaultB.confirmedNonProduction = false; vaultNamespacesB = [] }
        }
        vaultPlanA = nil; vaultPlanB = nil; vaultCaptureInfo = []; vaultSources = []
        changed()
        if old.namespace != new.namespace || old.namespacePattern != new.namespacePattern {
            publishNotice(.text("namespace 范围已改变；请重新读取选项。"))
        }
    }
    func unpackVaultLink(side: Bool) {
        do {
            var settings = side ? vaultA : vaultB
            let link = try VaultLink.parse(settings.url)
            if let namespace = link.namespaceHint { settings.updateNamespace(namespace) }
            settings.url = link.origin
            if let mount = link.mount { settings.updateMount(mount) }
            if let path = link.path, !path.isEmpty {
                let parts = path.split(separator: "/").map(String.init)
                let name = parts.last ?? ""
                settings.updateDirectory("")
                let pattern = parts.dropLast().joined(separator: "/")
                settings.updateDirectoryPattern(pattern.isEmpty ? "." : pattern, contents: nil)
                settings.environment = name
            }
            settings.confirmedNonProduction = false
            if side { vaultA = settings } else { vaultB = settings }
            publishNotice(.text("链接已拆解。要匹配各目录的同名配置，将目录匹配改为 **；名称和 mount 均可编辑。"))
        } catch { describe(error) }
    }
    func authorizeMCP() {
        do {
            guard let first = vaultPlanA, let second = vaultPlanB, !busy,
                  first.target == (try VaultTarget(vaultA)), second.target == (try VaultTarget(vaultB)) else { throw VaultFailure.invalid("请先预览两侧非生产范围，才能授权 MCP。") }
            try MCPVaultAuthorization.save(a:vaultA,b:vaultB,first:first,second:second)
            publishNotice(.text("已授权 MCP 使用当前两侧范围；Token 只保存到本机钥匙串。更改界面字段不会自动修改这份授权，可重新授权或撤销。"))
        } catch { describe(error) }
    }
    func revokeMCP() {
        do { try MCPVaultAuthorization.revoke(); publishNotice(.text("已撤销 Vault MCP 授权并删除钥匙串中的这份凭证。")) }
        catch { describe(error) }
    }
    func copyMCPConfiguration() {
        let executable = Bundle.main.executableURL?.path ?? ""
        guard !executable.isEmpty else { return }
        let config: [String:Any] = ["mcpServers":["config-compare":["command":executable,"args":["--mcp"]]]]
        if let data = try? JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys]) { copy(String(decoding:data,as:UTF8.self)) }
    }
    private func makeVaultReader() -> any VaultReading {
        // Dedicated worker connection: credentials are never passed into this validator.
        let validatorClient = clientFactory()
        return vaultFactory { raw, version, status in
            var fields: [String:Any] = ["op":version == nil ? "validateJson" : "inspectVaultRead", "source":raw]
            if let version { fields["kvVersion"] = version; fields["httpStatus"] = status }
            let data = try JSONSerialization.data(withJSONObject: fields)
            let response = try await validatorClient.send(String(decoding:data,as:UTF8.self))
            return try CoreResponse.decode(response)
        }
    }
    func discoverVault(side: Bool, contents: Bool = false) {
        guard !busy, !importing, tool == .vault, vaultLive else { return }
        let settings = side ? vaultA : vaultB
        do {
            _ = try VaultConnection(settings)
            if contents { _ = try VaultPath.segments(settings.mount) }
            let reader = makeVaultReader()
            let token = generation.begin()
            if side {
                vaultContentsA = nil
                if !contents { vaultCatalogA = nil }
            } else {
                vaultContentsB = nil
                if !contents { vaultCatalogB = nil }
            }
            vaultPlanA = nil; vaultPlanB = nil; vaultCaptureInfo = []; vaultSources = []
            stale = summary != nil; busy = true; detail = nil; selected = nil
            publishNotice(.text("正在读取选项；尚未读取配置值…"))
            operation = Task {
                do {
                    if contents {
                        let result = try await reader.discoverContents(settings)
                        guard generation.accepts(token), !Task.isCancelled else { return }
                        guard settings == (side ? vaultA : vaultB) else { busy = false; publishNotice(.text("连接输入已改变；请重新读取选项。")); return }
                        if side { vaultContentsA = result } else { vaultContentsB = result }
                        busy = false
                        if settings.environment.isEmpty, let link = try? VaultLink.parse(settings.url), link.mount == settings.mount, let path = link.path,
                           let name = path.split(separator: "/").last.map(String.init), result.configurations(forDirectory: settings.directoryPattern).contains(name) {
                            if side { vaultA.environment = name } else { vaultB.environment = name }
                        }
                        publishNotice(.text(result.configurations.isEmpty ? "没有可选配置；可在高级设置中手动输入。" : "配置选项已读取；选择名称和目录范围后预览。"))
                    } else {
                        let result = try await reader.discoverConnection(settings)
                        guard generation.accepts(token), !Task.isCancelled else { return }
                        guard settings == (side ? vaultA : vaultB) else { busy = false; publishNotice(.text("连接输入已改变；请重新读取选项。")); return }
                        if side { vaultCatalogA = result } else { vaultCatalogB = result }
                        busy = false
                        if settings.mount.isEmpty, let mount = (try? VaultLink.parse(settings.url))?.mount, result.mounts.contains(mount) {
                            if side { var updated = vaultA; updated.updateMount(mount); vaultA = updated }
                            else { var updated = vaultB; updated.updateMount(mount); vaultB = updated }
                        }
                        publishNotice(.text(result.mounts.isEmpty ? "没有可见的 KV mount；可在高级设置中手动输入。" : "连接选项已读取；请选择 KV mount，再读取配置名称。"))
                    }
                } catch {
                    guard generation.accepts(token), !Task.isCancelled else { return }
                    busy = false
                    if side { vaultAdvancedA = true } else { vaultAdvancedB = true }
                    describe(error)
                }
            }
        } catch { describe(error) }
    }
    func previewVault() {
        guard !busy else { return }
        do {
            let first = try VaultTarget(vaultA), second = try VaultTarget(vaultB)
            let readerA = makeVaultReader(), readerB = makeVaultReader()
            let token = generation.begin()
            vaultPlanA = nil; vaultPlanB = nil; stale = summary != nil; busy = true
            detail = nil; selected = nil
            publishNotice(.text("正在列举确认范围；尚未读取 secret 值…"))
            operation = Task {
                do {
                    let aPlan = try await readerA.preview(first)
                    let bPlan = try await readerB.preview(second)
                    guard generation.accepts(token), !Task.isCancelled else { return }
                    vaultPlanA = aPlan; vaultPlanB = bPlan
                    vaultNamespacesA = aPlan.discoveredNamespaces; vaultNamespacesB = bPlan.discoveredNamespaces
                    busy = false; publishNotice(.text("预览完成：A {0} 个、B {1} 个配置。核对范围后点击读取并比较。", [String(aPlan.secrets.count), String(bPlan.secrets.count)]))
                } catch {
                    guard generation.accepts(token) else { return }
                    busy = false; describe(error)
                }
            }
        } catch { describe(error) }
    }
    private func compareVault() {
        do {
            guard let first = vaultPlanA, let second = vaultPlanB,
                  first.target == (try VaultTarget(vaultA)), second.target == (try VaultTarget(vaultB)) else {
                throw VaultFailure.invalid("请先预览并核对两侧匹配范围。")
            }
            let readerA = makeVaultReader(), readerB = makeVaultReader()
            let token = generation.begin(), id = UUID().uuidString
            busy = true; stale = summary != nil; warnings = []; warningCount = 0
            detail = nil; selected = nil
            publishNotice(.text("正在只读取得两侧配置；Token 不进入比较核心…"))
            operation = Task {
                do {
                    let capturedA = try await readerA.capture(first)
                    let capturedB = try await readerB.capture(second)
                    try Task.checkCancellation()
                    let aMap = try await perform(encode(["op":"vaultSnapshot","entries":capturedA.entries]))
                    let bMap = try await perform(encode(["op":"vaultSnapshot","entries":capturedB.entries]))
                    let result = try await perform(encode(["op":"compare","kind":"json","a":aMap.text ?? "","b":bMap.text ?? "","session":id]))
                    guard generation.accepts(token), !Task.isCancelled else { return }
                    session = result.session; summary = result.summary; complete = result.complete ?? false
                    incomplete = result.incompleteRanges ?? []; rows = result.rows ?? []
                    warnings = result.warnings ?? []
                    warningCount = result.warningCount ?? warnings.count
                    filter = "differences"; page = 0; stale = false; busy = false; detail = nil; selected = nil
                    vaultCaptureInfo = [capturedA,capturedB].enumerated().map { index, value in
                        ["side":index == 0 ? "A" : "B","url":value.plan.target.origin,"namespaceRoot":value.plan.target.namespace,"namespacePattern":value.plan.target.namespacePattern,"mount":value.plan.target.mount,"directoryRoot":value.plan.target.directory,"directoryPattern":value.plan.target.directoryPattern,"configurationName":value.plan.target.environment,"started":value.started.ISO8601Format(),"finished":value.finished.ISO8601Format(),"secretCount":String(value.entries.count)]
                    }
                    vaultSources = [VaultSourceSnapshot(capturedA, side: "A"), VaultSourceSnapshot(capturedB, side: "B")]
                    publishNotice(.text("已比较 A {0} / B {1} 个配置，按相对 namespace 和目录配对；各条读取不是原子快照。", [String(capturedA.entries.count), String(capturedB.entries.count)]))
                    comparisonNotice = noticeMessage
                    loadRows()
                } catch {
                    guard generation.accepts(token) else { return }
                    busy = false; describe(error)
                    publishNotice(.joined([noticeMessage, .text(" 本次整批未完成，不生成缺失或相同结论。")]), isError: true)
                    client.abort(); client = clientFactory()
                }
            }
        } catch { describe(error) }
    }
    func inspectRoots() {
        guard tool == .env, !busy, !importing else { return }
        let token = generation.begin()
        let sourceA = a, sourceB = b
        busy = true; publishNotice(.text("正在检查静态根候选…"))
        operation = Task {
            do {
                let first = try await perform(encode(["op":"inspectJs", "source":sourceA]))
                let second = try await perform(encode(["op":"inspectJs", "source":sourceB]))
                guard generation.accepts(token) else { return }
                rootsA = first.roots ?? []; rootsB = second.roots ?? []
                let missing = (rootA != "*" && !rootsA.contains(rootA)) || (rootB != "*" && !rootsB.contains(rootB))
                busy = false
                publishNotice(.text(missing ? "所选变量不存在，请重新选择比较范围。" : "变量列表已更新。"))
            } catch { guard generation.accepts(token) else { return }; busy = false; describe(error) }
        }
    }
    var resultControlsDisabled: Bool { stale || busy || importing }

    func changePage(by delta: Int) {
        guard !resultControlsDisabled, session != nil, matched > 0 else { return }
        let (next, overflow) = page.addingReportingOverflow(delta)
        guard !overflow, next >= 0, next <= (matched - 1) / 200, next != page else { return }
        requestRows(page: next)
    }

    func loadRows(reset: Bool = false) {
        requestRows(page: reset ? 0 : page)
    }

    private func requestRows(page requestedPage: Int) {
        guard let session, !resultControlsDisabled else { return }
        let (offset, overflow) = requestedPage.multipliedReportingOverflow(by: 200)
        guard requestedPage >= 0, !overflow else { return }
        let key = RowsRequestKey(session: session, page: requestedPage, filter: filter, search: search, searchScope: searchScope)
        // SwiftUI option changes and the compare completion can both ask for
        // the same first page in one turn. Keep one transport request for that
        // exact snapshot; a later call after it settles remains a real refresh.
        guard activeRowsRequest != key else { return }
        let request = try? encode(["op":"rows", "session":session, "filter":filter, "search":search, "searchScope":searchScope, "offset":offset, "limit":200])
        guard let request else { return }
        let token = UUID()
        rowsToken = token
        activeRowsRequest = key
        operation = Task {
            defer { if self.rowsToken == token { self.activeRowsRequest = nil } }
            do {
                let response = try await perform(request)
                guard rowsToken == token, self.session == session, !stale, !Task.isCancelled else { return }
                page = requestedPage
                rows = response.rows ?? []; matched = response.matched ?? 0; selected = nil; detail = nil
                if rowFailurePending {
                    if error { publishNotice(comparisonNotice) }
                    else { rowFailurePending = false }
                }
            } catch {
                guard rowsToken == token, self.session == session, !stale, !Task.isCancelled else { return }
                describe(error); rowFailurePending = true
            }
        }
    }
    func selectOutline(_ selection: ResultOutlineID?) {
        guard selection != outlineSelection else { return }
        selectionToken = UUID(); detail = nil
        if case .result(let id) = selection { selected = id }
        else { selected = nil; selectedGroup = selection }
    }
    func inspectSelection() {
        selectionToken = UUID()
        guard let selected, let session, !stale else { detail = nil; return }
        let token = selectionToken
        detail = nil
        Task {
            do {
                let response = try await perform(encode(["op":"details", "session":session, "id":selected]))
                guard token == selectionToken, self.session == session, !stale else { return }
                detail = response.row
            } catch { if token == selectionToken { describe(error) } }
        }
    }
    func open(side: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = preferences.text("读取本地文件；内容不会发送到任何服务。")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            self.importFile(url, side: side)
        }
    }
    func importFile(_ url: URL, side: Bool) {
        guard url.isFileURL else { publishNotice(.text("仅接受本地文件。"), isError: true); return }
        let token = UUID()
        if side { importTokenA = token; importingA = true }
        else { importTokenB = token; importingB = true }
        Task { @MainActor in
            defer { importFinished() }
            do {
                let text = try await fileReader(url)
                guard token == (side ? importTokenA : importTokenB) else { return }
                changed(side: side)
                if side { a = text; fileA = url; labelA = "A · " + url.lastPathComponent }
                else { b = text; fileB = url; labelB = "B · " + url.lastPathComponent }
                publishNotice(.text("文件已载入；比较使用当前编辑内容。"))
            } catch {
                if token == (side ? importTokenA : importTokenB) {
                    if side { importingA = false } else { importingB = false }
                    describe(error)
                }
            }
        }
    }
    func copy(_ text: String, pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        publishNotice(.text("已复制；剪贴板会保留内容，直至被替换。"))
    }
    func export(_ format: ResultExportFormat = .typedJSON) {
        guard !stale, !busy else { return }
        let token = generation.begin()
        Task {
            do {
                var content = output
                let extensionName = tool == .yaml ? "yaml" : format.fileExtension
                if tool != .yaml {
                    guard let session else { return }
                    let request = try encode(["op":"report", "session":session, "filter":exportFiltered ? filter : "all", "search":exportFiltered ? search : "", "searchScope":searchScope, "includeValues":exportValues, "format":format == .csv ? "csv" : "json", "sourceA":labelA, "sourceB":labelB])
                    let raw = try await client.send(request)
                    let response = try CoreResponse.decode(raw)
                    if format == .csv {
                        content = response.text ?? ""
                    } else {
                        var report = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String:Any]
                        if tool == .vault, vaultLive {
                            report["sources"] = vaultCaptureInfo
                            report["vaultSources"] = try VaultSourceSnapshot.json(vaultSources)
                            report["snapshotAtomic"] = false
                        }
                        switch format {
                        case .typedJSON:
                            content = String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
                        case .jsonArray:
                            content = try ResultExportRenderer.jsonArray(from: report, vault: tool == .vault && vaultLive)
                        case .html:
                            content = ResultExportRenderer.html(from: report, title: preferences.text(tool.rawValue), sourceA: labelA, sourceB: labelB, language: preferences.language, vault: tool == .vault && vaultLive)
                        case .csv:
                            break
                        }
                    }
                }
                guard generation.accepts(token), !stale else { return }
                if let url = reportDestination(extensionName, preferences.text("仅保存到新文件。原输入和已有文件不会覆盖。报告可能包含敏感配置值。")) {
                    guard generation.accepts(token), !stale else { return }
                    try InputFiles.writeNew(Data(content.utf8), to: url, inputs: [fileA,fileB].compactMap { $0 })
                    publishNotice(.text("已导出到新文件：{0}", [url.lastPathComponent]))
                }
            } catch {
                guard generation.accepts(token), !stale, !Task.isCancelled else { return }
                describe(error)
            }
        }
    }

    // Keep the previous test/helper call shape while the menu uses named formats.
    func export(_ csv: Bool) {
        export(csv ? .csv : .typedJSON)
    }
}
