import Foundation
import Testing
import CompareShared
@testable import CompareUI

private actor ExportVaultTransport: VaultTransport {
    private(set) var requests: [URLRequest] = []
    let long = "REPORT_PRIVATE_LONG_" + String(repeating: "汉😀", count: 4096)
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        let first = request.url?.host == "uat-a.example.invalid"
        guard first || request.url?.host == "uat-b.example.invalid", request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-Vault-Token") == (first ? "synthetic-token-a" : "synthetic-token-b"),
              request.value(forHTTPHeaderField: "X-Vault-Namespace") == (first ? "team-a/" : "team-b/") else {
            throw VaultFailure.invalid("Unexpected synthetic export request")
        }
        let mount = first ? "kv-a" : "kv-b"
        if request.url?.path == "/v1/sys/internal/ui/mounts/" + mount {
            return .init(status: 200, body: Data("{\"data\":{\"path\":\"\(mount)/\",\"type\":\"kv\",\"options\":{\"version\":\"\(first ? "1" : "2")\"}}}".utf8))
        }
        guard request.url?.path == (first ? "/v1/kv-a/auth/uat-swim" : "/v1/kv-b/data/auth/qat-other") else {
            throw VaultFailure.invalid("Unexpected synthetic export path")
        }
        let bulk = (0..<240).map { String(format: "\"bulk%03d\":\"REPORT_PRIVATE_%03d\"", $0, $0) }.joined(separator: ",")
        let encodedLong = String(decoding: try JSONSerialization.data(withJSONObject: long, options: [.fragmentsAllowed]), as: UTF8.self)
        let blob = first ? #"{"\ud800":"\udfff","arr":[-0,9007199254740993,1e10000]}"# : "null"
        let object = "{" + bulk + #", "big":9007199254740993,"exp":1e10000,"blob":"# + blob + #", "s":"\ud800","n":"# + (first ? "-0,\"long\":" + encodedLong : "0") + "}"
        let body = first ? "{\"data\":" + object + "}" : "{\"data\":{\"data\":" + object + #", "metadata":{"version":9223372036854775807,"created_time":"2026-10-03T01:02:03.123456789Z","deletion_time":"2099-01-01T00:00:00Z","destroyed":false,"custom_metadata":{"private":"METADATA_PRIVATE_CANARY"}}}}"#
        return .init(status: 200, body: Data(body.utf8))
    }
}

@MainActor private final class ExportDestination {
    let directory: URL
    var name = "report"
    var cancelled = false
    var onChoose: (() -> Void)?
    var calls = 0
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func target(_ ext: String = "json") -> URL { directory.appendingPathComponent(name + "." + ext) }
    func choose(_ ext: String, _ message: String) -> URL? {
        calls += 1; onChoose?()
        return cancelled ? nil : target(ext)
    }
}

@MainActor private func exportSettled(_ predicate: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    try #require(predicate(), "Export did not reach its expected observable state")
}

@MainActor private func capturedExportWorkspace(_ destination: ExportDestination, clientFactory: @escaping () -> any WorkerSending = { DirectCoreWorker() }) async throws -> (Workspace, ExportVaultTransport) {
    let store = ProvenanceAuthorization(), transport = ExportVaultTransport()
    let model = Workspace(clientFactory: clientFactory,
                          vaultFactory: { VaultReader(transport: transport, validate: $0) },
                          reportDestination: { destination.choose($0, $1) })
    model.tool = .vault; model.switchTool(); model.vaultA = store.pair.a; model.vaultB = store.pair.b
    model.previewVault(); try await exportSettled { !model.busy }
    try #require(!model.error && model.vaultPlanB != nil, Comment(rawValue: model.notice))
    model.run(); try await exportSettled { !model.busy && (model.summary != nil || model.error) }
    try #require(!model.error, Comment(rawValue: model.notice))
    try await exportSettled { model.matched == 3 }
    #expect(model.summary?.total == 246 && model.summary?.same == 243 && model.summary?.valueChanged == 1 && model.summary?.typeChanged == 1 && model.summary?.onlyA == 1)
    return (model, transport)
}

private func exportedFile(_ destination: URL) throws -> (String, CoreResponse, [String: Any]) {
    let text = try InputFiles.read(destination)
    let mode = try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? NSNumber
    #expect(mode?.intValue == 0o600)
    return (text, try CoreResponse.decode(text), try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]))
}

@Suite(.serialized) struct VaultReportExportTests {
    @Test @MainActor func liveVaultRowsRetryPreservesNonAtomicSnapshotDisclosureInBothLanguages() async throws {
        let destination = try ExportDestination(), worker = NoticeExportWorker()
        defer { worker.drain(); try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination, clientFactory: { worker })
        defer { model.cancel() }
        model.filter = "all"; model.loadRows(reset: true)
        try await noticeExportSettled { model.matched == 246 }
        worker.failNextRows = true; model.changePage(by: 1)
        try await noticeExportSettled { model.error }
        #expect(model.page == 0)
        model.changePage(by: 1)
        try await noticeExportSettled { model.page == 1 }
        #expect(!model.error && model.rows.count == 46 && model.vaultSources.count == 2)
        model.preferences.language = .simplifiedChinese
        #expect(model.noticeLocalized.contains("不是原子快照"))
        model.preferences.language = .english
        #expect(model.noticeLocalized.contains("not an atomic snapshot"))
        #expect(await transport.requests.count == 6)
    }

    @Test @MainActor func fullLiveVaultExportPreservesTypedValuesAndCredentialFreeSourcesBeyondOnePage() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        model.export(); try await exportSettled { FileManager.default.fileExists(atPath: destination.target().path) || model.error }
        #expect(!model.error)
        let (text, response, object) = try exportedFile(destination.target())
        let rows = try #require(response.rows)
        #expect(rows.count == 246 && response.summary?.total == 246 && response.complete == true)
        func row(_ key: String) throws -> ResultRow { try #require(rows.first { $0.segments?.last == .key(Array(key.utf16)) }) }
        #expect(try row("big").a.literal == "9007199254740993" && row("big").b.literal == "9007199254740993")
        #expect(try row("exp").a.literal == "1e10000" && row("exp").b.literal == "1e10000")
        #expect(try row("n").a.literal == "-0" && row("n").b.literal == "0" && row("n").status == "VALUE_CHANGED")
        #expect(try row("s").a.units == [55296] && row("s").a.type == "String")
        let blob = try #require(try row("blob").a.entries)
        #expect(try row("blob").status == "TYPE_CHANGED" && row("blob").b.type == "Null")
        #expect(blob.first { $0.keyUnits == [55296] }?.value.units == [57343])
        #expect(blob.first { $0.keyUnits == Array("arr".utf16) }?.value.items?.map(\.literal) == ["-0", "9007199254740993", "1e10000"])
        let long = transport.long
        #expect(try row("long").a.units == Array(long.utf16) && row("long").a.truncated == nil && row("long").b.type == "Missing")
        #expect(try row("bulk239").a.units == Array("REPORT_PRIVATE_239".utf16))
        let sources = try #require(object["vaultSources"] as? [[String: Any]])
        let captures = try #require(object["sources"] as? [[String: String]])
        #expect(sources.count == 2 && captures.count == 2 && object["snapshotAtomic"] as? Bool == false)
        #expect(captures[0]["configurationName"] == "uat-swim" && captures[1]["configurationName"] == "qat-other")
        let sourceKeys: Set<String> = ["side", "origin", "namespaceRoot", "namespacePattern", "mount", "directoryRoot", "directoryPattern", "configurationName", "started", "finished", "observations"]
        #expect(sources.allSatisfy { Set($0.keys) == sourceKeys })
        #expect(sources[0]["side"] as? String == "A" && sources[1]["side"] as? String == "B")
        #expect(sources[0]["namespaceRoot"] as? String == "team-a" && sources[1]["mount"] as? String == "kv-b")
        for (index, version) in [(0, 1), (1, 2)] {
            let observation = try #require((sources[index]["observations"] as? [[String: Any]])?.first)
            let metadata = try #require(observation["metadata"] as? [String: Any])
            #expect(metadata["kvVersion"] as? Int == version)
            if index == 0 { #expect(metadata["version"] is NSNull) }
            else {
                #expect(metadata["version"] as? String == "9223372036854775807")
                #expect(metadata["createdTime"] as? String == "2026-10-03T01:02:03.123456789Z")
                #expect(metadata["deletionTime"] as? String == "2099-01-01T00:00:00Z" && metadata["destroyed"] as? Bool == false)
            }
        }
        #expect(!text.contains("synthetic-token") && !text.contains("METADATA_PRIVATE_CANARY") && !text.contains("custom_metadata"))
        #expect(await transport.requests.count == 6)
    }

    @Test @MainActor func filteredHiddenValuesKeepSourceMetadataAndFullSummaryWithoutPrivateValues() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        // Verify each selector independently: search must not mask a broken filter.
        for (filter, search, filename) in [("ONLY_A", "", "filtered"), ("all", "long", "searched")] {
            destination.name = filename
            model.filter = filter; model.search = search; model.searchScope = "key"
            model.exportFiltered = true; model.exportValues = false
            model.export(); try await exportSettled { FileManager.default.fileExists(atPath: destination.target().path) || model.error }
            #expect(!model.error)
            let (text, response, object) = try exportedFile(destination.target())
            #expect(response.rows?.count == 1 && response.summary?.total == 246 && object["includesValues"] as? Bool == false)
            let row = try #require(response.rows?.first)
            #expect(row.status == "ONLY_A" && row.segments?.last == .key(Array("long".utf16)))
            for side in [row.a, row.b] {
                #expect(side.literal == nil && side.units == nil && side.entries == nil && side.items == nil && side.reason == nil)
                #expect(side.display == "<值未导出>")
            }
            let jsonRow = try #require((object["rows"] as? [[String: Any]])?.first)
            for key in ["a", "b"] {
                #expect(Set(try #require(jsonRow[key] as? [String: Any]).keys) == ["type", "display", "present"])
            }
            #expect((object["vaultSources"] as? [[String: Any]])?.count == 2 && object["snapshotAtomic"] as? Bool == false)
            #expect(!text.contains("REPORT_PRIVATE_") && !text.contains("9007199254740993") && !text.contains("1e10000"))
            #expect(!text.contains("synthetic-token") && !text.contains("METADATA_PRIVATE_CANARY"))
        }
        #expect(await transport.requests.count == 6)
    }

    @Test @MainActor func liveVaultCSVExportsThroughSameSafeWriterWithoutJSONSourceDecoration() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        model.export(true); try await exportSettled { FileManager.default.fileExists(atPath: destination.target("csv").path) || model.error }
        #expect(!model.error)
        let text = try InputFiles.read(destination.target("csv"))
        #expect(text.hasPrefix("path,status,a_type,b_type,a_value,b_value\r\n") && text.contains("bulk239") && text.contains("REPORT_PRIVATE_LONG_"))
        #expect(!text.contains("vaultSources") && !text.contains("snapshotAtomic") && !text.contains("synthetic-token") && !text.contains("METADATA_PRIVATE_CANARY"))
        let mode = try FileManager.default.attributesOfItem(atPath: destination.target("csv").path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        #expect(await transport.requests.count == 6)
    }

    @Test @MainActor func cancelledOrStaleDestinationDoesNotWriteAnyReport() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, _) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        destination.cancelled = true
        model.export(); try await exportSettled { destination.calls == 1 || model.error }
        #expect(!model.error && !FileManager.default.fileExists(atPath: destination.target().path))
        destination.cancelled = false; destination.onChoose = { model.changed() }
        model.export(); try await exportSettled { destination.calls == 2 || model.error }
        #expect(model.stale && !model.error && !FileManager.default.fileExists(atPath: destination.target().path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.directory.path).isEmpty)
    }

    @Test @MainActor func existingDestinationIsRejectedWithoutOverwritingItsBytes() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        let original = Data("ORIGINAL_PRIVATE_FILE".utf8)
        try InputFiles.writeNew(original, to: destination.target(), inputs: [])
        model.export(); try await exportSettled { model.error }
        #expect(try Data(contentsOf: destination.target()) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.directory.path) == ["report.json"])
        #expect(destination.calls == 1)
        #expect(await transport.requests.count == 6)
    }

    @Test @MainActor func offlineVaultExportDoesNotAttachPreviousLiveSourceRecordsOrReadVaultAgain() async throws {
        let destination = try ExportDestination()
        defer { try? FileManager.default.removeItem(at: destination.directory) }
        let (model, transport) = try await capturedExportWorkspace(destination)
        defer { model.cancel() }
        #expect(model.vaultSources.count == 2)
        model.vaultLive = false; model.a = #"{"x":9007199254740993}"#; model.b = "{}"
        model.changed(); model.run(); try await exportSettled { !model.busy && model.summary?.total == 1 && model.matched == 1 }
        model.export(); try await exportSettled { FileManager.default.fileExists(atPath: destination.target().path) || model.error }
        #expect(!model.error)
        let (_, response, object) = try exportedFile(destination.target())
        #expect(response.rows?.count == 1 && response.rows?.first?.a.literal == "9007199254740993")
        #expect(object["sources"] == nil && object["vaultSources"] == nil && object["snapshotAtomic"] == nil)
        #expect(await transport.requests.count == 6)
    }
}
