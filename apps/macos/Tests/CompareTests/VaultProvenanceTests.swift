import Foundation
import Testing
import CoreBridge
import CompareShared
import MCP
@testable import CompareUI

actor ProvenanceVault: VaultTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> VaultHTTPResponse {
        requests.append(request)
        let first = request.url?.host == "uat-a.example.invalid"
        guard first || request.url?.host == "uat-b.example.invalid",
              request.httpMethod == "GET",
              request.value(forHTTPHeaderField:"X-Vault-Token") == (first ? "synthetic-token-a" : "synthetic-token-b"),
              request.value(forHTTPHeaderField:"X-Vault-Namespace") == (first ? "team-a/" : "team-b/") else { throw VaultFailure.invalid("Unexpected synthetic source") }
        let mount = first ? "kv-a" : "kv-b", path = request.url!.path
        let body: String
        if path == "/v1/sys/internal/ui/mounts/" + mount {
            body = "{\"data\":{\"path\":\"" + mount + "/\",\"type\":\"kv\",\"options\":{\"version\":\"" + (first ? "1" : "2") + "\"}}}"
        } else if first && path == "/v1/kv-a/auth/uat-swim" {
            body = #"{"data":{"big":9007199254740993,"x":2,"s":"\ud800"}}"#
        } else if !first && path == "/v1/kv-b/data/auth/qat-other" {
            body = #"{"data":{"data":{"big":9007199254740993,"x":2,"s":"\ud800"},"metadata":{"version":7,"created_time":"2026-10-03T01:02:03.123456789Z","deletion_time":"","destroyed":false,"custom_metadata":{"private":"synthetic-private"}}}}"#
        } else { throw VaultFailure.invalid("Unexpected synthetic path") }
        return .init(status:200,body:Data(body.utf8))
    }
}

@MainActor final class ProvenanceAuthorization {
    var enabled = true
    let pair: MCPVaultPair
    init() {
        var a = VaultSettings(); a.url="https://uat-a.example.invalid"; a.token="synthetic-token-a"
        a.namespace="team-a"; a.mount="kv-a"; a.directoryPattern="auth"; a.environment="uat-swim"; a.confirmedNonProduction=true
        var b=a; b.url="https://uat-b.example.invalid"; b.token="synthetic-token-b"; b.namespace="team-b"
        b.mount="kv-b"; b.environment="qat-other"
        pair = .init(a:a,b:b,authorizedAt:Date(),allowedA:[.init(namespace:a.namespace,namespaceKey:".",path:"auth/uat-swim",directoryKey:"auth",kvVersion:1)],allowedB:[.init(namespace:b.namespace,namespaceKey:".",path:"auth/qat-other",directoryKey:"auth",kvVersion:2)])
    }
    func load() throws -> MCPVaultPair { guard enabled else { throw VaultFailure.invalid("Synthetic authorization revoked") }; return pair }
}

private func provenanceJSON(_ result: CallTool.Result) throws -> [String:Any] {
    let text = result.content.compactMap { if case .text(let value,_,_) = $0 { return value }; return nil }.joined()
    return try JSONSerialization.jsonObject(with:Data(text.utf8)) as! [String:Any]
}

@Suite(.serialized)
struct VaultProvenance {
    @Test func plannedDeletionStillReadsAndKnown404MetadataStopsWithoutGuessingUnknown404() async throws {
        let transport = MatrixVault { request, _ in
            request.url!.path.contains("/sys/internal/ui/mounts/") ? mountResponse() : vaultResponse(#"{"data":{"data":{"x":1},"metadata":{"version":7,"deletion_time":"2099-01-01T00:00:00Z","destroyed":false}}}"#)
        }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        let plan = try await reader.preview(literalTarget())
        let captured = try await reader.capture(plan)
        let text = try #require(captured.entries.first?["response"])
        let smallFixture = try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String:Int]
        #expect(smallFixture == ["x":1])
        #expect(captured.observations.first?.metadata.deletionTime == "2099-01-01T00:00:00Z")
        for (body, code) in [
            (#"{"data":{"data":null,"metadata":{"version":7,"deletion_time":"2020-01-01T00:00:00Z","destroyed":false}}}"#, "VAULT_SECRET_DELETED"),
            (#"{"data":{"data":null,"metadata":{"version":7,"destroyed":true}}}"#, "VAULT_SECRET_DESTROYED"),
            (#"{"errors":[]}"#, "VAULT_HTTP_404"),
            (#"{"data":{"data":{"x":1},"metadata":{"version":7}}}"#, "VAULT_HTTP_404"),
            (#"{"data":{"data":null,"metadata":{"version":"synthetic-private"}}}"#, "VAULT_HTTP_404")
        ] {
            let fixture = MatrixVault { request, _ in
                request.url!.path.contains("/sys/internal/ui/mounts/") ? mountResponse() : vaultResponse(body, status: 404)
            }
            let failureReader = VaultReader(transport: fixture, validate: validatedFixture)
            let failurePlan = try await failureReader.preview(literalTarget())
            try await requireVaultCode(code) { _ = try await failureReader.capture(failurePlan) }
            #expect(await fixture.requests.count == 3)
        }
    }
    @Test @MainActor func appMixedSourcesMapThroughTypedSegmentsAndClearOnScopeChange() async throws {
        let store = ProvenanceAuthorization(), transport = ProvenanceVault()
        let model = Workspace(clientFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) })
        model.tool = .vault; model.switchTool(); model.vaultA = store.pair.a; model.vaultB = store.pair.b
        func settle(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            try #require(predicate(), "Workspace did not settle: \(model.notice)")
        }
        model.previewVault(); try await settle { !model.busy && model.vaultPlanB != nil }
        #expect(model.vaultSources.isEmpty)
        #expect(await transport.requests.count == 2)
        model.run(); try await settle { !model.busy && model.summary != nil }
        #expect(model.complete && model.summary?.same == 3 && model.summary?.differences == 0)
        #expect(model.vaultSources.count == 2)
        model.filter = "all"; model.loadRows(reset: true); try await settle { model.rows.count == 3 }
        for row in model.rows {
            #expect(model.vaultSources[0].observation(for: row)?.namespace == "team-a")
            #expect(model.vaultSources[1].observation(for: row)?.path == "auth/qat-other")
        }
        #expect(model.vaultSources[0].observations[0].metadata.version == nil)
        #expect(model.vaultSources[1].observations[0].metadata.version == "7")
        let previousRow = try #require(model.rows.first)
        model.selected = previousRow.id; model.detail = previousRow
        model.previewVault()
        #expect(model.busy && model.stale)
        #expect(model.detail == nil && model.selected == nil)
        try await settle { !model.busy && model.vaultPlanB != nil }
        #expect(model.detail == nil && model.selected == nil)
        model.selected = previousRow.id; model.detail = previousRow
        model.run()
        #expect(model.busy && model.stale)
        #expect(model.detail == nil && model.selected == nil)
        try await settle { !model.busy && !model.stale }
        model.cancel()
        #expect(model.summary == nil && model.vaultSources.isEmpty && model.vaultCaptureInfo.isEmpty)
        model.run(); try await settle { !model.busy && model.summary != nil }
        #expect(model.vaultSources.count == 2)
        let old = model.vaultA; model.vaultA.environment = "other"
        model.vaultChanged(side: true, old: old, new: model.vaultA)
        #expect(model.stale && model.vaultSources.isEmpty && model.vaultCaptureInfo.isEmpty)
        #expect(await transport.requests.count == 16)
        model.previewVault(); try await settle { !model.busy }
        // Re-previewing a changed scope must not restore old read sources.
        #expect(model.vaultSources.isEmpty)
        model.tool = .env; model.switchTool()
        #expect(model.vaultSources.isEmpty && model.vaultA.token.isEmpty && model.vaultB.token.isEmpty)
        model.cancel()
    }

    @Test func metadataFailuresStopEntireBatchWithoutAdditionalMetadataRequests() async throws {
        for (metadata, code) in [
            (#"{"version":2,"destroyed":true}"#, "VAULT_SECRET_DESTROYED"),
            (#"{"version":3,"deletion_time":"2026-10-03T01:02:03Z","destroyed":false}"#, "VAULT_SECRET_DELETED"),
            (#"{"version":4,"created_time":"synthetic-private-invalid"}"#, "VAULT_METADATA_INVALID")
        ] {
            let transport = MatrixVault { request, _ in
                if request.url!.path.contains("/sys/internal/ui/mounts/") { return mountResponse() }
                return vaultResponse("{\"data\":{\"data\":null,\"metadata\":" + metadata + "}}")
            }
            let reader = VaultReader(transport: transport, validate: validatedFixture)
            let target = try literalTarget()
            let secrets = ["first", "second"].map { VaultSecret(namespace: "", namespaceKey: ".", path: $0, directoryKey: $0, kvVersion: 2) }
            let plan = VaultPlan(target: target, secrets: secrets, discoveredNamespaces: [""], created: Date())
            do { _ = try await reader.capture(plan); Issue.record("Expected entire-batch failure") }
            catch let failure as VaultFailure { #expect(failure.code == code && !failure.message.contains("synthetic-private")) }
            catch let failure as CoreError { #expect(failure.code == code && !failure.message.contains("synthetic-private")) }
            #expect(await transport.requests.count == 2)
            #expect(await transport.requests.allSatisfy { $0.httpMethod == "GET" && !$0.url!.path.contains("/metadata/") })
        }
    }

    @Test func sourceVersionDoesNotParticipateInBusinessDiffAndLargeMetadataVersionRemainsExact() async throws {
        let transport = MatrixVault { request, count in
            if request.url!.path.contains("/sys/internal/ui/mounts/") { return mountResponse() }
            let version = count < 4 ? "9007199254740993" : "9223372036854775807"
            return vaultResponse("{\"data\":{\"data\":{\"n\":1e10000,\"s\":\"\\ud800\"},\"metadata\":{\"version\":" + version + "}}}")
        }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        let plan = try await reader.preview(literalTarget())
        let first = try await reader.capture(plan), second = try await reader.capture(plan)
        #expect(first.entries[0]["response"] == second.entries[0]["response"])
        #expect(first.observations[0].metadata.version == "9007199254740993")
        #expect(second.observations[0].metadata.version == "9223372036854775807")
        #expect(first.entries[0]["response"]?.contains("1e10000") == true)
        #expect(first.entries[0]["response"]?.contains("\\ud800") == true)
        let sources = [VaultSourceSnapshot(first, side: "A"), VaultSourceSnapshot(second, side: "B")]
        let object = try #require(try VaultSourceSnapshot.json(sources) as? [[String:Any]])
        let observation = try #require((object[0]["observations"] as? [[String:Any]])?.first)
        let started = try #require(observation["started"] as? String), finished = try #require(observation["finished"] as? String)
        #expect(started <= finished)
        let text = String(decoding: try JSONEncoder().encode(sources), as: UTF8.self)
        #expect(!text.contains("synthetic-token") && !text.contains("1e10000") && !text.contains("\\ud800"))
    }

    @Test @MainActor func cachedSourceRecordsAreEvictedWithComparisonSession() async throws {
        let store = ProvenanceAuthorization(), transport = ProvenanceVault()
        let service = MCPService(workerFactory: { DirectCoreWorker() }, vaultFactory: { VaultReader(transport: transport, validate: $0) }, authorization: { try store.load() })
        let plan = try #require(try provenanceJSON(await service.call(name: "vault_preview", arguments: [:]))["planId"] as? String)
        let report = try provenanceJSON(await service.call(name: "vault_compare", arguments: ["planId": .string(plan)]))
        let session = try #require(report["session"] as? String)
        for _ in 0..<4 {
            let result = await service.call(name: "env_compare", arguments: ["a": .string("var env={x:1}"), "b": .string("var env={x:1}")])
            #expect(result.isError != true)
            #expect(try provenanceJSON(result)["vaultSources"] == nil)
        }
        let result = await service.call(name: "comparison_rows", arguments: ["session": .string(session)])
        #expect(result.isError == true)
        #expect(!result.content.description.contains("team-a"))
    }

    @Test func newSourceStringsHaveEnglishTranslations() {
        for key in ["Vault 读取来源 · {0} 条", "KV v{0} · secret 版本：{1}", "本机读取：{0} → {1}", "未知", "未删除", "是", "否", "创建时间：{0}", "删除／计划删除时间：{0}", "销毁：{0}"] {
            #expect(L10n.text(key, language: .english) != key)
        }
    }
    @Test func sourceLookupUsesTypedPairKeysInsteadOfDisplayPathParsing() async throws {
        let transport = MatrixVault { request, _ in
            request.url!.path.contains("/sys/internal/ui/mounts/") ? mountResponse() : vaultResponse(#"{"data":{"data":{"x":1},"metadata":{"version":9}}}"#)
        }
        let reader = VaultReader(transport: transport, validate: validatedFixture)
        let secret = VaultSecret(namespace: "sandbox/team", namespaceKey: "team.one", path: "auth/child/config", directoryKey: "auth/child", kvVersion: 2)
        let captured = try await reader.capture(VaultPlan(target: literalTarget(), secrets: [secret], discoveredNamespaces: [secret.namespace], created: Date()))
        let source = VaultSourceSnapshot(captured, side: "A")
        let side: [String:Any] = ["type":"Number", "display":"1", "present":true]
        func row(_ namespace: String, _ path: String) throws -> ResultRow {
            let fields: [String:Any] = ["id":0,"path":"$.misleading.display.path","status":"SAME","a":side,"b":side,
                                       "segments":[["keyUnits":Array(namespace.utf16)],["keyUnits":Array(path.utf16)],["keyUnits":[120]]]]
            return try JSONDecoder().decode(ResultRow.self, from: JSONSerialization.data(withJSONObject: fields))
        }
        #expect(try source.observation(for: row("team.one", "auth/child"))?.path == "auth/child/config")
        #expect(try source.observation(for: row("team", "auth/child")) == nil)
        #expect(try source.observation(for: row("team.one", "auth")) == nil)
    }
    @Test @MainActor func mixedKvSourcesRetainMetadataAcrossMCPPagesAndRejectRevocation() async throws {
        let store=ProvenanceAuthorization(), transport=ProvenanceVault()
        let service=MCPService(workerFactory:{DirectCoreWorker()},vaultFactory:{VaultReader(transport:transport,validate:$0)},authorization:{try store.load()})
        let preview=await service.call(name:"vault_preview",arguments:[:])
        #expect(preview.isError != true)
        let plan = try #require(try provenanceJSON(preview)["planId"] as? String)
        let compared=await service.call(name:"vault_compare",arguments:["planId":.string(plan)])
        #expect(compared.isError != true)
        let report=try provenanceJSON(compared)
        #expect((report["summary"] as? [String:Int])?["same"] == 3)
        #expect(report["includesValues"] as? Bool == false)
        let sources=try #require(report["vaultSources"] as? [[String:Any]])
        #expect(sources.count == 2 && report["snapshotAtomic"] as? Bool == false)
        let first=try #require((sources[0]["observations"] as? [[String:Any]])?.first)
        let second=try #require((sources[1]["observations"] as? [[String:Any]])?.first)
        let a=try #require(first["metadata"] as? [String:Any]), b=try #require(second["metadata"] as? [String:Any])
        #expect(a["kvVersion"] as? Int == 1 && a["version"] is NSNull)
        #expect(b["kvVersion"] as? Int == 2 && b["version"] as? String == "7")
        #expect(b["createdTime"] as? String == "2026-10-03T01:02:03.123456789Z")
        #expect(first["namespace"] as? String == "team-a" && second["namespace"] as? String == "team-b")
        let text=String(decoding:try JSONSerialization.data(withJSONObject:report),as:UTF8.self)
        #expect(!text.contains("synthetic-token") && !text.contains("synthetic-private") && !text.contains("9007199254740993"))
        let session=try #require(report["session"] as? String)
        let page=try provenanceJSON(await service.call(name:"comparison_rows",arguments:["session":.string(session),"filter":.string("all"),"includeValues":.bool(true)]))
        #expect((page["vaultSources"] as? [[String:Any]])?.count == 2)
        #expect(String(decoding:try JSONSerialization.data(withJSONObject:page),as:UTF8.self).contains("9007199254740993"))
        store.enabled=false
        #expect(await service.call(name:"comparison_rows",arguments:["session":.string(session)]).isError == true)
        #expect(await transport.requests.count == 6)
    }
}
