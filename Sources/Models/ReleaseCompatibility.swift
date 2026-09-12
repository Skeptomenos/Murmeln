import Foundation

/// Product-owned mapping from strict release versions to their minimum macOS.
struct ReleaseCompatibility: Sendable {
    private let macOS26Transition = [2, 6, 0]
    private let legacyMinimumOS = OperatingSystemVersion(
        majorVersion: 14,
        minorVersion: 0,
        patchVersion: 0
    )
    private let currentMinimumOS = OperatingSystemVersion(
        majorVersion: 26,
        minorVersion: 0,
        patchVersion: 0
    )

    func versionComponents(from rawVersion: String) -> [Int]? {
        let version = rawVersion.hasPrefix("v")
            ? String(rawVersion.dropFirst())
            : rawVersion
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }

        var result: [Int] = []
        for component in components {
            guard !component.isEmpty,
                  component.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  component == "0" || !component.hasPrefix("0"),
                  let value = Int(component)
            else { return nil }
            result.append(value)
        }
        return result
    }

    func normalizedVersion(from rawVersion: String) -> String? {
        versionComponents(from: rawVersion)?.map(String.init).joined(separator: ".")
    }

    func isCompatible(version: [Int], with operatingSystem: OperatingSystemVersion) -> Bool {
        let minimumOS = compare(version, macOS26Transition) == .orderedAscending
            ? legacyMinimumOS
            : currentMinimumOS
        return compare(operatingSystem, minimumOS) != .orderedAscending
    }

    func compare(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        for index in 0..<3 {
            if lhs[index] < rhs[index] { return .orderedAscending }
            if lhs[index] > rhs[index] { return .orderedDescending }
        }
        return .orderedSame
    }

    private func compare(
        _ lhs: OperatingSystemVersion,
        _ rhs: OperatingSystemVersion
    ) -> ComparisonResult {
        let lhsParts = [lhs.majorVersion, lhs.minorVersion, lhs.patchVersion]
        let rhsParts = [rhs.majorVersion, rhs.minorVersion, rhs.patchVersion]
        return compare(lhsParts, rhsParts)
    }
}
