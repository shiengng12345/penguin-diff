import Foundation
import CompareShared

enum WorkerFailure: LocalizedError, Sendable {
    case interrupted, timedOut, invalidRequest
    var errorDescription: String? {
        switch self {
        case .interrupted: "本地计算服务已中断，请重新运行。"
        case .timedOut: "本地计算超过 30 秒，已停止；请缩小输入后重试。"
        case .invalidRequest: "本地请求无效。"
        }
    }
}

// NSXPC callbacks may race a timeout. Every continuation is resumed exactly once.
private final class PendingReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, any Error>?
    init(_ continuation: CheckedContinuation<String, any Error>) { self.continuation = continuation }
    @discardableResult func finish(_ result: Result<String, any Error>) -> Bool {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
        return pending != nil
    }
}

@MainActor
protocol WorkerSending: Sendable {
    func send(_ request: String) async throws -> String
    func abort()
}

@MainActor
final class WorkerClient: WorkerSending {
    private let connectionFactory: @MainActor () -> NSXPCConnection
    private var connection: NSXPCConnection?
    private var connectionID: UUID?
    private var pending: [UUID: PendingReply] = [:]
    // Older task cancellation finishes its own reply; stopping the latest task
    // stops the shared worker and therefore cancels every attached request.
    private var requestID = UUID()
    init(connectionFactory: @escaping @MainActor () -> NSXPCConnection = {
        NSXPCConnection(serviceName: "com.penguin.configcompare.worker")
    }) { self.connectionFactory = connectionFactory }
    func abort() {
        let oldConnection = connection
        let replies = Array(pending.values)
        connection = nil
        connectionID = nil
        pending.removeAll()
        for reply in replies { reply.finish(.failure(CancellationError())) }
        if let proxy = oldConnection?.remoteObjectProxy as? CompareWorkerProtocol { proxy.stop() }
        oldConnection?.invalidate()
    }
    private func interrupted(_ id: UUID) {
        guard connectionID == id else { return }
        let oldConnection = connection
        let replies = Array(pending.values)
        connection = nil
        connectionID = nil
        pending.removeAll()
        for reply in replies { reply.finish(.failure(WorkerFailure.interrupted)) }
        oldConnection?.invalidate()
    }
    func send(_ request: String) async throws -> String {
        try Task.checkCancellation()
        let id = UUID(); requestID = id
        if connection == nil {
            let connection = connectionFactory()
            connection.remoteObjectInterface = NSXPCInterface(with: CompareWorkerProtocol.self)
            connection.resume()
            self.connection = connection
            connectionID = UUID()
        }
        guard let connection, let connectionID else { throw WorkerFailure.interrupted }
        var deadline: Task<Void, Never>?
        defer { deadline?.cancel(); pending.removeValue(forKey: id) }
        return try await withTaskCancellationHandler {
          try await withCheckedThrowingContinuation { continuation in
            let pending = PendingReply(continuation)
            self.pending[id] = pending
            // Foundation invokes error handlers on its private queue. Only the
            // Sendable identity crosses queues; connection state stays on MainActor.
            let proxy = connection.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.interrupted(connectionID)
                    pending.finish(.failure(WorkerFailure.interrupted))
                }
            } as? CompareWorkerProtocol
            guard let proxy else { interrupted(connectionID); return }
            proxy.run(request) { output in pending.finish(.success(output)) }
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                if pending.finish(.failure(WorkerFailure.timedOut)),
                   self?.connectionID == connectionID { self?.abort() }
            }
          }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, let reply = self.pending[id],
                      reply.finish(.failure(CancellationError())) else { return }
                self.pending.removeValue(forKey: id)
                if self.requestID == id { self.abort() }
            }
        }
    }
}
