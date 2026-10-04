import Foundation
import MCP
import CompareShared

@MainActor
final class MCPService {
    private let worker: any WorkerSending
    private let workerFactory: () -> any WorkerSending
    private let vaultFactory: (@escaping VaultReader.Validator) -> any VaultReading
    private let authorization: () throws -> MCPVaultPair
    private var plans: [String:(MCPVaultPair,VaultPlan,VaultPlan)] = [:]
    private var planOrder: [String] = []
    private var busy = false
    private var vaultSessions: [String:MCPVaultPair] = [:]
    private var vaultSources: [String:[VaultSourceSnapshot]] = [:]
    private var sessionOrder: [String] = []
    init(workerFactory: @escaping () -> any WorkerSending = { WorkerClient() },
         vaultFactory: @escaping (@escaping VaultReader.Validator) -> any VaultReading = { VaultReader(validate:$0) },
         authorization: @escaping () throws -> MCPVaultPair = { try MCPVaultAuthorization.load() }) {
        self.workerFactory = workerFactory; worker = workerFactory(); self.vaultFactory = vaultFactory; self.authorization = authorization
    }
    static var tools: [MCP.Tool] {
        func text(_ description: String) -> MCP.Value { .object(["type":.string("string"),"description":.string(description)]) }
        func tool(_ name: String, _ description: String, _ properties: [String:MCP.Value], _ required: [String], network: Bool = false) -> MCP.Tool {
            .init(name:name,description:description,inputSchema:.object(["type":.string("object"),"properties":.object(properties),"required":.array(required.map{.string($0)}),"additionalProperties":.bool(false)]),annotations:.init(readOnlyHint:true,destructiveHint:false,idempotentHint:true,openWorldHint:network))
        }
        let values: MCP.Value = .object(["type":.string("boolean"),"default":.bool(false),"description":.string("是否向 MCP 客户端返回配置值；默认仅返回路径、类型、状态。")])
        let root: MCP.Value = .object(["type":.string("string"),"default":.string("*"),"description":.string("默认 *，一次按名称比较所有顶层变量，不重复计数导出根；也可指定 env、module.exports 或其他命名变量。两侧须同时为全变量或单变量模式。")])
        return [
            tool("env_compare","静态比较两份 env.js，默认一次比较文件内全部顶层变量，不执行脚本。返回 summary、前200项差异、前200项源码警告及各自总数和结果 session；默认不返回配置值。",["a":text("A JS 文本"),"b":text("B JS 文本"),"rootA":root,"rootB":root,"includeValues":values],["a","b"]),
            tool("yaml_format","本机 YAML 格式化，保留注释、引号与引用；只返回文本，不写文件。",["source":text("YAML 文本"),"indent":.object(["type":.string("integer"),"enum":.array([.int(2),.int(4)]),"default":.int(2)])],["source"]),
            tool("vault_preview","列举 App 已授权的两侧非生产 Vault 范围，返回 planId 与匹配清单，不读取 secret 值。不能通过参数更换 URL、Token 或范围。",[:],[],network:true),
            tool("vault_compare","读取并比较 vault_preview 的匹配清单。仅使用 App 已授权的两侧范围；Token 不进入 MCP。各条读取不是原子快照。",["planId":text("vault_preview 返回的 planId，有效5分钟"),"includeValues":values],["planId"],network:true),
            tool("comparison_rows","分页取得之前比较的差异和源码警告，各自每页最多200项。offset控制差异，warningOffset独立控制警告；警告不随差异筛选消失。warningCount和hasMoreWarnings说明剩余警告，默认不返回配置值。",["session":text("比较返回的 session"),"offset":.object(["type":.string("integer"),"minimum":.int(0),"maximum":.int(100000)]),"warningOffset":.object(["type":.string("integer"),"minimum":.int(0),"maximum":.int(100000),"default":.int(0),"description":.string("源码警告的独立偏移；警告位置按A/B和源码顺序排列。")]),"filter":.object(["type":.string("string"),"enum":.array(["all","differences","SAME","VALUE_CHANGED","TYPE_CHANGED","ONLY_A","ONLY_B","NOT_COMPARABLE"].map{.string($0)})]),"includeValues":values],["session"])
        ]
    }
    private func core(_ fields: [String:Any]) async throws -> (String, CoreResponse) {
        try Task.checkCancellation()
        let data = try JSONSerialization.data(withJSONObject:fields)
        let raw = try await worker.send(String(decoding:data,as:UTF8.self))
        try Task.checkCancellation()
        return (raw,try CoreResponse.decode(raw))
    }
    private func reader() -> any VaultReading {
        let validator = workerFactory()
        return vaultFactory { raw, version, status in
            var fields: [String:Any] = ["op":version == nil ? "validateJson" : "inspectVaultRead", "source":raw]
            if let version { fields["kvVersion"] = version; fields["httpStatus"] = status }
            let request = try JSONSerialization.data(withJSONObject:fields)
            return try CoreResponse.decode(try await validator.send(String(decoding:request,as:UTF8.self)))
        }
    }
    private func report(_ session: String, includeValues: Bool, offset: Int = 0, filter: String = "differences", warningOffset: Int = 0) async throws -> String {
        if let pair = vaultSessions[session], try authorization() != pair { throw VaultFailure.invalid("这份 Vault 结果的授权已更改或撤销，不能读取。") }
        let (raw,_) = try await core(["op":"report","session":session,"includeValues":includeValues,"offset":offset,"limit":200,"filter":filter,"warningOffset":warningOffset,"warningLimit":200])
        var result = try JSONSerialization.jsonObject(with:Data(raw.utf8)) as! [String:Any]
        result["session"] = session; result["offset"] = offset; result["pageSize"] = 200
        if let sources = vaultSources[session] {
            result["vaultSources"] = try VaultSourceSnapshot.json(sources)
            result["snapshotAtomic"] = false
        }
        return String(decoding:try JSONSerialization.data(withJSONObject:result),as:UTF8.self)
    }
    private func remember(_ session: String, pair: MCPVaultPair? = nil, sources: [VaultSourceSnapshot]? = nil) {
        if sessionOrder.count >= 4 {
            let oldest = sessionOrder.removeFirst(); vaultSessions.removeValue(forKey:oldest); vaultSources.removeValue(forKey:oldest)
        }
        sessionOrder.append(session)
        if let pair { vaultSessions[session] = pair }
        if let sources { vaultSources[session] = sources }
    }
    func call(name: String, arguments: [String:MCP.Value]) async -> CallTool.Result {
        guard !busy else { return .init(content:[.text(text:"MCP_BUSY：请等待当前调用完成，或取消后重试。",annotations:nil,_meta:nil)],isError:true) }
        busy = true; defer { busy = false }
        do {
            let allowed: Set<String>
            switch name {
            case "env_compare": allowed = ["a","b","rootA","rootB","includeValues"]
            case "yaml_format": allowed = ["source","indent"]
            case "vault_preview": allowed = []
            case "vault_compare": allowed = ["planId","includeValues"]
            case "comparison_rows": allowed = ["session","offset","filter","includeValues","warningOffset"]
            default: throw VaultFailure.invalid("未知 MCP 工具。")
            }
            guard Set(arguments.keys).isSubset(of:allowed) else { throw VaultFailure.invalid("包含工具未允许的参数；连接凭证与范围不能由 MCP 参数修改。") }
            func string(_ key: String, fallback: String? = nil) throws -> String {
                if let value = arguments[key]?.stringValue { return value }
                if arguments[key] == nil, let fallback { return fallback }
                throw VaultFailure.invalid("缺少或无效的字符串参数：" + key)
            }
            if let value = arguments["includeValues"], value.boolValue == nil { throw VaultFailure.invalid("includeValues 必须是 Boolean。") }
            let includesValues = arguments["includeValues"]?.boolValue ?? false
            let output: String
            var guardedPair: MCPVaultPair?
            switch name {
            case "env_compare":
                let session = UUID().uuidString
                _ = try await core(["op":"compare","kind":"js","a":try string("a"),"b":try string("b"),"rootA":try string("rootA",fallback:"*"),"rootB":try string("rootB",fallback:"*"),"session":session])
                remember(session)
                output = try await report(session,includeValues:includesValues)
            case "yaml_format":
                let indent = arguments["indent"]?.intValue ?? 2
                guard arguments["indent"] == nil || arguments["indent"]?.intValue != nil, [2,4].contains(indent) else { throw VaultFailure.invalid("indent 只能是整数2或4。") }
                output = try await core(["op":"formatYaml","source":try string("source"),"indent":indent]).1.text ?? ""
            case "vault_preview":
                let pair = try authorization()
                guardedPair = pair
                let readerA = reader(), readerB = reader()
                let first = try await readerA.preview(VaultTarget(pair.a)), second = try await readerB.preview(VaultTarget(pair.b))
                try pair.validate(first:first,second:second)
                guard try authorization() == pair else { throw VaultFailure.invalid("授权在读取期间已更改或撤销。") }
                let id = UUID().uuidString
                if plans.count >= 4, let oldest = planOrder.first { plans.removeValue(forKey:oldest); planOrder.removeFirst() }
                plans[id] = (pair,first,second); planOrder.append(id)
                let value: [String:Any] = ["planId":id,"expiresInSeconds":300,"a":first.secrets.map(\.label),"b":second.secrets.map(\.label),"configurationA":pair.a.environment,"configurationB":pair.b.environment,"mountA":pair.a.mount,"mountB":pair.b.mount]
                output = String(decoding:try JSONSerialization.data(withJSONObject:value),as:UTF8.self)
            case "vault_compare":
                let id = try string("planId")
                guard let (pair,first,second) = plans[id], try authorization() == pair else { throw VaultFailure.invalid("预览不存在、已失效或授权更改，请重新预览。") }
                guardedPair = pair
                try pair.validate(first:first,second:second)
                let readerA = reader(), readerB = reader()
                let a = try await readerA.capture(first), b = try await readerB.capture(second)
                guard try authorization() == pair else { throw VaultFailure.invalid("授权在读取期间已更改或撤销；结果不返回。") }
                let firstMap = try await core(["op":"vaultSnapshot","entries":a.entries]).1.text ?? ""
                let secondMap = try await core(["op":"vaultSnapshot","entries":b.entries]).1.text ?? ""
                let session = UUID().uuidString
                _ = try await core(["op":"compare","kind":"json","a":firstMap,"b":secondMap,"session":session])
                remember(session,pair:pair,sources:[VaultSourceSnapshot(a,side:"A"),VaultSourceSnapshot(b,side:"B")])
                output = try await report(session,includeValues:includesValues)
            default:
                let offset = arguments["offset"]?.intValue ?? 0
                let warningOffset = arguments["warningOffset"]?.intValue ?? 0
                let filter = try string("filter",fallback:"differences")
                guard arguments["offset"] == nil || arguments["offset"]?.intValue != nil, (0...100000).contains(offset), ["all","differences","SAME","VALUE_CHANGED","TYPE_CHANGED","ONLY_A","ONLY_B","NOT_COMPARABLE"].contains(filter) else { throw VaultFailure.invalid("分页参数无效。") }
                guard arguments["warningOffset"] == nil || arguments["warningOffset"]?.intValue != nil, (0...100000).contains(warningOffset) else { throw VaultFailure.invalid("源码警告分页参数无效。") }
                let session = try string("session")
                guardedPair = vaultSessions[session]
                output = try await report(session,includeValues:includesValues,offset:offset,filter:filter,warningOffset:warningOffset)
            }
            try Task.checkCancellation()
            if let guardedPair, try authorization() != guardedPair { throw VaultFailure.invalid("授权已更改或撤销，结果不返回。") }
            return .init(content:[.text(text:output,annotations:nil,_meta:nil)],isError:false)
        } catch is CancellationError { worker.abort(); return .init(content:[.text(text:"MCP_CANCELLED：操作已停止。",annotations:nil,_meta:nil)],isError:true) }
        catch let error as CoreError { return .init(content:[.text(text:error.code + "：" + error.message,annotations:nil,_meta:nil)],isError:true) }
        catch let error as VaultFailure { return .init(content:[.text(text:error.code + "：" + error.message,annotations:nil,_meta:nil)],isError:true) }
        catch { return .init(content:[.text(text:"MCP_FAILED：调用未完成，没有输出可比较结果。",annotations:nil,_meta:nil)],isError:true) }
    }
}

public enum MCPRunner {
    @MainActor public static func run(transport: any Transport = StdioTransport()) async -> Int32 {
        let service = MCPService()
        let server = Server(name:"config-compare",version:"0.2.0",instructions:"本机配置工具。Vault仅使用App主动授权的非生产来源。先vault_preview再vault_compare。默认不返回配置值；includeValues会把值交给调用客户端。",capabilities:.init(tools:.init(listChanged:false)),configuration:.strict)
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: await MCPService.tools) }
        await server.withMethodHandler(CallTool.self) { params in await service.call(name:params.name,arguments:params.arguments ?? [:]) }
        var status: Int32 = 0
        do { try await server.start(transport:transport); await server.waitUntilCompleted() }
        catch { status = 1 /* Protocol stdout remains JSON-RPC only; no input or credentials logged. */ }
        await server.stop()
        return status
    }
}
