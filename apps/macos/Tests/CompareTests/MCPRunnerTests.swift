import Foundation
import Testing
import MCP
import Logging
@testable import CompareUI

private actor FailedStartupTransport: Transport {
    let logger = Logger(label: "synthetic-failed-transport", factory: { _ in SwiftLogNoOpLogHandler() })
    private(set) var disconnects = 0
    func connect() async throws { throw CocoaError(.fileReadUnknown) }
    func disconnect() async { disconnects += 1 }
    func send(_ data: Data) async throws { throw CocoaError(.fileReadUnknown) }
    func receive() -> AsyncThrowingStream<Data, any Error> { .init { $0.finish() } }
}

@Test @MainActor func mcpStartupFailureReturnsNonzero() async {
    let transport = FailedStartupTransport()
    #expect(await MCPRunner.run(transport: transport) == 1)
    #expect(await transport.disconnects >= 1)
}
