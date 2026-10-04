import Foundation
import Testing
import CompareShared
import MCP
@testable import CompareUI

@Suite(.serialized, .enabled(if:ProcessInfo.processInfo.environment["CC_HTTP_FIXTURE"] != nil,
                            "Run scripts/check-network.py for real loopback HTTP/TLS fixtures"))
struct HTTPTransportIntegration {
    @Test func realDeletedAndDestroyed404MetadataStopsEntireRead() async throws {
        let origin = try #require(ProcessInfo.processInfo.environment["CC_HTTP_FIXTURE"])
        for (name, code) in [("deleted", "VAULT_SECRET_DELETED"), ("destroyed", "VAULT_SECRET_DESTROYED")] {
            var settings = VaultSettings(); settings.url = origin; settings.token = "synthetic-token-b"
            settings.namespace = "team-b"; settings.mount = "kv-b"; settings.directoryPattern = "auth"
            settings.environment = name; settings.confirmedNonProduction = true
            let reader = VaultReader(validate: validatedFixture)
            let plan = try await reader.preview(VaultTarget(settings))
            try await requireVaultCode(code) { _ = try await reader.capture(plan) }
        }
    }
    @Test @MainActor func realMixedKVReadsRetainSourcesThroughAppAndMCP() async throws {
        let origin = try #require(ProcessInfo.processInfo.environment["CC_HTTP_FIXTURE"])
        let original = ProvenanceAuthorization().pair
        var a = original.a, b = original.b; a.url = origin; b.url = origin
        let pair = MCPVaultPair(a:a,b:b,authorizedAt:Date(),allowedA:original.allowedA,allowedB:original.allowedB)
        let model = Workspace(clientFactory: { DirectCoreWorker() })
        model.tool = .vault; model.switchTool(); model.vaultA = a; model.vaultB = b
        func settle(_ predicate: () -> Bool) async throws {
            let deadline = ContinuousClock.now + .seconds(5)
            while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
            try #require(predicate(), "Workspace did not settle: \(model.notice)")
        }
        model.previewVault(); try await settle { !model.busy && model.vaultPlanB != nil }
        model.run(); try await settle { !model.busy && model.summary != nil }
        #expect(model.complete && model.summary?.same == 3 && model.summary?.differences == 0)
        #expect(model.vaultSources.count == 2 && model.vaultSources[0].observations[0].metadata.version == nil)
        #expect(model.vaultSources[1].observations[0].metadata.version == "7")
        #expect(model.vaultSources[1].observations[0].metadata.deletionTime == "2099-01-01T00:00:00Z")
        let service = MCPService(workerFactory: { DirectCoreWorker() }, authorization: { pair })
        func json(_ result: CallTool.Result) throws -> [String:Any] {
            #expect(result.isError != true)
            let text = result.content.compactMap { if case .text(let value,_,_) = $0 { return value }; return nil }.joined()
            return try JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String:Any]
        }
        let preview = try json(await service.call(name: "vault_preview", arguments: [:]))
        let plan = try #require(preview["planId"] as? String)
        let report = try json(await service.call(name: "vault_compare", arguments: ["planId": .string(plan)]))
        #expect((report["summary"] as? [String:Int])?["same"] == 3)
        #expect((report["vaultSources"] as? [[String:Any]])?.count == 2)
        #expect(report["snapshotAtomic"] as? Bool == false)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self)
        #expect(!text.contains("synthetic-token") && !text.contains("synthetic-private") && !text.contains("9007199254740993"))
        let session = try #require(report["session"] as? String)
        let page = try json(await service.call(name: "comparison_rows", arguments: ["session": .string(session), "filter": .string("all"), "includeValues": .bool(true)]))
        let values = String(decoding: try JSONSerialization.data(withJSONObject: page), as: UTF8.self)
        #expect(values.contains("9007199254740993") && values.contains("1e10000") && values.contains("55296"))
        model.cancel()
    }
    func request(_ path: String, timeout: TimeInterval = 30) throws -> URLRequest {
        let origin=try #require(ProcessInfo.processInfo.environment["CC_HTTP_FIXTURE"])
        var request=URLRequest(url:try #require(URL(string:origin+path)))
        request.timeoutInterval=timeout
        request.setValue("synthetic-token",forHTTPHeaderField:"X-Vault-Token")
        return request
    }
    @Test func realRedirectDoesNotReplayCredentialsToAnotherOrigin() async throws {
        let response=try await VaultHTTPTransport().send(request("/redirect"))
        #expect(response.status == 302)
        #expect(response.body.isEmpty)
        // The runner independently checks that the other origin received no /sink.
    }
    @Test func realCookiesAreNotStoredAndRawBytesStayExact() async throws {
        let transport=VaultHTTPTransport()
        _=try await transport.send(request("/cookie"))
        let echo=try await transport.send(request("/echo"))
        let object=try JSONSerialization.jsonObject(with:echo.body) as! [String:Bool]
        #expect(object["cookiePresent"] == false)
        let raw=try await transport.send(request("/raw"))
        #expect(String(data:raw.body,encoding:.utf8) == #"{"n":9007199254740993,"s":"\ud800"}"#)
    }
    @Test func realUntrustedCertificateFailsWithoutTrustBypass() async throws {
        let origin=try #require(ProcessInfo.processInfo.environment["CC_TLS_FIXTURE"])
        var request=URLRequest(url:try #require(URL(string:origin+"/raw")))
        request.timeoutInterval=2
        try await requireVaultCode("VAULT_NETWORK_FAILED") { _=try await VaultHTTPTransport().send(request) }
    }
    @Test func realDisconnectionAndTimeoutFailWithinBounds() async throws {
        let transport=VaultHTTPTransport()
        try await requireVaultCode("VAULT_NETWORK_FAILED") { _=try await transport.send(request("/disconnect")) }
        let start=ContinuousClock.now
        try await requireVaultCode("VAULT_NETWORK_FAILED") { _=try await transport.send(request("/slow",timeout:0.2)) }
        #expect(ContinuousClock.now-start < .seconds(2))
    }
    @Test func realDeclaredBodyLimit() async throws {
        let transport=VaultHTTPTransport()
        try await requireVaultCode("RESOURCE_LIMIT") { _=try await transport.send(request("/declared-large")) }
    }
    @Test func realChunkedBodyLimit() async throws {
        let transport=VaultHTTPTransport()
        try await requireVaultCode("RESOURCE_LIMIT") { _=try await transport.send(request("/chunked-large")) }
    }
    @Test func realCancellationStopsNetworkAndAllowsANewRequest() async throws {
        let transport=VaultHTTPTransport(), urlRequest=try request("/cancel")
        let operation=Task { try await transport.send(urlRequest) }
        try await Task.sleep(for:.milliseconds(50))
        let start=ContinuousClock.now
        operation.cancel()
        do { _=try await operation.value; Issue.record("Cancelled operation unexpectedly completed") }
        catch { #expect(error is CancellationError) }
        #expect(ContinuousClock.now-start < .seconds(2))
        #expect(try await transport.send(request("/raw")).status == 200)
    }
    @Test func realConcurrentResponsesDoNotMixBodiesOrContinuations() async throws {
        let transport=VaultHTTPTransport()
        let origin=try #require(ProcessInfo.processInfo.environment["CC_HTTP_FIXTURE"])
        let received=try await withThrowingTaskGroup(of:Int.self) { group in
            for id in 0..<40 { group.addTask {
                let request=URLRequest(url:URL(string:origin+"/echo-id/\(id)")!)
                let response=try await transport.send(request)
                let value=try JSONSerialization.jsonObject(with:response.body) as! [String:Int]
                #expect(value["id"] == id)
                return value["id"]!
            }}
            var ids=Set<Int>(); for try await id in group { ids.insert(id) }; return ids
        }
        #expect(received == Set(0..<40))
    }
    @Test func realCancellationBeforeTaskStartsNeverHangs() async throws {
        let transport=VaultHTTPTransport(), urlRequest=try request("/cancel")
        for _ in 0..<30 {
            let task=Task { try await transport.send(urlRequest) }
            task.cancel()
            do { _=try await task.value; Issue.record("Precancelled request completed") }
            catch { #expect(error is CancellationError) }
        }
        #expect(try await transport.send(request("/raw")).status == 200)
    }
}
