import Foundation
import Testing
import CompareShared
import CoreBridge
@testable import CompareUI

private final class IPCPeer: NSObject, CompareWorkerProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: @Sendable (String) -> Void] = [:]
    private var links: [NSXPCConnection] = []
    private var received = 0
    var heldCount: Int { lock.withLock { replies.count } }
    var receivedCount: Int { lock.withLock { received } }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CompareWorkerProtocol.self)
        connection.exportedObject = self
        lock.withLock { links.append(connection) }
        connection.resume()
        return true
    }
    func run(_ request: String, withReply reply: @escaping @Sendable (String) -> Void) {
        lock.withLock { received += 1 }
        if request.contains("# held-") { lock.withLock { replies[request] = reply } }
        else { reply(CoreBridge.process(request)) }
    }
    func release(_ request: String) {
        let callback = lock.withLock { replies.removeValue(forKey: request) }
        callback?(CoreBridge.process(request))
    }
    func releaseAll() {
        let saved = lock.withLock { let saved = replies; replies.removeAll(); return saved }
        for (request, reply) in saved { reply(CoreBridge.process(request)) }
    }
    func stop() { invalidateLinks() }
    func invalidateLinks() {
        let saved = lock.withLock { let saved = links; links.removeAll(); return saved }
        for link in saved { link.invalidate() }
    }
}

@MainActor private final class IPCFixture {
    let peer = IPCPeer()
    let listener = NSXPCListener.anonymous()
    private(set) var createdConnections = 0
    init() { listener.delegate = peer; listener.resume() }
    func connection() -> NSXPCConnection {
        createdConnections += 1
        return NSXPCConnection(listenerEndpoint: listener.endpoint)
    }
    func close() { peer.releaseAll(); peer.invalidateLinks(); listener.invalidate() }
}

@MainActor private final class IPCOutcome {
    var value: Result<String, any Error>?
    func start(_ client: WorkerClient, _ request: String) -> Task<Void, Never> {
        Task {
            do { value = .success(try await client.send(request)) }
            catch { value = .failure(error) }
        }
    }
    var wasCancelled: Bool {
        if case .failure(let error) = value { return error is CancellationError }
        return false
    }
    func response() throws -> CoreResponse {
        try CoreResponse.decode(try #require(value).get())
    }
}

private func ipcRequest(_ source: String) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: ["op": "formatYaml", "source": source]), as: UTF8.self)
}

@MainActor private func ipcWait(timeout: Duration = .seconds(3), _ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(predicate(), "Actual NSXPC request did not reach its expected state")
}

@Suite(.serialized) struct IPCLifecycleTests {
    @Test @MainActor func actualNSXPCAndCoreFFIRoundtripKeepsTheConnectionReusable() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        defer { client.abort(); fixture.close() }
        for (source, expected) in [("x:  1\n", "x: 1\n"), ("x:  2\n", "x: 2\n")] {
            let result = try CoreResponse.decode(try await client.send(ipcRequest(source)))
            #expect(result.text == expected)
        }
        #expect(fixture.createdConnections == 1 && fixture.peer.receivedCount == 2)
    }

    @Test @MainActor func fileBomCrLfAndChineseWarningSurviveXPCIntoWorkspaceRows() async throws {
        let fixture = IPCFixture()
        let model = Workspace(clientFactory: { WorkerClient(connectionFactory: { fixture.connection() }) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            model.cancel()
            fixture.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let aURL = directory.appendingPathComponent("a-中文.js")
        let bURL = directory.appendingPathComponent("b-中文.js")
        let aSource = "\u{FEFF}var env={\r\n  中文:1,\r\n  中文:2\r\n};\r\n"
        let bSource = "var env={\r\n  中文:2\r\n};\r\n"
        try Data(aSource.utf8).write(to: aURL)
        try Data(bSource.utf8).write(to: bURL)
        model.importFile(aURL, side: true)
        model.importFile(bURL, side: false)
        try await ipcWait(timeout: .seconds(3)) {
            model.fileA == aURL && model.fileB == bURL && !model.importing
        }
        #expect(model.a == aSource && model.b == bSource)
        model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary != nil }
        #expect(model.warningCount == 1)
        let warning = try #require(model.warnings.first)
        #expect(warning.side == "A" && warning.line == 3 && warning.column == 3)
        #expect(warning.previousLine == 2 && warning.previousColumn == 3)
        #expect(model.summary?.same == 1 && model.complete)
        model.filter = "all"
        model.loadRows(reset: true)
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.matched == 1 }
        let row = try #require(model.rows.first)
        #expect(model.inputLabel(side: true) == "A · a-中文.js" && model.inputLabel(side: false) == "B · b-中文.js")
        #expect(model.resultName(row.path) == #"env["中文"]"#)
        #expect(row.status == "SAME")
        #expect(row.a.line == 3 && row.a.column == 10 && row.b.line == 2 && row.b.column == 10)
        model.selected = row.id
        model.inspectSelection()
        try await ipcWait(timeout: .seconds(3)) { model.detail != nil }
        #expect(model.detail?.a.line == 3 && model.detail?.a.column == 10)
        #expect(model.detail?.b.line == 2 && model.detail?.b.column == 10)

        let malformedURL = directory.appendingPathComponent("malformed-中文.js")
        let malformed = "\u{FEFF}var env={\r\n  中文:1,\r\n  @\r\n};\r\n"
        try Data(malformed.utf8).write(to: malformedURL)
        model.importFile(malformedURL, side: true)
        try await ipcWait(timeout: .seconds(3)) { model.fileA == malformedURL && !model.importing }
        model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.error }
        #expect(model.a == malformed && model.summary == nil && model.notice.contains("JS_PARSE_ERROR"))
    }

    @Test @MainActor func fileLfWithoutBomAndChineseWarningKeepsByteColumnsOverXPC() async throws {
        let fixture = IPCFixture()
        let model = Workspace(clientFactory: { WorkerClient(connectionFactory: { fixture.connection() }) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            model.cancel()
            fixture.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let aURL = directory.appendingPathComponent("lf-a.js")
        let bURL = directory.appendingPathComponent("lf-b.js")
        let aSource = "var env={\n  中文:1,\n  中文:2\n};\n"
        let bSource = "var env={\n  中文:2\n};\n"
        try Data(aSource.utf8).write(to: aURL)
        try Data(bSource.utf8).write(to: bURL)
        model.importFile(aURL, side: true)
        model.importFile(bURL, side: false)
        try await ipcWait(timeout: .seconds(3)) { model.fileA == aURL && model.fileB == bURL && !model.importing }
        #expect(model.a == aSource && model.b == bSource && !model.a.hasPrefix("\u{FEFF}"))
        model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary != nil }
        let warning = try #require(model.warnings.first)
        #expect(warning.line == 3 && warning.column == 3 && warning.previousLine == 2 && warning.previousColumn == 3)
        model.filter = "all"
        model.loadRows(reset: true)
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.matched == 1 }
        let row = try #require(model.rows.first)
        #expect(row.a.line == 3 && row.a.column == 10 && row.b.line == 2 && row.b.column == 10)
    }

    @Test @MainActor func bomBeforeFirstLineCodePreservesUtf8ByteOffsetOverXPC() async throws {
        let fixture = IPCFixture()
        let model = Workspace(clientFactory: { WorkerClient(connectionFactory: { fixture.connection() }) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            model.cancel()
            fixture.close()
            try? FileManager.default.removeItem(at: directory)
        }
        let aURL = directory.appendingPathComponent("bom-first-a.js")
        let bURL = directory.appendingPathComponent("bom-first-b.js")
        let aSource = "\u{FEFF}var env={中文:1,中文:2};\r\n"
        let bSource = "var env={中文:2};\r\n"
        try Data(aSource.utf8).write(to: aURL)
        try Data(bSource.utf8).write(to: bURL)
        model.importFile(aURL, side: true)
        model.importFile(bURL, side: false)
        try await ipcWait(timeout: .seconds(3)) { model.fileA == aURL && model.fileB == bURL && !model.importing }
        model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary != nil }
        let warning = try #require(model.warnings.first)
        #expect(warning.line == 1 && warning.column == 22 && warning.previousLine == 1 && warning.previousColumn == 13)
        model.filter = "all"
        model.loadRows(reset: true)
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.matched == 1 }
        let row = try #require(model.rows.first)
        #expect(row.a.line == 1 && row.a.column == 29 && row.b.line == 1 && row.b.column == 17)
    }

    @Test @MainActor func bomAndLineEndingMatrixKeepsChineseWarningsAndDetailsOverXPC() async throws {
        for (bom, newline) in [(false, "\n"), (false, "\r\n"), (true, "\n"), (true, "\r\n")] {
            let fixture = IPCFixture()
            let model = Workspace(clientFactory: { WorkerClient(connectionFactory: { fixture.connection() }) })
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer {
                model.cancel()
                fixture.close()
                try? FileManager.default.removeItem(at: directory)
            }
            let aURL = directory.appendingPathComponent("matrix-a.js")
            let bURL = directory.appendingPathComponent("matrix-b.js")
            let marker = bom ? "\u{FEFF}" : ""
            let aSource = "\(marker)var env={\(newline)  中文:1,\(newline)  中文:2\(newline)};\(newline)"
            let bSource = "var env={\(newline)  中文:2\(newline)};\(newline)"
            try Data(aSource.utf8).write(to: aURL)
            try Data(bSource.utf8).write(to: bURL)
            model.importFile(aURL, side: true)
            model.importFile(bURL, side: false)
            try await ipcWait(timeout: .seconds(3)) { model.fileA == aURL && model.fileB == bURL && !model.importing }
            #expect(model.a == aSource && model.b == bSource)
            model.run()
            try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary != nil }
            #expect(model.warningCount == 1 && model.summary?.same == 1 && model.complete)
            let warning = try #require(model.warnings.first)
            #expect(warning.line == 3 && warning.column == 3 && warning.previousLine == 2 && warning.previousColumn == 3)
            model.filter = "all"
            model.loadRows(reset: true)
            try await ipcWait(timeout: .seconds(3)) { !model.busy && model.matched == 1 }
            let row = try #require(model.rows.first)
            #expect(row.a.line == 3 && row.a.column == 10 && row.b.line == 2 && row.b.column == 10)
            model.selected = row.id
            model.inspectSelection()
            try await ipcWait(timeout: .seconds(3)) { model.detail?.id == row.id }
            #expect(model.detail?.a.line == 3 && model.detail?.a.column == 10 && model.detail?.b.line == 2 && model.detail?.b.column == 10)
        }
    }

    @Test @MainActor func missingNullUndefinedAndEmptyValuesSurviveXPCIntoWorkspaceRowsAndDetails() async throws {
        let fixture = IPCFixture()
        let model = Workspace(clientFactory: { WorkerClient(connectionFactory: { fixture.connection() }) })
        defer {
            model.cancel()
            fixture.close()
        }
        model.a = "var env={nullValue:null,emptyValue:'',undefinedValue:undefined,undefinedOnly:undefined,onlyA:1};"
        model.b = "var env={nullValue:null,emptyValue:'',undefinedValue:undefined,onlyB:2};"
        model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary?.total == 6 && model.matched == 3 }
        #expect(model.summary?.same == 3 && model.summary?.onlyA == 2 && model.summary?.onlyB == 1 && model.complete)
        model.filter = "all"
        model.loadRows(reset: true)
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.matched == 6 }
        let byName = Dictionary(uniqueKeysWithValues: model.rows.map { (model.resultName($0.path), $0) })
        let nullRow = try #require(byName["env.nullValue"])
        let emptyRow = try #require(byName["env.emptyValue"])
        let undefinedRow = try #require(byName["env.undefinedValue"])
        let undefinedOnlyRow = try #require(byName["env.undefinedOnly"])
        let onlyARow = try #require(byName["env.onlyA"])
        let onlyBRow = try #require(byName["env.onlyB"])
        #expect(nullRow.a.type == "Null" && nullRow.b.type == "Null" && nullRow.a.display == "null" && nullRow.b.display == "null")
        #expect(emptyRow.a.type == "String" && emptyRow.b.type == "String" && emptyRow.a.display == "\"\"" && emptyRow.b.display == "\"\"")
        #expect(undefinedRow.a.type == "Undefined" && undefinedRow.b.type == "Undefined" && undefinedRow.a.display == "undefined" && undefinedRow.b.display == "undefined")
        #expect(undefinedOnlyRow.a.type == "Undefined" && undefinedOnlyRow.a.present && undefinedOnlyRow.b.type == "Missing" && undefinedOnlyRow.b.display == "<不存在>" && !undefinedOnlyRow.b.present)
        #expect(onlyARow.a.present && onlyARow.a.type != "Missing" && onlyARow.b.type == "Missing" && onlyARow.b.display == "<不存在>" && !onlyARow.b.present)
        #expect(onlyBRow.a.type == "Missing" && onlyBRow.a.display == "<不存在>" && !onlyBRow.a.present && onlyBRow.b.present && onlyBRow.b.type != "Missing")
        for selected in [nullRow, emptyRow, undefinedRow, undefinedOnlyRow, onlyARow, onlyBRow] {
            model.selected = selected.id
            model.inspectSelection()
            try await ipcWait(timeout: .seconds(3)) { model.detail?.id == selected.id }
            #expect(model.detail?.id == selected.id)
            #expect(model.detail?.a.type == selected.a.type && model.detail?.a.present == selected.a.present && model.detail?.a.display == selected.a.display)
            #expect(model.detail?.b.type == selected.b.type && model.detail?.b.present == selected.b.present && model.detail?.b.display == selected.b.display)
        }

        model.a = "var env={stringValue:'value',nullValue:null,undefinedValue:undefined};"
        model.b = "var env={stringValue:null,nullValue:undefined,undefinedValue:''};"
        model.changed(); model.run()
        try await ipcWait(timeout: .seconds(3)) { !model.busy && model.summary?.total == 3 && model.matched == 3 }
        #expect(model.summary?.typeChanged == 3 && model.summary?.differences == 3)
        for row in model.rows {
            switch row.path {
            case "$.env.stringValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "String" && row.b.type == "Null")
            case "$.env.nullValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "Null" && row.b.type == "Undefined")
            case "$.env.undefinedValue":
                #expect(row.status == "TYPE_CHANGED" && row.a.type == "Undefined" && row.b.type == "String")
            default:
                Issue.record("Unexpected XPC cross-type row: \(row.path)")
            }
            model.selected = row.id
            model.inspectSelection()
            try await ipcWait(timeout: .seconds(3)) { model.detail?.id == row.id }
            #expect(model.detail?.a.type == row.a.type && model.detail?.a.present == row.a.present && model.detail?.a.display == row.a.display)
            #expect(model.detail?.b.type == row.b.type && model.detail?.b.present == row.b.present && model.detail?.b.display == row.b.display)
        }
    }

    @Test @MainActor func cancelBeforeStartingDoesNotCreateAnXPCConnection() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        defer { client.abort(); fixture.close() }
        let outcome = IPCOutcome(), request = try ipcRequest("# held-before\nx:  1\n")
        let task = outcome.start(client, request); task.cancel()
        try await ipcWait { outcome.value != nil }
        #expect(outcome.wasCancelled && fixture.createdConnections == 0 && fixture.peer.receivedCount == 0)
    }

    @Test @MainActor func attachedCancellationRejectsLateReplyAndReconnects() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let outcome = IPCOutcome(), request = try ipcRequest("# held-attached\nx:  1\n")
        let task = outcome.start(client, request)
        defer { task.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 1 }
        task.cancel(); try await ipcWait { outcome.value != nil }
        #expect(outcome.wasCancelled)
        fixture.peer.release(request)
        let result = try CoreResponse.decode(try await client.send(ipcRequest("x:  2\n")))
        #expect(result.text == "x: 2\n" && outcome.wasCancelled && fixture.createdConnections == 2)
    }

    @Test @MainActor func cancellingAnOlderRequestCompletesItWithoutAbortingANewerRequest() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome()
        let a = try ipcRequest("# held-a\nx:  1\n"), b = try ipcRequest("# held-b\nx:  2\n")
        let taskA = first.start(client, a)
        defer { taskA.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 1 }
        let taskB = second.start(client, b)
        defer { taskB.cancel() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        taskA.cancel(); try await ipcWait { first.value != nil }
        #expect(first.wasCancelled && second.value == nil)
        fixture.peer.release(a); fixture.peer.release(b)
        try await ipcWait { second.value != nil }
        #expect(try second.response().text == "# held-b\nx: 2\n" && first.wasCancelled && fixture.createdConnections == 1)
    }

    @Test @MainActor func abortCancelsEveryAttachedRequestBeforeRetrying() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome()
        let taskA = first.start(client, try ipcRequest("# held-abort-a\nx:  1\n"))
        let taskB = second.start(client, try ipcRequest("# held-abort-b\nx:  2\n"))
        defer { taskA.cancel(); taskB.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        client.abort(); try await ipcWait { first.value != nil && second.value != nil }
        #expect(first.wasCancelled && second.wasCancelled)
        let result = try CoreResponse.decode(try await client.send(ipcRequest("x:  3\n")))
        #expect(result.text == "x: 3\n" && fixture.createdConnections == 2)
    }

    @Test @MainActor func serviceInvalidationCompletesEveryRequestAndFirstRetryReconnects() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome()
        let taskA = first.start(client, try ipcRequest("# held-interrupt-a\nx:  1\n"))
        let taskB = second.start(client, try ipcRequest("# held-interrupt-b\nx:  2\n"))
        defer { taskA.cancel(); taskB.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        fixture.peer.invalidateLinks()
        try await ipcWait { first.value != nil && second.value != nil }
        for outcome in [first, second] {
            guard case .failure(let error) = outcome.value else { Issue.record("Interrupted request unexpectedly succeeded"); continue }
            #expect(error as? WorkerFailure == .interrupted)
        }
        let result = try CoreResponse.decode(try await client.send(ipcRequest("x:  4\n")))
        #expect(result.text == "x: 4\n" && fixture.createdConnections == 2)
    }

    @Test @MainActor func outOfOrderRepliesRemainPairedAndCompletedCancellationCannotStopANewRequest() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome(), third = IPCOutcome()
        let a = try ipcRequest("# held-order-a\nx:  1\n"), b = try ipcRequest("# held-order-b\nx:  2\n")
        let c = try ipcRequest("# held-order-c\nx:  3\n")
        let taskA = first.start(client, a), taskB = second.start(client, b)
        defer { taskA.cancel(); taskB.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        fixture.peer.release(b); try await ipcWait { second.value != nil }
        #expect(try second.response().text == "# held-order-b\nx: 2\n" && first.value == nil)
        fixture.peer.release(a); try await ipcWait { first.value != nil }
        #expect(try first.response().text == "# held-order-a\nx: 1\n")
        let taskC = third.start(client, c)
        defer { taskC.cancel() }
        try await ipcWait { fixture.peer.heldCount == 1 }
        taskB.cancel(); taskA.cancel()
        fixture.peer.release(c); try await ipcWait { third.value != nil }
        #expect(try third.response().text == "# held-order-c\nx: 3\n" && fixture.createdConnections == 1)
    }

    @Test @MainActor func cancellingTheLatestRequestStopsAllAttachedRequestsAndRetryReconnects() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome()
        let taskA = first.start(client, try ipcRequest("# held-latest-a\nx:  1\n"))
        defer { taskA.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 1 }
        let taskB = second.start(client, try ipcRequest("# held-latest-b\nx:  2\n"))
        defer { taskB.cancel() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        taskB.cancel(); try await ipcWait { first.value != nil && second.value != nil }
        #expect(first.wasCancelled && second.wasCancelled)
        let result = try CoreResponse.decode(try await client.send(ipcRequest("x:  5\n")))
        #expect(result.text == "x: 5\n" && fixture.createdConnections == 2)
    }

    @Test @MainActor func actualDefaultThirtySecondDeadlineStopsSiblingRejectsLateReplyAndReconnects() async throws {
        let fixture = IPCFixture(), client = WorkerClient(connectionFactory: { fixture.connection() })
        let first = IPCOutcome(), second = IPCOutcome(), retry = IPCOutcome()
        let a = try ipcRequest("# held-timeout-a\nx:  1\n"), b = try ipcRequest("# held-timeout-b\nx:  2\n")
        let c = try ipcRequest("# held-timeout-retry\nx:  3\n")
        let began = ContinuousClock.now
        let taskA = first.start(client, a)
        defer { taskA.cancel(); client.abort(); fixture.close() }
        try await ipcWait { fixture.peer.heldCount == 1 }
        try await Task.sleep(for: .seconds(1))
        let taskB = second.start(client, b)
        defer { taskB.cancel() }
        try await ipcWait { fixture.peer.heldCount == 2 }
        try await ipcWait(timeout: .seconds(35)) { first.value != nil && second.value != nil }
        let elapsed = began.duration(to: .now)
        #expect(elapsed >= .seconds(29.5) && elapsed < .seconds(36))
        guard case .failure(let error) = first.value else { Issue.record("Timed out request unexpectedly succeeded"); return }
        #expect(error as? WorkerFailure == .timedOut && second.wasCancelled)
        let taskC = retry.start(client, c)
        defer { taskC.cancel() }
        try await ipcWait { fixture.peer.heldCount == 3 }
        fixture.peer.release(a); fixture.peer.release(b)
        #expect(retry.value == nil)
        fixture.peer.release(c); try await ipcWait { retry.value != nil }
        #expect(try retry.response().text == "# held-timeout-retry\nx: 3\n" && fixture.createdConnections == 2)
        guard case .failure(let finalError) = first.value else { Issue.record("Late reply replaced timeout"); return }
        #expect(finalError as? WorkerFailure == .timedOut)
    }
}
