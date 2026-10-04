import Foundation
import AppKit
import Testing
@testable import CompareUI

// Real Rust evaluator; inject only a rows transport fault or hold an already
// computed report reply. Return/caller processing has no intervening suspension
// on MainActor, so delivered acknowledges Workspace's response/error handling.
@MainActor final class NoticeExportWorker: WorkerSending {
    private let core = DirectCoreWorker()
    var failNextRows = false
    var holdReports = false
    private(set) var completedRows = 0
    private(set) var delivered = 0
    private var reports: [(String, CheckedContinuation<String, any Error>)] = []
    var pendingCount: Int { reports.count }
    func send(_ request: String) async throws -> String {
        let fields = try JSONSerialization.jsonObject(with: Data(request.utf8)) as! [String: Any]
        let isRows = fields["op"] as? String == "rows"
        defer { if isRows { completedRows += 1 } }
        if failNextRows && fields["op"] as? String == "rows" {
            failNextRows = false
            throw WorkerFailure.interrupted
        }
        let response = try await core.send(request)
        guard holdReports && fields["op"] as? String == "report" else { return response }
        defer { delivered += 1 }
        return try await withCheckedThrowingContinuation { reports.append((response, $0)) }
    }
    func abort() { core.abort() } // Deliberately deliver computed replies after cancellation.
    func finish(_ index: Int = 0, failure: Bool = false) {
        let (response, continuation) = reports.remove(at: index)
        if failure { continuation.resume(throwing: WorkerFailure.interrupted) }
        else { continuation.resume(returning: response) }
    }
    func drain() { while !reports.isEmpty { finish(failure: true) } }
}

@MainActor func noticeExportSettled(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(4)
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(predicate(), "Result notice/export did not settle")
}

@MainActor private final class NoticeExportFixture {
    let worker = NoticeExportWorker()
    let directory: URL
    let target: URL
    var destinationCalls = 0
    lazy var model = Workspace(clientFactory: { [worker] in worker }, reportDestination: { [weak self] _, _ in
        guard let self else { return nil }
        self.destinationCalls += 1
        return self.target
    })
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        target = directory.appendingPathComponent("owned-synthetic-report.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func compare(unknown: Bool = false) async throws {
        let keys = (0..<401).map { String(format: "k%03d", $0) }
        model.a = "var env={" + keys.enumerated().map { "\($0.element):\($0.offset)" }.joined(separator: ",") + "};"
        model.b = "var env={" + keys.enumerated().map { "\($0.element):\($0.offset + 1)" }.joined(separator: ",") + "};"
        if unknown { model.a += "var happy={x:missingExternal};"; model.b += "var happy={x:1};" }
        model.changed(); model.run()
        try await noticeExportSettled { !self.model.busy && self.model.matched == (unknown ? 402 : 401) }
        try #require(!model.error && model.rows.first?.path == "$.env.k000")
    }
    func startExport() async throws {
        let count = worker.pendingCount
        worker.holdReports = true
        model.export()
        try await noticeExportSettled { self.worker.pendingCount == count + 1 }
    }
    func cleanup() {
        worker.drain(); model.cancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite(.serialized) struct ResultNoticeExportTests {
    @Test @MainActor func copyingToOwnedPasteboardSupersedesRowErrorAndRetryKeepsItsNotice() async throws {
        let fixture = try NoticeExportFixture(), pasteboard = NSPasteboard.withUniqueName()
        defer { fixture.cleanup(); pasteboard.releaseGlobally() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        fixture.model.copy("OWNED_SYNTHETIC_VARIABLE", pasteboard: pasteboard)
        let copiedNotice = fixture.model.notice
        #expect(pasteboard.string(forType: .string) == "OWNED_SYNTHETIC_VARIABLE")
        #expect(!fixture.model.error && copiedNotice.contains("已复制"))
        fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.page == 1 }
        #expect(!fixture.model.error && fixture.model.notice == copiedNotice)
    }

    @Test @MainActor func successfulExportSupersedesRowErrorAndRetryKeepsTheSavedNotice() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        fixture.model.export()
        try await noticeExportSettled { FileManager.default.fileExists(atPath: fixture.target.path) }
        let savedNotice = fixture.model.notice
        #expect(!fixture.model.error && savedNotice.contains("已导出"))
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.target)) as! [String: Any]
        #expect((report["rows"] as? [Any])?.count == 401)
        fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.page == 1 }
        #expect(!fixture.model.error && fixture.model.notice == savedNotice)
    }

    @Test @MainActor func rejectedRemoteFileRetainsItsNewerErrorAfterRowsRetry() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        let input = fixture.model.a
        fixture.model.importFile(try #require(URL(string: "https://example.invalid/never-fetched.js")), side: true)
        let rejectedNotice = fixture.model.notice
        #expect(fixture.model.error && rejectedNotice.contains("本地文件") && !fixture.model.importing)
        fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.page == 1 }
        #expect(fixture.model.error && fixture.model.notice == rejectedNotice && fixture.model.a == input)
        #expect(fixture.model.fileA == nil)
    }

    @Test @MainActor func stoppingComparisonClearsItsPreviousRowError() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        let input = fixture.model.a
        fixture.model.cancel()
        #expect(!fixture.model.error && fixture.model.notice.contains("操作已停止"))
        #expect(fixture.model.a == input && fixture.model.summary == nil && fixture.model.rows.isEmpty)
    }

    @Test @MainActor func inputEditSupersedesRowErrorAndMarksRetainedResultsStale() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        fixture.model.a += "\n// edited"; fixture.model.changed(side: true)
        #expect(!fixture.model.error && fixture.model.stale && fixture.model.resultControlsDisabled)
        #expect(fixture.model.notice.contains("结果已过期") && fixture.model.rows.first?.path == "$.env.k000")
    }

    @Test @MainActor func successfulRootRefreshKeepsItsNewerNoticeAfterRowsRetry() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        fixture.model.inspectRoots()
        try await noticeExportSettled { !fixture.model.busy && fixture.model.rootsA.contains("env") }
        let refreshedNotice = fixture.model.notice
        #expect(!fixture.model.error && refreshedNotice.contains("变量列表已更新"))
        fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.page == 1 }
        #expect(!fixture.model.error && fixture.model.notice == refreshedNotice)
    }

    @Test @MainActor func incompleteResultNoticeSurvivesRepeatedRowsFailureAndRetryInBothLanguages() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare(unknown: true)
        let model = fixture.model
        try #require(!model.complete && model.summary?.notComparable == 1)
        for _ in 0..<2 {
            let completed = fixture.worker.completedRows
            fixture.worker.failNextRows = true; model.changePage(by: 1)
            try await noticeExportSettled { fixture.worker.completedRows == completed + 1 && model.error }
            #expect(model.page == 0 && model.rows.first?.path == "$.env.k000")
        }
        let completed = fixture.worker.completedRows
        model.changePage(by: 1)
        try await noticeExportSettled { fixture.worker.completedRows == completed + 1 && model.page == 1 }
        #expect(!model.error && !model.complete && !model.incomplete.isEmpty)
        model.preferences.language = .simplifiedChinese
        #expect(model.noticeLocalized.contains("结果不完整") && !model.noticeLocalized.contains("比较完成"))
        model.preferences.language = .english
        #expect(model.noticeLocalized.localizedCaseInsensitiveContains("incomplete") && !model.noticeLocalized.contains("Comparison complete"))
    }

    @Test @MainActor func retryAfterNewComparisonUsesItsCurrentCompletenessNotice() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare(unknown: true)
        try await fixture.compare()
        fixture.worker.failNextRows = true; fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.error }
        fixture.model.changePage(by: 1)
        try await noticeExportSettled { fixture.model.page == 1 }
        #expect(!fixture.model.error && fixture.model.complete && fixture.model.incomplete.isEmpty)
        #expect(!fixture.model.notice.contains("不完整"))
    }

    @Test @MainActor func stoppedExportRejectsBothLateSuccessAndLateFailureWithoutWriting() async throws {
        for failure in [false, true] {
            let fixture = try NoticeExportFixture()
            defer { fixture.cleanup() }
            try await fixture.compare(); try await fixture.startExport()
            fixture.model.cancel()
            let stopNotice = fixture.model.notice
            fixture.worker.finish(failure: failure)
            try await noticeExportSettled { fixture.worker.delivered == 1 }
            #expect(fixture.model.summary == nil && !fixture.model.error && fixture.model.notice == stopNotice)
            #expect(fixture.destinationCalls == 0 && !FileManager.default.fileExists(atPath: fixture.target.path))
        }
    }

    @Test @MainActor func editedInputRejectsBothLateExportRepliesAndKeepsStaleNotice() async throws {
        for failure in [false, true] {
            let fixture = try NoticeExportFixture()
            defer { fixture.cleanup() }
            try await fixture.compare(); try await fixture.startExport()
            fixture.model.a += "\n// local edit"; fixture.model.changed(side: true)
            let staleNotice = fixture.model.notice
            fixture.worker.finish(failure: failure)
            try await noticeExportSettled { fixture.worker.delivered == 1 }
            #expect(fixture.model.stale && !fixture.model.error && fixture.model.notice == staleNotice)
            #expect(fixture.destinationCalls == 0 && !FileManager.default.fileExists(atPath: fixture.target.path))
        }
    }

    @Test @MainActor func newComparisonRejectsBothPreviousSessionsExportReplies() async throws {
        for failure in [false, true] {
            let fixture = try NoticeExportFixture()
            defer { fixture.cleanup() }
            try await fixture.compare(); try await fixture.startExport()
            fixture.model.a = "var fresh={x:1};"; fixture.model.b = "var fresh={x:2};"
            fixture.model.changed(); fixture.model.run()
            try await noticeExportSettled { !fixture.model.busy && fixture.model.matched == 1 && fixture.model.rows.first?.path == "$.fresh.x" }
            let newNotice = fixture.model.notice
            fixture.worker.finish(failure: failure)
            try await noticeExportSettled { fixture.worker.delivered == 1 }
            #expect(!fixture.model.stale && !fixture.model.error && fixture.model.notice == newNotice)
            #expect(fixture.model.summary?.total == 1 && fixture.model.rows.first?.path == "$.fresh.x")
            #expect(fixture.destinationCalls == 0 && !FileManager.default.fileExists(atPath: fixture.target.path))
        }
    }

    @Test @MainActor func newestExportWinsAndOldFailureCannotOverwriteItsSavedNotice() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare(); try await fixture.startExport(); try await fixture.startExport()
        fixture.worker.finish(1)
        try await noticeExportSettled { FileManager.default.fileExists(atPath: fixture.target.path) }
        let savedNotice = fixture.model.notice
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.target)) as! [String: Any]
        #expect((report["rows"] as? [Any])?.count == 401)
        fixture.worker.finish(failure: true)
        try await noticeExportSettled { fixture.worker.delivered == 2 }
        #expect(!fixture.model.error && fixture.model.notice == savedNotice && fixture.destinationCalls == 1)
    }

    @Test @MainActor func currentExportFailureRemainsVisibleAndDoesNotOpenDestination() async throws {
        let fixture = try NoticeExportFixture()
        defer { fixture.cleanup() }
        try await fixture.compare(); try await fixture.startExport()
        fixture.worker.finish(failure: true)
        try await noticeExportSettled { fixture.worker.delivered == 1 }
        #expect(fixture.model.error && !fixture.model.stale && fixture.model.summary?.total == 401)
        #expect(fixture.destinationCalls == 0 && !FileManager.default.fileExists(atPath: fixture.target.path))
    }
}
