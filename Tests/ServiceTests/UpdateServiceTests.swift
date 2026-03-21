import Testing
import Foundation
@testable import mrml

// MARK: - UpdateService Tests

@Suite("UpdateService Tests")
struct UpdateServiceTests {
    
    // MARK: - Version Comparison Tests
    
    @Test("Same version returns false")
    func sameVersionReturnsFalse() {
        let result = isNewerVersion("1.0.0", than: "1.0.0")
        #expect(result == false)
    }
    
    @Test("Higher major version returns true")
    func higherMajorVersionReturnsTrue() {
        let result = isNewerVersion("2.0.0", than: "1.0.0")
        #expect(result == true)
    }
    
    @Test("Lower major version returns false")
    func lowerMajorVersionReturnsFalse() {
        let result = isNewerVersion("1.0.0", than: "2.0.0")
        #expect(result == false)
    }
    
    @Test("Higher minor version returns true")
    func higherMinorVersionReturnsTrue() {
        let result = isNewerVersion("1.2.0", than: "1.1.0")
        #expect(result == true)
    }
    
    @Test("Lower minor version returns false")
    func lowerMinorVersionReturnsFalse() {
        let result = isNewerVersion("1.1.0", than: "1.2.0")
        #expect(result == false)
    }
    
    @Test("Higher patch version returns true")
    func higherPatchVersionReturnsTrue() {
        let result = isNewerVersion("1.0.2", than: "1.0.1")
        #expect(result == true)
    }
    
    @Test("Lower patch version returns false")
    func lowerPatchVersionReturnsFalse() {
        let result = isNewerVersion("1.0.1", than: "1.0.2")
        #expect(result == false)
    }
    
    @Test("Version with more parts is handled correctly")
    func versionWithMoreParts() {
        let result1 = isNewerVersion("1.0.0.1", than: "1.0.0")
        #expect(result1 == true)
        
        let result2 = isNewerVersion("1.0.0", than: "1.0.0.1")
        #expect(result2 == false)
    }
    
    @Test("Version with fewer parts is handled correctly")
    func versionWithFewerParts() {
        let result1 = isNewerVersion("2.0", than: "1.0.0")
        #expect(result1 == true)
        
        let result2 = isNewerVersion("1.0", than: "1.0.0")
        #expect(result2 == false)
    }
    
    @Test("Double-digit version numbers compare correctly")
    func doubleDigitVersions() {
        let result1 = isNewerVersion("1.10.0", than: "1.9.0")
        #expect(result1 == true)
        
        let result2 = isNewerVersion("1.9.0", than: "1.10.0")
        #expect(result2 == false)
        
        let result3 = isNewerVersion("10.0.0", than: "9.0.0")
        #expect(result3 == true)
    }
    
    @Test("Real-world version comparison: 2.2.3 vs 2.2.2")
    func realWorldVersionComparison() {
        let result = isNewerVersion("2.2.3", than: "2.2.2")
        #expect(result == true)
    }
    
    @Test("Real-world version comparison: 2.3.0 vs 2.2.3")
    func realWorldMinorBump() {
        let result = isNewerVersion("2.3.0", than: "2.2.3")
        #expect(result == true)
    }
    
    // MARK: - GitHubRelease Parsing Tests
    
    @Test("GitHubRelease decodes correctly")
    func gitHubReleaseDecodes() throws {
        let json = """
        {
            "tag_name": "v2.2.3",
            "html_url": "https://github.com/Skeptomenos/Murmeln/releases/tag/v2.2.3",
            "body": "## What's New\\n- Bug fixes"
        }
        """.data(using: .utf8)!
        
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        
        #expect(release.tagName == "v2.2.3")
        #expect(release.htmlURL == "https://github.com/Skeptomenos/Murmeln/releases/tag/v2.2.3")
        #expect(release.body == "## What's New\n- Bug fixes")
    }
    
    @Test("GitHubRelease handles nil body")
    func gitHubReleaseNilBody() throws {
        let json = """
        {
            "tag_name": "v1.0.0",
            "html_url": "https://github.com/example/repo/releases/tag/v1.0.0"
        }
        """.data(using: .utf8)!
        
        let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
        
        #expect(release.tagName == "v1.0.0")
        #expect(release.body == nil)
    }
    
    @Test("Version tag stripping removes 'v' prefix")
    func versionTagStripping() {
        let tagName = "v2.2.3"
        let cleanVersion = tagName.replacingOccurrences(of: "v", with: "")
        
        #expect(cleanVersion == "2.2.3")
    }
    
    @Test("Version tag without 'v' prefix is unchanged")
    func versionTagWithoutPrefix() {
        let tagName = "2.2.3"
        let cleanVersion = tagName.replacingOccurrences(of: "v", with: "")
        
        #expect(cleanVersion == "2.2.3")
    }
    
    // MARK: - Edge Cases
    
    @Test("Empty version strings handled")
    func emptyVersionStrings() {
        let result = isNewerVersion("", than: "")
        #expect(result == false)
    }
    
    @Test("Zero versions compare correctly")
    func zeroVersions() {
        let result1 = isNewerVersion("0.0.1", than: "0.0.0")
        #expect(result1 == true)
        
        let result2 = isNewerVersion("0.1.0", than: "0.0.9")
        #expect(result2 == true)
    }
    
    @Test("Large version numbers compare correctly")
    func largeVersionNumbers() {
        let result = isNewerVersion("100.200.300", than: "100.200.299")
        #expect(result == true)
    }
}

private func isNewerVersion(_ latest: String, than current: String) -> Bool {
    let latestParts = latest.split(separator: ".").compactMap { Int($0) }
    let currentParts = current.split(separator: ".").compactMap { Int($0) }
    
    for i in 0..<max(latestParts.count, currentParts.count) {
        let latestPart = i < latestParts.count ? latestParts[i] : 0
        let currentPart = i < currentParts.count ? currentParts[i] : 0
        
        if latestPart > currentPart { return true }
        if latestPart < currentPart { return false }
    }
    
    return false
}
