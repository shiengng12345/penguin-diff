import Foundation
import Testing
@testable import CompareUI

// Keep Workspace and the actual Rust evaluator; delay only the transport reply.
// All delivery/caller frames run on MainActor, with no further suspension between
// returning this reply, decoding it and applying Workspace's response guards.
@MainActor private final class HeldRowsWorker: WorkerSending {
    private let core = DirectCoreWorker()
    var holdRows = false
    var failNextInspection = false
    private(set) var delivered = 0
    private var replies: [(String, CheckedContinuation<String, any Error>)] = []
    var pendingCount: Int { replies.count }
    func send(_ request: String) async throws -> String {
        let fields = try JSONSerialization.jsonObject(with: Data(request.utf8)) as! [String: Any]
        if failNextInspection && fields["op"] as? String == "inspectJs" {
            failNextInspection = false
            throw WorkerFailure.timedOut
        }
        let response = try await core.send(request)
        guard holdRows && fields["op"] as? String == "rows" else { return response }
        defer { delivered += 1 }
        return try await withCheckedThrowingContinuation { replies.append((response, $0)) }
    }
    func abort() { core.abort() } // Deliberately allow the already-computed late reply.
    func finish(_ index: Int = 0, failure: WorkerFailure? = nil) {
        let (response, continuation) = replies.remove(at: index)
        if let failure { continuation.resume(throwing: failure) }
        else { continuation.resume(returning: response) }
    }
    func drain() { while !replies.isEmpty { finish(failure: .interrupted) } }
}

@MainActor private final class CountingRowsWorker: WorkerSending {
    private let core = DirectCoreWorker()
    private(set) var rowRequests = 0

    func send(_ request: String) async throws -> String {
        let fields = try JSONSerialization.jsonObject(with: Data(request.utf8)) as! [String: Any]
        if fields["op"] as? String == "rows" { rowRequests += 1 }
        return try await core.send(request)
    }

    func abort() { core.abort() }
}

@MainActor private func rowsSettled(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(predicate(), "Row transaction did not settle")
}

@MainActor private func rowsFixture(_ worker: HeldRowsWorker, destination: @escaping @MainActor (String, String) -> URL? = { _, _ in nil }) async throws -> Workspace {
    let model = Workspace(clientFactory: { worker }, reportDestination: destination)
    let fields = (0..<401).map { String(format: "k%03d", $0) }
    model.a = "var env={" + fields.enumerated().map { "\($0.element):\($0.offset)" }.joined(separator: ",") + "};"
    model.b = "var env={" + fields.enumerated().map { "\($0.element):\($0.offset + 1)" }.joined(separator: ",") + "};"
    model.run()
    try await rowsSettled { !model.busy && model.matched == 401 && model.rows.count == 200 }
    try #require(model.rows.first?.path == "$.env.k000" && model.page == 0)
    worker.holdRows = true
    return model
}

@Suite(.serialized) struct RowsTransactionTests {
    @Test @MainActor func identicalPendingRowsRequestsAreCoalescedAndLaterRefreshStillRuns() async throws {
        let worker = CountingRowsWorker()
        let model = Workspace(clientFactory: { worker })
        defer { model.cancel() }
        model.a = "var env={x:1,y:7};"
        model.b = "var env={x:2,y:7};"
        model.run()
        try await rowsSettled { !model.busy && model.matched == 1 && model.rows.count == 1 }
        let baseline = worker.rowRequests

        model.filter = "all"
        model.loadRows(reset: true)
        model.loadRows(reset: true)
        try await rowsSettled { worker.rowRequests == baseline + 1 && model.rows.count == 2 }
        #expect(worker.rowRequests == baseline + 1)

        model.loadRows(reset: true)
        try await rowsSettled { worker.rowRequests == baseline + 2 && model.rows.count == 2 }
    }

    @Test @MainActor func pendingPageKeepsDisplayedPageUntilItsActualRowsArrive() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        #expect(model.page == 0 && model.rows.first?.path == "$.env.k000")
        worker.finish()
        try await rowsSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && model.rows.last?.path == "$.env.k399")
    }

    @Test @MainActor func exportingWhilePageIsPendingDoesNotDiscardItsRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("synthetic-report.json")
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker, destination: { _, _ in target })
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.export()
        try await rowsSettled { FileManager.default.fileExists(atPath: target.path) }
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: target)) as! [String: Any]
        #expect((report["rows"] as? [Any])?.count == 401 && (report["summary"] as? [String: Int])?["total"] == 401)
        worker.finish()
        try await rowsSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && model.matched == 401 && !model.stale && !model.error)
    }

    @Test @MainActor func rootRefreshWhilePageIsPendingDoesNotDiscardItsRows() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.inspectRoots()
        try await rowsSettled { !model.busy && model.rootsA.contains("env") }
        worker.finish()
        try await rowsSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && model.matched == 401 && !model.error)
    }

    @Test @MainActor func failedPageRetainsMatchingOldPageAndCanRetry() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        worker.finish(failure: .interrupted)
        try await rowsSettled { model.error }
        #expect(model.page == 0 && model.rows.first?.path == "$.env.k000" && model.matched == 401)
        worker.holdRows = false
        model.changePage(by: 1)
        try await rowsSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && !model.error)
    }

    @Test @MainActor func newerFilterRejectsAnOlderPageReply() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.filter = "ONLY_A"; model.loadRows(reset: true)
        try await rowsSettled { worker.pendingCount == 2 }
        worker.finish(1)
        try await rowsSettled { model.matched == 0 && model.rows.isEmpty }
        worker.finish()
        try await rowsSettled { worker.delivered == 2 }
        #expect(model.page == 0 && model.rows.isEmpty && model.matched == 0 && model.summary?.valueChanged == 401)
    }

    @Test @MainActor func editedInputsRejectAnAlreadyComputedPageReply() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.a += "\n// synthetic edit"; model.changed(side: true)
        worker.finish()
        try await rowsSettled { worker.delivered == 1 }
        #expect(model.stale && model.page == 0 && model.rows.first?.path == "$.env.k000")
    }

    @Test @MainActor func olderPageFailureCannotPoisonNewerFilterResults() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.filter = "ONLY_A"; model.loadRows(reset: true)
        try await rowsSettled { worker.pendingCount == 2 }
        worker.finish(1)
        try await rowsSettled { model.matched == 0 && model.rows.isEmpty }
        worker.finish(failure: .interrupted)
        try await rowsSettled { worker.delivered == 2 }
        #expect(!model.error && model.page == 0 && model.rows.isEmpty && model.matched == 0)
    }

    @Test @MainActor func pageRecoveryDoesNotClearANewerRootInspectionFailure() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        worker.finish(failure: .interrupted)
        try await rowsSettled { model.error }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        worker.failNextInspection = true
        model.inspectRoots()
        try await rowsSettled { !model.busy && model.error }
        let rootFailure = model.notice
        worker.finish()
        try await rowsSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && model.error && model.notice == rootFailure)
    }

    @Test @MainActor func stoppedComparisonCannotBeRestoredByALatePageReply() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        model.cancel(); worker.finish()
        try await rowsSettled { worker.delivered == 1 }
        #expect(model.summary == nil && model.rows.isEmpty && model.page == 0 && model.matched == 0)
    }

    @Test @MainActor func newComparisonRejectsThePreviousSessionsPageReply() async throws {
        let worker = HeldRowsWorker(), model = try await rowsFixture(worker)
        defer { worker.drain(); model.cancel() }
        model.changePage(by: 1)
        try await rowsSettled { worker.pendingCount == 1 }
        worker.holdRows = false
        model.a = "var env={fresh:1};"; model.b = "var env={fresh:2};"; model.changed(); model.run()
        try await rowsSettled { !model.busy && model.rows.first?.path == "$.env.fresh" && model.matched == 1 }
        worker.finish()
        try await rowsSettled { worker.delivered == 1 }
        #expect(model.summary?.total == 1 && model.rows.count == 1 && model.rows.first?.path == "$.env.fresh" && model.page == 0 && !model.stale)
    }
}
