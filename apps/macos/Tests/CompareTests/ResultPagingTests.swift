import Foundation
import Testing
import CompareShared
@testable import CompareUI

private actor PagingImportGate {
    private var continuation: CheckedContinuation<String, any Error>?
    private(set) var readStarted = false
    func read(_ url: URL) async throws -> String {
        readStarted = true
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: "var env={replacement:1}"); continuation = nil }
}

@MainActor private func pagingSettled(_ predicate: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !(await predicate()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(await predicate(), "Paging operation did not settle")
}

@MainActor private func pagingFixture(fileReader: @escaping @Sendable (URL) async throws -> String = { try InputFiles.read($0) }) async throws -> Workspace {
    let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: fileReader)
    let names = (0..<401).map { "k" + String(format: "%03d", $0) }
    model.a = "var env={" + names.enumerated().map { "\($0.element):\($0.offset)" }.joined(separator: ",") + "}"
    model.b = "var env={" + names.enumerated().map { "\($0.element):\($0.offset + 1)" }.joined(separator: ",") + "}"
    model.run()
    try await pagingSettled { !model.busy && model.matched == 401 && model.rows.count == 200 }
    try #require(model.rows.first?.path == "$.env.k000" && model.summary?.valueChanged == 401)
    return model
}

@Suite(.serialized)
struct ResultPagingTests {
    @Test @MainActor func actualThreePageRowsAndBoundsStayInSync() async throws {
        let model = try await pagingFixture()
        defer { model.cancel() }
        #expect(!model.resultControlsDisabled && model.page == 0)
        model.changePage(by: -1)
        #expect(model.page == 0)
        model.changePage(by: 1)
        try await pagingSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1 && model.rows.count == 200 && model.rows.last?.path == "$.env.k399")
        model.changePage(by: Int.max)
        #expect(model.page == 1 && model.rows.first?.path == "$.env.k200")
        model.changePage(by: 1)
        try await pagingSettled { model.rows.count == 1 && model.rows.first?.path == "$.env.k400" }
        #expect(model.page == 2 && model.matched == 401)
        model.changePage(by: 1)
        #expect(model.page == 2 && model.rows.first?.path == "$.env.k400")
        model.changePage(by: -1)
        try await pagingSettled { model.rows.first?.path == "$.env.k200" }
        model.changePage(by: -1)
        try await pagingSettled { model.rows.first?.path == "$.env.k000" }
        model.changePage(by: Int.min)
        #expect(model.page == 0 && model.rows.count == 200)
        model.cancel()
        model.changePage(by: 1)
        #expect(model.page == 0 && model.rows.isEmpty)
    }

    @Test @MainActor func editingInputCannotChangeRetainedPageOrRows() async throws {
        let model = try await pagingFixture()
        defer { model.cancel() }
        let oldRows = model.rows.map(\.id)
        model.a += "\n// synthetic edit"
        model.changed(side: true)
        #expect(model.stale && model.resultControlsDisabled)
        model.changePage(by: 1)
        #expect(model.page == 0 && model.rows.map(\.id) == oldRows && model.matched == 401)
        model.loadRows(reset: true)
        #expect(model.page == 0 && model.rows.map(\.id) == oldRows)
        model.run()
        try await pagingSettled { !model.busy && !model.stale && model.rows.first?.path == "$.env.k000" }
        #expect(!model.resultControlsDisabled)
        model.changePage(by: 1)
        try await pagingSettled { model.rows.first?.path == "$.env.k200" }
        #expect(model.page == 1)
    }

    @Test @MainActor func actualRootInspectionCannotChangePreviousPageWhileBusy() async throws {
        let model = try await pagingFixture()
        defer { model.cancel() }
        model.changePage(by: 1)
        try await pagingSettled { model.rows.first?.path == "$.env.k200" }
        let oldRows = model.rows.map(\.id)
        model.inspectRoots()
        #expect(model.busy && model.resultControlsDisabled)
        model.changePage(by: -1)
        try #require(model.page == 1 && model.rows.map(\.id) == oldRows)
        try await pagingSettled { !model.busy && model.rootsA.contains("env") }
        #expect(!model.resultControlsDisabled)
        model.changePage(by: -1)
        try await pagingSettled { model.rows.first?.path == "$.env.k000" }
        #expect(model.page == 0)
    }

    @Test @MainActor func pendingFileImportCannotChangeRetainedPage() async throws {
        let gate = PagingImportGate()
        let model = try await pagingFixture(fileReader: { try await gate.read($0) })
        defer { model.cancel() }
        let oldRows = model.rows.map(\.id)
        model.importFile(URL(fileURLWithPath: "/synthetic-paging-fixture.js"), side: true)
        try await pagingSettled { await gate.readStarted }
        #expect(model.importing && model.resultControlsDisabled)
        model.changePage(by: 1)
        #expect(model.page == 0 && model.rows.map(\.id) == oldRows)
        model.cancel()
        await gate.finish()
        // Cancelling only a pending file import preserves the existing result.
        #expect(!model.importing && model.page == 0 && model.rows.map(\.id) == oldRows)
        #expect(model.summary?.valueChanged == 401)
    }
}
