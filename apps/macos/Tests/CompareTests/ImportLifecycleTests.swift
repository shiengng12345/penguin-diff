import Foundation
import Testing
@testable import CompareUI

private actor SuspendedFileReader {
    private var pending: [CheckedContinuation<String, any Error>] = []
    var count: Int { pending.count }
    func read(_ url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func finish(_ index: Int, text: String) { pending.remove(at: index).resume(returning: text) }
    func fail(_ index: Int) { pending.remove(at: index).resume(throwing: CocoaError(.fileReadUnknown)) }
}

@MainActor private final class ImportDeliveryProbe {
    private(set) var count = 0
    func record() { count += 1 }
}

@MainActor private final class ImportBusyWorker: WorkerSending {
    var pending: [CheckedContinuation<String, any Error>] = []
    var aborts = 0
    func send(_ request: String) async throws -> String {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func abort() { aborts += 1 }
    func finish() { pending.removeFirst().resume(returning: #"{"ok":true}"#) }
}

@MainActor private func awaitImportState(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(await condition())
}

@Suite(.serialized) struct ImportLifecycleTests {
    @Test @MainActor func stoppingOnlyAnImportPreservesTheLiveComparisonSession() async throws {
        let reader = SuspendedFileReader()
        let deliveries = ImportDeliveryProbe()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) }, importFinished: { deliveries.record() })
        model.a = "var env={x:1,y:7};"; model.b = "var env={x:2,y:7};"
        model.run()
        try await awaitImportState { !model.busy && model.matched == 1 }
        model.filter = "all"; model.loadRows(reset: true)
        try await awaitImportState { model.rows.count == 2 }
        let paths = model.rows.map(\.path), id = model.rows[0].id
        model.selected = id; model.inspectSelection()
        try await awaitImportState { model.detail?.id == id }
        model.importFile(URL(fileURLWithPath: "/synthetic/replacement.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.cancel()
        #expect(!model.canStop && !model.stale && !model.error)
        #expect(model.rows.map(\.path) == paths && model.summary?.total == 2 && model.summary?.differences == 1)
        #expect(model.selected == id && model.detail?.id == id && model.matched == 2)
        let completed = deliveries.count
        await reader.finish(0, text: "var env={replacement:999};")
        try await awaitImportState {
            deliveries.count == completed + 1
                && model.a == "var env={x:1,y:7};"
                && model.fileA == nil
                && model.labelA == "A · 粘贴或打开文件"
        }
        #expect(model.a == "var env={x:1,y:7};" && model.fileA == nil && model.labelA == "A · 粘贴或打开文件")
        // A fresh core query must still succeed; retaining only cached rows is insufficient.
        model.search = "y"; model.searchScope = "path"; model.loadRows(reset: true)
        try await awaitImportState { model.matched == 1 && model.rows.first?.path == "$.env.y" }
        #expect(!model.stale && !model.error)
        model.cancel()
    }

    @Test @MainActor func stoppingOnlyAnImportKeepsFormattedYamlUsable() async throws {
        let reader = SuspendedFileReader()
        let deliveries = ImportDeliveryProbe()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) }, importFinished: { deliveries.record() })
        model.tool = .yaml; model.switchTool(); model.a = "x: 1\n"
        model.run()
        try await awaitImportState { !model.busy && !model.output.isEmpty }
        let formatted = model.output
        model.importFile(URL(fileURLWithPath: "/synthetic/replacement.yaml"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.cancel()
        #expect(model.output == formatted && !model.stale && !model.canStop)
        let completed = deliveries.count
        await reader.fail(0)
        try await awaitImportState {
            deliveries.count == completed + 1
                && model.a == "x: 1\n"
                && model.output == formatted
                && !model.stale
                && !model.error
        }
        #expect(model.a == "x: 1\n" && model.output == formatted && !model.stale && !model.error)
    }

    @Test @MainActor func stopCommandIsAvailableDuringFileImportAndRejectsLateResults() async throws {
        let reader = SuspendedFileReader()
        let deliveries = ImportDeliveryProbe()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) }, importFinished: { deliveries.record() })
        model.a = "retained A"; model.b = "retained B"
        #expect(!model.canStop)
        model.importFile(URL(fileURLWithPath: "/synthetic/a.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/b.js"), side: false)
        try await awaitImportState { await reader.count == 2 }
        #expect(model.canStop && !model.busy)
        model.cancel()
        #expect(!model.canStop && !model.importing)
        let completed = deliveries.count
        await reader.finish(0, text: "cancelled A")
        await reader.fail(0)
        try await awaitImportState {
            deliveries.count == completed + 2
                && model.a == "retained A"
                && model.b == "retained B"
                && !model.error
        }
        #expect(model.a == "retained A" && model.b == "retained B" && !model.error)
    }

    @Test @MainActor func changingComparisonOptionsKeepsBothFileImports() async throws {
        let reader = SuspendedFileReader()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) })
        model.importFile(URL(fileURLWithPath: "/synthetic/a.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/b.js"), side: false)
        try await awaitImportState { await reader.count == 2 }
        model.rootA = "custom"; model.changed()
        model.inputTypeB = "kv-v2-response"; model.changed()
        model.indent = 4; model.changed()
        #expect(model.importingA && model.importingB)
        await reader.finish(0, text: "var custom={a:1};")
        await reader.finish(0, text: "var env={b:2};")
        try await awaitImportState { !model.importing }
        #expect(model.a == "var custom={a:1};" && model.b == "var env={b:2};")
        #expect(model.rootA == "custom" && model.inputTypeB == "kv-v2-response" && model.indent == 4)
        #expect(model.labelA == "A · a.js" && model.labelB == "B · b.js")
        model.cancel()
    }

    @Test @MainActor func changingOptionsStopsOldComputationButKeepsFileImport() async throws {
        let reader = SuspendedFileReader(), worker = ImportBusyWorker()
        let model = Workspace(clientFactory: { worker }, fileReader: { try await reader.read($0) })
        model.a = "var env={a:1};"; model.b = model.a
        model.run()
        try await awaitImportState { worker.pending.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/b.js"), side: false)
        try await awaitImportState { await reader.count == 1 }
        model.rootA = "other"; model.changed()
        #expect(!model.busy && worker.aborts == 1 && model.importingB)
        worker.finish()
        await reader.finish(0, text: "var env={new:2};")
        try await awaitImportState { !model.importing }
        #expect(model.b == "var env={new:2};" && model.labelB == "B · b.js")
        #expect(model.summary == nil && !model.busy)
        model.cancel()
    }

    @Test @MainActor func editingOneSideDuringComputationOnlyInvalidatesItsImport() async throws {
        let reader = SuspendedFileReader(), worker = ImportBusyWorker()
        let model = Workspace(clientFactory: { worker }, fileReader: { try await reader.read($0) })
        model.a = "var env={a:1};"; model.b = model.a
        model.run()
        try await awaitImportState { worker.pending.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/a.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/b.js"), side: false)
        try await awaitImportState { await reader.count == 2 }
        model.a = "manually edited"; model.changed(side: true)
        #expect(!model.busy && !model.importingA && model.importingB && worker.aborts == 1)
        worker.finish()
        await reader.finish(0, text: "superseded A")
        await reader.finish(0, text: "imported B")
        try await awaitImportState { !model.importing }
        #expect(model.a == "manually edited" && model.b == "imported B")
        model.cancel()
    }

    @Test @MainActor func rootInspectionDoesNotUseTextFromBeforeAnImport() async throws {
        let reader = SuspendedFileReader(), worker = ImportBusyWorker()
        let model = Workspace(clientFactory: { worker }, fileReader: { try await reader.read($0) })
        model.a = "var oldRoot={};"; model.b = model.a
        model.importFile(URL(fileURLWithPath: "/synthetic/new.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.inspectRoots()
        #expect(!model.busy)
        await reader.finish(0, text: "var newRoot={};")
        try await awaitImportState { !model.importing }
        // Drain any old-code request so the regression test leaves no continuation pending.
        for _ in 0..<10 { await Task.yield() }
        #expect(worker.pending.isEmpty)
        if !worker.pending.isEmpty { worker.finish() }
        #expect(model.a == "var newRoot={};")
        model.cancel()
    }

    @Test @MainActor func importingPreventsExchangeAndCompareUntilBothSidesFinish() async throws {
        let reader = SuspendedFileReader()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) })
        model.a = "old A"; model.b = "old B"
        model.importFile(URL(fileURLWithPath: "/synthetic/left.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/right.js"), side: false)
        #expect(model.importingA && model.importingB && model.importing)
        model.swapSides(); model.run()
        #expect(model.a == "old A" && model.b == "old B" && !model.busy)
        try await awaitImportState { await reader.count == 2 }
        await reader.finish(0, text: "var env={left:1};")
        try await awaitImportState { !model.importingA }
        #expect(model.importingB && model.importing)
        #expect(model.labelA == "A · left.js" && model.b == "old B")
        model.swapSides()
        #expect(model.a == "var env={left:1};")
        await reader.finish(0, text: "var env={right:2};")
        try await awaitImportState { !model.importing }
        model.swapSides()
        #expect(model.a == "var env={right:2};" && model.b == "var env={left:1};")
        #expect(model.labelA == "A · right.js" && model.labelB == "B · left.js")
        model.cancel()
    }

    @Test @MainActor func replacedImportCannotClearNewPendingStateOrOverwriteNewFile() async throws {
        let reader = SuspendedFileReader()
        let deliveries = ImportDeliveryProbe()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) }, importFinished: { deliveries.record() })
        model.a = "existing"
        model.importFile(URL(fileURLWithPath: "/synthetic/old.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/new.js"), side: true)
        try await awaitImportState { await reader.count == 2 }
        let completed = deliveries.count
        await reader.finish(0, text: "old result")
        try await awaitImportState {
            deliveries.count == completed + 1
                && model.importingA
                && model.a == "existing"
        }
        #expect(model.importingA && model.a == "existing")
        await reader.finish(0, text: "new result")
        try await awaitImportState { !model.importing }
        #expect(model.a == "new result" && model.labelA == "A · new.js")
        model.cancel()
    }

    @Test @MainActor func lateFailureAfterCancelDoesNotChangeToolOrShowAnError() async throws {
        let reader = SuspendedFileReader()
        let deliveries = ImportDeliveryProbe()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, fileReader: { try await reader.read($0) }, importFinished: { deliveries.record() })
        model.a = "var env={x:1};"; model.b = "var env={x:2};"
        model.run()
        try await awaitImportState { !model.busy && model.rows.count == 1 }
        model.importFile(URL(fileURLWithPath: "/synthetic/old.js"), side: true)
        try await awaitImportState { await reader.count == 1 }
        model.tool = .yaml; model.switchTool()
        model.a = "new: 1\n"
        let notice = model.notice
        #expect(!model.importing && model.rows.isEmpty && model.summary == nil && model.selected == nil)
        let completed = deliveries.count
        await reader.fail(0)
        try await awaitImportState {
            deliveries.count == completed + 1
                && model.a == "new: 1\n"
                && model.notice == notice
                && !model.error
        }
        #expect(model.a == "new: 1\n" && model.notice == notice && !model.error)
    }
}
