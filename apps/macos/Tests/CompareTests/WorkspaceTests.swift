import Foundation
import Testing
@testable import CompareUI

@MainActor
private final class ControlledWorker: WorkerSending {
    var requests: [CheckedContinuation<String, any Error>] = []
    var abortCount = 0
    func send(_ request: String) async throws -> String {
        let json = try JSONSerialization.jsonObject(with: Data(request.utf8)) as! [String: Any]
        if json["op"] as? String == "inspectJs" { return #"{"ok":true,"roots":["env","module.exports"],"complete":true}"# }
        if json["op"] as? String == "rows" { return #"{"ok":true,"rows":[],"matched":0}"# }
        return try await withCheckedThrowingContinuation { requests.append($0) }
    }
    func abort() { abortCount += 1 }
    func reply(index: Int, count: Int) {
        let response = "{\"ok\":true,\"session\":\"test\",\"complete\":true,\"incompleteRanges\":[],\"rows\":[],\"summary\":{\"total\":\(count),\"same\":\(count),\"valueChanged\":0,\"typeChanged\":0,\"onlyA\":0,\"onlyB\":0,\"notComparable\":0,\"differences\":0}}"
        requests.remove(at: index).resume(returning: response)
    }
}

@MainActor private final class DelayedDetailsWorker: WorkerSending {
    private let core = DirectCoreWorker()
    var pending: [(String, CheckedContinuation<String, any Error>)] = []
    func send(_ request: String) async throws -> String {
        let fields = try JSONSerialization.jsonObject(with: Data(request.utf8)) as! [String:Any]
        if fields["op"] as? String == "details" {
            return try await withCheckedThrowingContinuation { pending.append((request,$0)) }
        }
        return try await core.send(request)
    }
    func abort() { core.abort() }
    func reply() async throws {
        let (request, continuation) = pending.removeFirst()
        do { continuation.resume(returning: try await core.send(request)) }
        catch { continuation.resume(throwing: error) }
    }
}

@MainActor private func until(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(predicate())
}

@Test @MainActor func lateCancelledReplyCannotReplaceTheNewWorkspaceResult() async throws {
    let worker = ControlledWorker()
    let model = Workspace(clientFactory: { worker })
    model.a = "var env={x:1};"; model.b = model.a
    model.run()
    try await until { worker.requests.count == 1 }
    model.matched = 9; model.page = 2
    model.cancel()
    #expect(model.matched == 0)
    #expect(model.page == 0)
    #expect(!model.busy)
    #expect(model.a == "var env={x:1};")
    model.run()
    try await until { worker.requests.count == 2 }
    worker.reply(index: 1, count: 2)
    try await until { model.summary?.total == 2 }
    worker.reply(index: 0, count: 7)
    try await Task.sleep(for: .milliseconds(20))
    #expect(model.summary?.total == 2)
    #expect(worker.abortCount == 1)
}

@Test @MainActor func checkingRootsPreservesTheExplicitGlobalSelection() async throws {
    let worker = ControlledWorker()
    let model = Workspace(clientFactory: { worker })
    model.rootA = "*"; model.rootB = "*"
    model.inspectRoots()
    #expect(model.busy)
    try await until { !model.busy }
    #expect(model.rootA == "*")
    #expect(model.rootB == "*")
}

@Test @MainActor func changedYamlDisablesThePreviousOutput() {
    let model = Workspace(clientFactory: { ControlledWorker() })
    model.tool = .yaml
    model.output = "x: 1\n"
    model.a = "x: 2\n"
    model.changed(side: true)
    #expect(model.stale)
    #expect(model.output == "x: 1\n")
}

@Test @MainActor func clearingSelectionRejectsAnAlreadyPendingDetail() async throws {
    let worker = DelayedDetailsWorker()
    let model = Workspace(clientFactory: { worker })
    model.a = "var env={x:1};"; model.b = "var env={x:2};"
    model.run()
    try await until { model.rows.count == 1 && !model.busy }
    model.selected = model.rows[0].id; model.inspectSelection()
    try await until { worker.pending.count == 1 }
    // Direct model mutation must invalidate old replies without a SwiftUI callback.
    model.selected = nil
    #expect(model.detail == nil)
    try await worker.reply()
    try await Task.sleep(for: .milliseconds(10))
    #expect(model.detail == nil && model.selected == nil)
    model.cancel()
}

@Test @MainActor func changingSelectionRejectsTheOldDetailBeforeTheNextViewCallback() async throws {
    let worker = DelayedDetailsWorker()
    let model = Workspace(clientFactory: { worker })
    model.a = "var env={x:1,y:3};"; model.b = "var env={x:2,y:4};"
    model.run()
    try await until { model.rows.count == 2 && !model.busy }
    let first = model.rows[0].id, second = model.rows[1].id
    model.selected = first; model.inspectSelection()
    try await until { worker.pending.count == 1 }
    model.selected = second
    try await worker.reply()
    try await Task.sleep(for: .milliseconds(10))
    #expect(model.selected == second && model.detail == nil)
    model.inspectSelection()
    try await until { worker.pending.count == 1 }
    try await worker.reply()
    try await until { model.detail?.id == second }
    model.selected = nil
    #expect(model.detail == nil)
    model.cancel()
}

@Test @MainActor func outlineGroupKeepsSelectionButCannotShowLateFieldDetails() async throws {
    let worker = DelayedDetailsWorker()
    let model = Workspace(clientFactory: { worker })
    model.a = "var env={nested:{x:1}};"; model.b = "var env={nested:{x:2}};"
    model.run()
    try await until { model.rows.count == 1 && !model.busy }
    model.selected = model.rows[0].id; model.inspectSelection()
    try await until { worker.pending.count == 1 }
    let group = ResultOutlineID.branch([.key(Array("nested".utf16))])
    model.selectOutline(group)
    #expect(model.outlineSelection == group && model.selected == nil && model.detail == nil)
    try await worker.reply()
    try await Task.sleep(for: .milliseconds(10))
    #expect(model.outlineSelection == group && model.detail == nil)
    model.selected = model.rows[0].id
    #expect(model.outlineSelection == .result(model.rows[0].id))
    model.cancel()
    #expect(model.outlineSelection == nil)
}
