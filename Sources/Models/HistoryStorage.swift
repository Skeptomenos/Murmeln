import Foundation

/// Versioned storage format for history persistence.
struct HistoryStorage: Codable, Sendable {
    let version: Int
    let entries: [HistoryEntry]

    static let currentVersion = 1

    init(version: Int = currentVersion, entries: [HistoryEntry]) {
        self.version = version
        self.entries = entries
    }
}
