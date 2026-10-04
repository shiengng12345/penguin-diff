import Foundation
import CompareShared
import CoreBridge
import Darwin

final class Worker: NSObject, CompareWorkerProtocol, NSXPCListenerDelegate {
    func run(_ request: String, withReply reply: @escaping @Sendable (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            reply(CoreBridge.process(request))
        }
    }
    func stop() { _exit(0) }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CompareWorkerProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }
}

@main
enum WorkerMain {
    static func main() {
        // The worker has no logging of input, values or Rust panic messages.
        freopen("/dev/null", "w", stdout)
        freopen("/dev/null", "w", stderr)
        let worker = Worker()
        let listener = NSXPCListener.service()
        listener.delegate = worker
        listener.resume()
        RunLoop.current.run()
    }
}
