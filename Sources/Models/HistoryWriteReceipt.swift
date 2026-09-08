import Foundation

/// One complete disk snapshot, never only its newest entry.
struct HistoryWriteReceipt: Sendable {
    let revision: Int
    let storage: HistoryStorage
    let succeeded: Bool
}
