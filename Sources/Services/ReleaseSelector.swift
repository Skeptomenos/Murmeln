import Foundation

/// Selects the greatest strictly newer stable release that the current OS can run.
struct ReleaseSelector: Sendable {
    let currentOSVersion: OperatingSystemVersion
    private let compatibility = ReleaseCompatibility()

    func selectNewestCompatible(
        from releases: [GitHubRelease],
        currentVersion: String
    ) -> GitHubRelease? {
        guard let installed = compatibility.versionComponents(from: currentVersion) else {
            return nil
        }

        return releases.compactMap { release -> (version: [Int], release: GitHubRelease)? in
            guard release.draft == false,
                  release.prerelease == false,
                  let tagName = release.tagName,
                  let version = compatibility.versionComponents(from: tagName),
                  compatibility.compare(version, installed) == .orderedDescending,
                  compatibility.isCompatible(version: version, with: currentOSVersion),
                  trustedURL(for: release) != nil
            else { return nil }
            return (version, release)
        }
        .max { lhs, rhs in
            compatibility.compare(lhs.version, rhs.version) == .orderedAscending
        }?
        .release
    }

    func normalizedVersion(for release: GitHubRelease) -> String? {
        guard let tagName = release.tagName else { return nil }
        return compatibility.normalizedVersion(from: tagName)
    }

    func trustedURL(for release: GitHubRelease) -> URL? {
        guard let tagName = release.tagName,
              compatibility.versionComponents(from: tagName) != nil,
              let rawURL = release.htmlURL,
              let url = URL(string: rawURL),
              url.scheme == "https",
              url.host?.lowercased() == "github.com",
              url.port == nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path == "/Skeptomenos/Murmeln/releases/tag/\(tagName)"
        else { return nil }
        return url
    }
}
