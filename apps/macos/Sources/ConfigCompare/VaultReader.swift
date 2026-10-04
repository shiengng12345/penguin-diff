import Foundation
import CompareShared

struct VaultHTTPResponse: Sendable { let status: Int; let body: Data }
protocol VaultTransport: Sendable {
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse
}
// URLSession delegate callbacks and task cancellation can arrive on different
// executors. The registry and each response buffer are protected by this lock.
private final class VaultHTTPDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Pending {
        let continuation: CheckedContinuation<VaultHTTPResponse, any Error>
        var response: HTTPURLResponse?
        var body = Data()
    }
    private let lock = NSLock()
    private var pending: [Int:Pending] = [:]
    private let maxBytes = 20 * 1024 * 1024
    func register(_ task: URLSessionDataTask, continuation: CheckedContinuation<VaultHTTPResponse, any Error>) {
        lock.lock(); pending[task.taskIdentifier] = .init(continuation:continuation); lock.unlock()
    }
    private func finish(_ task: URLSessionTask, with result: Result<VaultHTTPResponse,any Error>) {
        lock.lock(); let item = pending.removeValue(forKey:task.taskIdentifier); lock.unlock()
        item?.continuation.resume(with:result)
    }
    private var tooLarge: VaultFailure { .init(code:"RESOURCE_LIMIT",message:"响应超过 20 MiB。") }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(dataTask,with:.failure(VaultFailure.invalid("响应不是 HTTP。")))
            completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= maxBytes else {
            finish(dataTask,with:.failure(tooLarge)); completionHandler(.cancel); return
        }
        lock.lock(); pending[dataTask.taskIdentifier]?.response = http; lock.unlock()
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let exceeds = (pending[dataTask.taskIdentifier]?.body.count ?? 0) + data.count > maxBytes
        if !exceeds { pending[dataTask.taskIdentifier]?.body.append(data) }
        lock.unlock()
        if exceeds { finish(dataTask,with:.failure(tooLarge)); dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock(); let item = pending.removeValue(forKey:task.taskIdentifier); lock.unlock()
        guard let item else { return }
        if let error { item.continuation.resume(throwing:error) }
        else if let http = item.response { item.continuation.resume(returning:.init(status:http.statusCode,body:item.body)) }
        else { item.continuation.resume(throwing:VaultFailure.invalid("响应不是 HTTP。")) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
// Handles cancellation before task registration as well as after it. Never
// resumes a continuation: the delegate removes/resumes each request exactly once.
private final class VaultTaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    func attach(_ task: URLSessionDataTask) {
        lock.lock(); self.task = task; let cancelled = cancelled; lock.unlock()
        if cancelled { task.cancel() }
    }
    func cancel() {
        lock.lock(); cancelled = true; let task = task; lock.unlock()
        task?.cancel()
    }
}
actor VaultHTTPTransport: VaultTransport {
    private let session: URLSession
    private let delegate: VaultHTTPDelegate
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        let delegate = VaultHTTPDelegate()
        self.delegate = delegate
        session = URLSession(configuration: config, delegate:delegate, delegateQueue:nil)
    }
    deinit { session.invalidateAndCancel() }
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        do {
            try Task.checkCancellation()
            let cancellation = VaultTaskCancellation()
            let result = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let task = session.dataTask(with:request)
                    delegate.register(task,continuation:continuation)
                    cancellation.attach(task)
                    task.resume()
                }
            } onCancel: { cancellation.cancel() }
            try Task.checkCancellation()
            return result
        } catch is CancellationError { throw CancellationError() }
        catch let failure as VaultFailure { throw failure }
        catch {
            // URLSession cancellation normally arrives as URLError.cancelled.
            // Preserve the task's cancellation semantics instead of reporting a network fault.
            try Task.checkCancellation()
            throw VaultFailure(code: "VAULT_NETWORK_FAILED", message: "网络、TLS 或超时错误；未绕过证书验证。")
        }
    }
}

protocol VaultReading: Sendable {
    func discoverConnection(_ settings: VaultSettings) async throws -> VaultCatalog
    func discoverContents(_ settings: VaultSettings) async throws -> VaultContents
    func preview(_ target: VaultTarget) async throws -> VaultPlan
    func capture(_ plan: VaultPlan) async throws -> VaultCaptured
}

extension VaultReading {
    func discoverConnection(_ settings: VaultSettings) async throws -> VaultCatalog { throw VaultFailure(code: "VAULT_DISCOVERY_UNAVAILABLE", message: "无法列举选项，请使用高级设置手动输入。") }
    func discoverContents(_ settings: VaultSettings) async throws -> VaultContents { throw VaultFailure(code: "VAULT_DISCOVERY_UNAVAILABLE", message: "无法列举选项，请使用高级设置手动输入。") }
}

actor VaultReader: VaultReading {
    typealias Validator = @Sendable (String, Int?, Int) async throws -> CoreResponse
    private let transport: any VaultTransport
    private let validate: Validator
    private var requests = 0
    private var bytes = 0
    init(transport: any VaultTransport = VaultHTTPTransport(), validate: @escaping Validator) {
        self.transport = transport; self.validate = validate
    }
    private func response(_ target: any VaultRequestSource, namespace: String, route: [String], list: Bool = false,
                          emptyList: Bool = false, kvVersion: Int? = nil) async throws -> (CoreResponse, [String:Any]) {
        try Task.checkCancellation()
        guard requests < 500 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "本次读取超过 500 个请求，范围未完成。") }
        guard !VaultPath.blockedProduction(namespace) else { throw VaultFailure.invalid("匹配范围出现生产 namespace，已停止。") }
        var url = URLComponents(string: target.origin)!
        url.path = "/v1/" + route.joined(separator: "/")
        if list { url.queryItems = [URLQueryItem(name: "list", value: "true")] }
        var request = URLRequest(url: url.url!)
        request.httpMethod = "GET"; request.timeoutInterval = 30
        request.setValue(target.token, forHTTPHeaderField: "X-Vault-Token")
        if !namespace.isEmpty { request.setValue(namespace + "/", forHTTPHeaderField: "X-Vault-Namespace") }
        request.setValue("true", forHTTPHeaderField: "X-Vault-Request")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        requests += 1
        let result = try await transport.send(request)
        try Task.checkCancellation()
        bytes += result.body.count
        guard bytes <= 20 * 1024 * 1024 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "本次来源响应总量超过 20 MiB。") }
        guard !((300...399).contains(result.status)) else { throw VaultFailure(code: "VAULT_REDIRECT_BLOCKED", message: "Vault 重定向已阻止；请填写最终的非生产服务地址。") }
        guard result.status == 200 || (result.status == 404 && (emptyList || kvVersion == 2)) else {
            throw VaultFailure(code: "VAULT_HTTP_\(result.status)", message: "\(list ? "列举" : "读取")未完成；403/404 不代表配置不存在。")
        }
        guard let raw = String(data: result.body, encoding: .utf8) else { throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "响应不是完整 UTF-8 JSON。") }
        let validated: CoreResponse
        do { validated = try await validate(raw, kvVersion, result.status) }
        catch {
            if let failure = error as? CoreError,
               ["VAULT_SECRET_DELETED", "VAULT_SECRET_DESTROYED"].contains(failure.code) {
                throw VaultFailure(code: failure.code, message: failure.message)
            }
            if result.status == 404, kvVersion == 2 {
                throw VaultFailure(code: "VAULT_HTTP_404", message: "范围无法确认；未将 404 当作缺失。")
            }
            throw error
        }
        if kvVersion != nil {
            if result.status == 404 {
                throw VaultFailure(code: "VAULT_HTTP_404", message: "范围无法确认；未将 404 当作缺失。")
            }
            return (validated,[:])
        }
        guard let canonical = validated.text,
              let json = try JSONSerialization.jsonObject(with: Data(canonical.utf8)) as? [String:Any] else { throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "响应不是 JSON 对象。") }
        if result.status == 404 {
            guard Set(json.keys) == ["errors"], let errors = json["errors"] as? [String], errors.isEmpty else { throw VaultFailure(code: "VAULT_HTTP_404", message: "范围无法确认；未将 404 当作缺失。") }
            return (validated, ["data":["keys":[String]()]])
        }
        return (validated,json)
    }
    private func keys(_ object: [String:Any]) throws -> [String] {
        guard let data = object["data"] as? [String:Any], let keys = data["keys"] as? [String],
              Set(keys).count == keys.count else { throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "列举结果没有可靠的 keys，或包含重复路径。") }
        for key in keys {
            let name = key.hasSuffix("/") ? String(key.dropLast()) : key
            let segments = try VaultPath.segments(name)
            guard segments.count == 1 else { throw VaultFailure.invalid("服务器列举结果不是相对单层路径。") }
        }
        return keys.sorted()
    }
    private func namespaceCandidates(_ target: any VaultRequestSource, patternText: String) async throws -> [(String,String)] {
        if patternText == "." { return [(target.namespace,".")] }
        let pattern = try VaultGlob(patternText)
        var queue = [(target.namespace, "", 0)]
        var result = [(String,String)]()
        var i = 0
        while i < queue.count {
            let (namespace, relative, depth) = queue[i]; i += 1
            guard depth <= 8, queue.count <= 100 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "namespace 超过 100 个或 8 层，范围未完成。") }
            if pattern.matches(relative) { result.append((namespace,relative.isEmpty ? "." : relative)) }
            if !pattern.canDescend(relative) { continue }
            let (_, json) = try await response(target, namespace: namespace, route: ["sys","namespaces"], list: true, emptyList: true)
            for key in try keys(json) {
                let name = String(key.hasSuffix("/") ? key.dropLast() : key[...])
                let child = VaultPath.join(namespace,name)
                guard !VaultPath.blockedProduction(child) else { throw VaultFailure.invalid("列举范围出现生产 namespace；请收窄非生产 namespace 根。") }
                let childRelative = VaultPath.join(relative,name)
                if pattern.matches(childRelative) || pattern.canDescend(childRelative) { queue.append((child,childRelative,depth + 1)) }
            }
        }
        return result
    }
    private func identify(_ target: any VaultRequestSource, namespace: String, mount: String) async throws -> Int {
        let (_, json) = try await response(target, namespace: namespace, route: ["sys","internal","ui","mounts"] + (try VaultPath.segments(mount)))
        guard let data = json["data"] as? [String:Any], data["type"] as? String == "kv",
              data["path"] as? String == mount + "/" else { throw VaultFailure(code: "VAULT_MOUNT_UNCONFIRMED", message: "所选 mount 未被服务器确认为 KV；不会尝试读取其他 engine。") }
        let options = data["options"] as? [String:Any]
        if let rawOptions = data["options"], !(rawOptions is NSNull), options == nil {
            throw VaultFailure(code: "VAULT_MOUNT_UNCONFIRMED", message: "KV 版本未确认。")
        }
        let version: String
        if let rawVersion = options?["version"] {
            guard let value = rawVersion as? String else { throw VaultFailure(code: "VAULT_MOUNT_UNCONFIRMED", message: "KV 版本未确认。") }
            version = value
        } else { version = "1" }
        guard version == "1" || version == "2" else { throw VaultFailure(code: "VAULT_MOUNT_UNCONFIRMED", message: "KV 版本未确认。") }
        return version == "2" ? 2 : 1
    }
    func discoverConnection(_ settings: VaultSettings) async throws -> VaultCatalog {
        let connection = try VaultConnection(settings)
        requests = 0; bytes = 0
        let (_, json) = try await response(connection, namespace: connection.namespace, route: ["sys", "internal", "ui", "mounts"])
        guard let data = json["data"] as? [String: Any], let secret = data["secret"] as? [String: Any], secret.count <= 1000 else {
            throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "未取得可靠的 KV mount 列表，请使用高级设置手动输入。")
        }
        var excluded = false
        var mounts = [String]()
        for (path, value) in secret {
            guard let mount = value as? [String: Any], let type = mount["type"] as? String else {
                throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "mount 列表格式无效。")
            }
            guard type == "kv" else { continue }
            guard path.hasSuffix("/") else { throw VaultFailure.invalid("mount 列表路径格式无效。") }
            let name = String(path.dropLast()); _ = try VaultPath.segments(name)
            if VaultPath.blockedProduction(name) { excluded = true; continue }
            mounts.append(name)
        }
        var namespaces = [connection.namespace]
        var unavailable = false
        do {
            let (_, object) = try await response(connection, namespace: connection.namespace, route: ["sys", "namespaces"], list: true, emptyList: true)
            let children = try keys(object)
            guard children.count <= 100 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "namespace 超过 100 个，范围未完成。") }
            for key in children {
                let child = VaultPath.join(connection.namespace, key.hasSuffix("/") ? String(key.dropLast()) : key)
                if VaultPath.blockedProduction(child) { excluded = true; continue }
                namespaces.append(child)
            }
        } catch let failure as VaultFailure where ["VAULT_HTTP_400", "VAULT_HTTP_403", "VAULT_HTTP_404", "VAULT_HTTP_405", "VAULT_HTTP_501"].contains(failure.code) {
            // A deployment may not support namespaces, or the token may only
            // access its current namespace. Never guess that permission changed.
            unavailable = true
        }
        return .init(namespaces: namespaces.sorted(), mounts: mounts.sorted(), namespaceListingUnavailable: unavailable, excludedProduction: excluded)
    }
    func discoverContents(_ settings: VaultSettings) async throws -> VaultContents {
        let connection = try VaultConnection(settings)
        _ = try VaultPath.segments(settings.mount)
        _ = try VaultPath.segments(settings.directory, empty: true)
        if settings.namespacePattern != "." { _ = try VaultGlob(settings.namespacePattern) }
        if settings.directoryPattern != "." { _ = try VaultGlob(settings.directoryPattern) }
        guard !VaultPath.blockedProduction(settings.mount), !VaultPath.blockedProduction(settings.directory), !VaultPath.blockedProduction(settings.directoryPattern) else {
            throw VaultFailure.invalid("生产标识被阻止；仅允许非生产来源。")
        }
        requests = 0; bytes = 0
        let namespaces = try await namespaceCandidates(connection, patternText: settings.namespacePattern)
        guard !namespaces.isEmpty else { throw VaultFailure(code: "VAULT_NO_MATCH", message: "namespace 模式没有匹配；未读取 secret。") }
        let recursive = settings.directoryPattern.contains("*") || settings.directoryPattern.contains("?")
        // A literal `.` is the mount-root directory, not an all-directories
        // scan. Keep its matcher absent so the catalog metadata and traversal
        // scope cannot be mistaken for a proven `**` intersection.
        let pattern = settings.directoryPattern == "." ? nil : try VaultGlob(settings.directoryPattern)
        let literal = settings.directoryPattern == "." ? "" : settings.directoryPattern
        var paths = Set<VaultConfigurationPath>()
        var discoveredDirectories = Set<String>()
        var excluded = false
        var totalDirectories = 0
        for (namespace, _) in namespaces {
            let version = try await identify(connection, namespace: namespace, mount: settings.mount)
            var queue = [(recursive ? "" : literal, 0)]
            var index = 0
            while index < queue.count {
                let (relative, depth) = queue[index]; index += 1; totalDirectories += 1
                guard depth <= 16, totalDirectories <= 1000, queue.count <= 1000 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "目录超过 1000 个或 16 层，范围未完成。") }
                discoveredDirectories.insert(relative.isEmpty ? "." : relative)
                let directory = VaultPath.join(settings.directory, relative)
                let route = try VaultPath.segments(settings.mount) + (version == 2 ? ["metadata"] : []) + VaultPath.segments(directory, empty: true)
                let (_, json) = try await response(connection, namespace: namespace, route: route, list: true, emptyList: true)
                for key in try keys(json) {
                    let name = key.hasSuffix("/") ? String(key.dropLast()) : key
                    if VaultPath.blockedProduction(name) { excluded = true; continue }
                    if key.hasSuffix("/") {
                        let child = VaultPath.join(relative, name)
                        if recursive && (pattern?.matches(child) == true || pattern?.canDescend(child) == true) { queue.append((child, depth + 1)) }
                    } else if !recursive || pattern?.matches(relative) == true {
                        paths.insert(.init(name: key, directory: relative.isEmpty ? "." : relative))
                        guard paths.count <= 1000 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "匹配 secret 超过 1000 个。") }
                    }
                }
            }
        }
        return .init(paths: paths, discoveredDirectories: discoveredDirectories, discoveryDirectoryPattern: settings.directoryPattern, excludedProduction: excluded)
    }
    func preview(_ target: VaultTarget) async throws -> VaultPlan {
        requests = 0; bytes = 0
        let namespaces = try await namespaceCandidates(target, patternText: target.namespacePattern)
        guard !namespaces.isEmpty else { throw VaultFailure(code: "VAULT_NO_MATCH", message: "namespace 模式没有匹配；未读取 secret。") }
        let pattern = try VaultGlob(target.directoryPattern == "." ? "**" : target.directoryPattern)
        var selected = [VaultSecret]()
        for (namespace, namespaceKey) in namespaces {
            let version = try await identify(target, namespace: namespace, mount: target.mount)
            // A literal directory does not require LIST permissions: the user has chosen one exact secret.
            if !target.directoryPattern.contains("*"), !target.directoryPattern.contains("?") {
                let directory = target.directoryPattern == "." ? target.directory : VaultPath.join(target.directory,target.directoryPattern)
                selected.append(.init(namespace: namespace, namespaceKey: namespaceKey, path: VaultPath.join(directory,target.environment), directoryKey: target.directoryPattern, kvVersion: version))
                continue
            }
            var queue = [("",0)]
            var i = 0
            while i < queue.count {
                let (relative,depth) = queue[i]; i += 1
                guard depth <= 16, queue.count <= 1000 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "目录超过 1000 个或 16 层，范围未完成。") }
                let directory = VaultPath.join(target.directory,relative)
                let route = try VaultPath.segments(target.mount) + (version == 2 ? ["metadata"] : []) + VaultPath.segments(directory, empty: true)
                let (_, json) = try await response(target, namespace: namespace, route: route, list: true, emptyList: true)
                for key in try keys(json) {
                    if key.hasSuffix("/") {
                        if VaultPath.blockedProduction(key) { continue }
                        let child = VaultPath.join(relative,String(key.dropLast()))
                        if pattern.matches(child) || pattern.canDescend(child) { queue.append((child,depth + 1)) }
                    } else if key == target.environment, pattern.matches(relative) {
                        selected.append(.init(namespace: namespace, namespaceKey: namespaceKey, path: VaultPath.join(directory,key), directoryKey: relative.isEmpty ? "." : relative, kvVersion: version))
                    }
                }
                guard selected.count <= 1000 else { throw VaultFailure(code: "RESOURCE_LIMIT", message: "匹配 secret 超过 1000 个。") }
            }
        }
        guard !selected.isEmpty else { throw VaultFailure(code: "VAULT_NO_MATCH", message: "没有匹配的配置名称；请修改两侧各自的名称或目录模式。") }
        return .init(target: target, secrets: selected, discoveredNamespaces: namespaces.map(\.0), created: Date())
    }
    func capture(_ plan: VaultPlan) async throws -> VaultCaptured {
        guard Date().timeIntervalSince(plan.created) <= 300 else { throw VaultFailure(code: "VAULT_PLAN_EXPIRED", message: "范围预览已超过 5 分钟，请重新预览。") }
        for secret in plan.secrets {
            _ = try VaultPath.segments(secret.path)
            _ = try VaultPath.segments(secret.namespace, empty: true)
            guard !VaultPath.blockedProduction(secret.path), !VaultPath.blockedProduction(secret.namespace) else {
                    throw VaultFailure.invalid("生产标识被阻止；仅允许非生产来源。")
            }
        }
        requests = 0; bytes = 0
        let started = Date()
        var entries = [[String:String]]()
        var observations = [VaultObservation]()
        var checked = [String:Int]()
        for secret in plan.secrets {
            try Task.checkCancellation()
            if checked[secret.namespace] == nil { checked[secret.namespace] = try await identify(plan.target, namespace: secret.namespace, mount: plan.target.mount) }
            guard checked[secret.namespace] == secret.kvVersion else { throw VaultFailure(code: "VAULT_SOURCE_CHANGED", message: "KV 版本已改变，请重新预览。") }
            let route = try VaultPath.segments(plan.target.mount) + (secret.kvVersion == 2 ? ["data"] : []) + VaultPath.segments(secret.path)
            let readStarted = Date()
            let (validated,_) = try await response(plan.target, namespace: secret.namespace, route: route, kvVersion: secret.kvVersion)
            let readFinished = Date()
            guard let metadata = validated.vaultMetadata, metadata.kvVersion == secret.kvVersion else {
                throw VaultFailure(code: "VAULT_METADATA_INVALID", message: "Vault 版本来源格式无效；没有输出可比较结果。")
            }
            if metadata.state == "deleted" || metadata.state == "destroyed" {
                throw VaultFailure(code: metadata.state == "deleted" ? "VAULT_SECRET_DELETED" : "VAULT_SECRET_DESTROYED", message: "读取版本已删除或销毁；整批停止，不生成缺失或相同结论。")
            }
            guard metadata.state == "readable", let text = validated.text else {
                throw VaultFailure(code: "VAULT_RESPONSE_INVALID", message: "响应没有可比较配置。")
            }
            entries.append(["namespace":secret.namespaceKey,"path":secret.directoryKey,"response":text,"format":"plain-object"])
            observations.append(.init(secret: secret, started: readStarted.ISO8601Format(), finished: readFinished.ISO8601Format(), metadata: metadata))
        }
        return .init(plan: plan, entries: entries, started: started, finished: Date(), observations: observations)
    }
}
