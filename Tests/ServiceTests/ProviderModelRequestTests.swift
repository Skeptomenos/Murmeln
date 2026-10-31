import Foundation
import Synchronization
import Testing
@testable import mrml

private final class PullURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { let code: Int; let body: String }
    static let replies = Mutex<[String: Reply]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let reply = Self.replies.withLock { $0[url.host!]! }
        let body = url.path == "/api/tags" ? "{\"models\":[{\"name\":\"gemma2:2b\"}]}" : reply.body
        let code = url.path == "/api/tags" ? 200 : reply.code
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: code,
            httpVersion: nil, headerFields: ["Content-Type": "application/x-ndjson"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
@Suite("Provider model request ownership")
struct ProviderModelRequestTests {
    @Test("Pull requires HTTP and terminal stream success", arguments: [0, 1, 2, 3, 4, 5])
    func pullResult(kind: Int) async {
        let replies: [PullURLProtocol.Reply] = [
            .init(code: 404, body: "{\"error\":\"missing\"}\n"),
            .init(code: 200, body: "{\"error\":\"disk full\"}\n"),
            .init(code: 200, body: "{\"status\":\"pulling manifest\"}\n"),
            .init(code: 200, body: "not json\n"),
            .init(code: 200, body: "{\"status\":\"success\"}\n{\"error\":\"failed\"}\n"),
            .init(code: 200, body: "{\"status\":\"downloading\",\"completed\":50,\"total\":100}\n{\"status\":\"success\"}\n")
        ]
        let host = UUID().uuidString.lowercased() + ".test"
        PullURLProtocol.replies.withLock { $0[host] = replies[kind] }
        defer { PullURLProtocol.replies.withLock { _ = $0.removeValue(forKey: host) } }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PullURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = OllamaService(session: session, baseURLProvider: { "https://" + host })
        let succeeded = await service.pullModel("gemma2:2b")
        #expect(succeeded == (kind == 5))
        #expect((service.pullError == nil) == succeeded)
        #expect(!service.isPulling && service.pullingModelName == nil && service.pullProgress.isEmpty)
        #expect(service.installedModels == (succeeded ? ["gemma2:2b"] : []))
    }

    @Test("Configuration edits invalidate discovery without fetching or changing a custom model",
          arguments: [1, 2], ["", "partial", "https://intermediate.test"])
    func editingConfiguration(field: Int, value: String) async throws {
        let controller = ModelDiscoveryRequestController()
        var key = ["provider", "https://original.test", "committed-key"]
        var pending: CheckedContinuation<[ModelInfo], Never>?
        var fetchCount = 0
        var completed = false
        var selection = "custom-model"
        controller.load(request: key, currentRequest: { key }, fetch: {
            fetchCount += 1
            let models = await withCheckedContinuation { pending = $0 }
            completed = true
            return models
        }, applySelection: { selection = $0.first!.id })
        try #require(await waitUntil { pending != nil })
        key[field] = value
        controller.invalidate(for: key)
        #expect(!controller.isLoading && controller.models.isEmpty)
        #expect(fetchCount == 1 && selection == "custom-model")
        pending!.resume(returning: [.init(id: "fallback", name: "Fallback")])
        try #require(await waitUntil { completed })
        await Task.yield()
        #expect(fetchCount == 1 && selection == "custom-model")
        #expect(!controller.isLoading && controller.models.isEmpty)
    }

    @Test("Explicit discovery survives either configuration-observer order", arguments: [false, true])
    func committedDiscovery(observerFirst: Bool) async throws {
        let controller = ModelDiscoveryRequestController()
        let previous = ["provider", "https://original.test", "previous-key"]
        let current = ["provider", "https://committed.test", "committed-key"]
        controller.invalidate(for: previous)
        var pending: CheckedContinuation<[ModelInfo], Never>?
        var fetchCount = 0
        var selections: [String] = []
        if observerFirst { controller.invalidate(for: current) }
        controller.load(request: current, currentRequest: { current }, fetch: {
            fetchCount += 1
            return await withCheckedContinuation { pending = $0 }
        }, applySelection: { selections.append($0.first!.id) })
        if !observerFirst { controller.invalidate(for: current) }
        try #require(await waitUntil { pending != nil })
        #expect(controller.isLoading && fetchCount == 1)
        pending!.resume(returning: [.init(id: "current", name: "Current")])
        try #require(await waitUntil { !controller.isLoading })
        #expect(controller.models.map(\.id) == ["current"])
        #expect(selections == ["current"] && fetchCount == 1)
    }

    @Test("Superseded discovery cannot publish models, selection or loading state", arguments: [false, true])
    func reversedDiscovery(olderFirst: Bool) async throws {
        let controller = ModelDiscoveryRequestController()
        var key = ["A", "url-a", "key-a"]
        var pending: [String: CheckedContinuation<[ModelInfo], Never>] = [:]
        var completed: Set<String> = []
        var selection = "original"
        func start(_ id: String) {
            controller.load(request: key, currentRequest: { key }, fetch: {
                let models = await withCheckedContinuation { pending[id] = $0 }
                completed.insert(id)
                return models
            }, applySelection: { selection = $0.first!.id })
        }
        start("A")
        #expect(await waitUntil { pending["A"] != nil })
        key = ["B", "url-b", "key-b"]
        start("B")
        #expect(await waitUntil { pending["B"] != nil })
        if olderFirst {
            pending.removeValue(forKey: "A")!.resume(returning: [.init(id: "stale", name: "stale")])
            #expect(await waitUntil { completed.contains("A") })
            #expect(controller.isLoading && selection == "original")
        }
        pending.removeValue(forKey: "B")!.resume(returning: [.init(id: "current", name: "current")])
        #expect(await waitUntil { !controller.isLoading })
        if !olderFirst {
            pending.removeValue(forKey: "A")!.resume(returning: [.init(id: "stale", name: "stale")])
            #expect(await waitUntil { completed.contains("A") })
        }
        #expect(controller.models.map(\.id) == ["current"] && selection == "current")
        start("C")
        #expect(await waitUntil { pending["C"] != nil })
        key[1] = "changed-url-without-reload"
        pending.removeValue(forKey: "C")!.resume(returning: [.init(id: "wrong-url", name: "wrong-url")])
        #expect(await waitUntil { !controller.isLoading })
        #expect(controller.models.isEmpty && selection == "current")
        start("D")
        #expect(await waitUntil { pending["D"] != nil })
        controller.cancel()
        pending.removeValue(forKey: "D")!.resume(returning: [.init(id: "closed", name: "closed")])
        #expect(await waitUntil { completed.contains("D") })
        #expect(!controller.isLoading && controller.models.isEmpty && selection == "current")
    }
}
