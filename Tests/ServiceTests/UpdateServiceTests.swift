import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("UpdateService Tests")
struct UpdateServiceTests {
    @Test("macOS 25 selects the newest compatible 2.5 release")
    func legacyOSSelectsMaintenanceRelease() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(25))

        let selected = selector.selectNewestCompatible(
            from: [release("v2.6.0"), release("v2.5.1")],
            currentVersion: "2.5.0"
        )

        #expect(try #require(selected?.tagName) == "v2.5.1")
    }

    @Test("macOS 14 selects the newest compatible 2.5 release")
    func oldestSupportedOSSelectsMaintenanceRelease() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(14))

        let selected = selector.selectNewestCompatible(
            from: [release("v2.6.0"), release("v2.5.1")],
            currentVersion: "2.5.0"
        )

        #expect(try #require(selected?.tagName) == "v2.5.1")
    }

    @Test("macOS 26 selects the newest compatible 2.6 release")
    func modernOSSelectsCurrentRelease() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(26))

        let selected = selector.selectNewestCompatible(
            from: [release("v2.5.1"), release("v2.6.0")],
            currentVersion: "2.5.0"
        )

        #expect(try #require(selected?.tagName) == "v2.6.0")
    }

    @Test("Selection uses semantic version order instead of feed order")
    func semanticOrderingIgnoresFeedOrder() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(26))

        let selected = selector.selectNewestCompatible(
            from: [release("v2.5.10"), release("v3.0.0"), release("v2.6.1")],
            currentVersion: "2.5.0"
        )

        #expect(try #require(selected?.tagName) == "v3.0.0")
    }

    @Test("Drafts and prereleases are ignored")
    func unstableReleasesAreIgnored() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(26))
        let selected = selector.selectNewestCompatible(
            from: [
                release("v3.0.0", draft: true),
                release("v2.9.0", prerelease: true),
                release("v2.6.1"),
            ],
            currentVersion: "2.6.0"
        )

        #expect(try #require(selected?.tagName) == "v2.6.1")
    }

    @Test(
        "Malformed tags are ignored",
        arguments: ["", "v", "v2.6", "v2.6.0.1", "v2.6.x", "vv2.6.0", "v2.6.0-beta.1", " 2.6.0"]
    )
    func malformedTagsAreIgnored(_ tag: String) {
        let selector = ReleaseSelector(currentOSVersion: osVersion(26))

        let selected = selector.selectNewestCompatible(
            from: [release(tag)],
            currentVersion: "2.5.0"
        )

        #expect(selected == nil)
    }

    @Test("Incomplete candidates do not hide a valid compatible release")
    func incompleteCandidatesAreIgnored() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(25))
        let selected = selector.selectNewestCompatible(
            from: [
                GitHubRelease(
                    tagName: nil,
                    htmlURL: nil,
                    body: nil,
                    draft: nil,
                    prerelease: nil
                ),
                release("v2.5.1"),
            ],
            currentVersion: "2.5.0"
        )

        #expect(try #require(selected?.tagName) == "v2.5.1")
    }

    @Test("Untrusted release URLs are ignored")
    func untrustedURLsAreIgnored() throws {
        let selector = ReleaseSelector(currentOSVersion: osVersion(26))
        let selected = selector.selectNewestCompatible(
            from: [
                release("v3.0.0", htmlURL: "https://example.com/download"),
                release("v2.9.0", htmlURL: "http://github.com/Skeptomenos/Murmeln/releases/tag/v2.9.0"),
                release("v2.6.1"),
            ],
            currentVersion: "2.6.0"
        )

        #expect(try #require(selected?.tagName) == "v2.6.1")
    }

    @Test("Equal, older, and incompatible releases produce no update")
    func noEligibleReleaseProducesNoSelection() {
        let selector = ReleaseSelector(currentOSVersion: osVersion(25))

        #expect(selector.selectNewestCompatible(
            from: [release("v2.5.0"), release("v2.4.9"), release("v2.6.0")],
            currentVersion: "2.5.0"
        ) == nil)
        #expect(selector.selectNewestCompatible(
            from: [release("v2.5.1")],
            currentVersion: "not-a-version"
        ) == nil)
    }

    @Test("Production update check requests the release list and selects through compatibility policy")
    func serviceUsesReleaseListAndSelector() async throws {
        var capturedRequest: URLRequest?
        let releases = [release("v2.6.0"), release("v2.5.1")]
        let service = UpdateService(
            operatingSystemVersion: osVersion(25),
            currentVersion: { "2.5.0" },
            dataLoader: { request in
                capturedRequest = request
                return try response(for: request, body: releases)
            }
        )

        let outcome = await service.checkForUpdates()

        #expect(outcome == .updateAvailable)
        #expect(service.updateAvailable)
        #expect(service.latestVersion == "2.5.1")
        #expect(service.releaseURL?.absoluteString == releaseURL(for: "v2.5.1"))
        #expect(capturedRequest?.url?.path == "/repos/Skeptomenos/Murmeln/releases")
        #expect(URLComponents(url: try #require(capturedRequest?.url), resolvingAgainstBaseURL: false)?
            .queryItems?.contains(URLQueryItem(name: "per_page", value: "100")) == true)
    }

    @Test("A later no-update result clears stale selected release state")
    func noUpdateClearsStaleState() async throws {
        var responseBodies = [
            [release("v2.5.1")],
            [release("v2.6.0")],
        ]
        let service = UpdateService(
            operatingSystemVersion: osVersion(25),
            currentVersion: { "2.5.0" },
            dataLoader: { request in
                try response(for: request, body: responseBodies.removeFirst())
            }
        )

        #expect(await service.checkForUpdates() == .updateAvailable)
        #expect(await service.checkForUpdates() == .upToDate)
        #expect(!service.updateAvailable)
        #expect(service.latestVersion == nil)
        #expect(service.releaseURL == nil)
        #expect(service.releaseNotes == nil)
    }

    @Test("HTTP, decoding, and transport failures are not reported as up to date")
    func failuresReturnTypedFailureAndClearState() async throws {
        var mode = 0
        let service = UpdateService(
            operatingSystemVersion: osVersion(26),
            currentVersion: { "2.5.0" },
            dataLoader: { request in
                defer { mode += 1 }
                switch mode {
                case 0:
                    return try response(for: request, body: [release("v2.6.0")])
                case 1:
                    return (Data(), httpResponse(for: request, statusCode: 503))
                case 2:
                    return (Data("not-json".utf8), httpResponse(for: request, statusCode: 200))
                default:
                    throw URLError(.notConnectedToInternet)
                }
            }
        )

        #expect(await service.checkForUpdates() == .updateAvailable)
        for _ in 0..<3 {
            #expect(await service.checkForUpdates() == .failed)
            #expect(!service.updateAvailable)
            #expect(service.latestVersion == nil)
            #expect(service.releaseURL == nil)
        }
    }
}

private func osVersion(_ major: Int) -> OperatingSystemVersion {
    OperatingSystemVersion(majorVersion: major, minorVersion: 0, patchVersion: 0)
}

private func release(
    _ tag: String,
    htmlURL: String? = nil,
    draft: Bool = false,
    prerelease: Bool = false
) -> GitHubRelease {
    GitHubRelease(
        tagName: tag,
        htmlURL: htmlURL ?? releaseURL(for: tag),
        body: "Notes for \(tag)",
        draft: draft,
        prerelease: prerelease
    )
}

private func releaseURL(for tag: String) -> String {
    "https://github.com/Skeptomenos/Murmeln/releases/tag/\(tag)"
}

private func response(
    for request: URLRequest,
    body: [GitHubRelease]
) throws -> (Data, URLResponse) {
    (try JSONEncoder().encode(body), httpResponse(for: request, statusCode: 200))
}

private func httpResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
}
