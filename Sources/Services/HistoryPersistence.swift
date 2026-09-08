import Foundation
import os.log

private let historyPersistenceLogger = Logger(
    subsystem: AppIdentity.loggerSubsystem,
    category: "HistoryPersistence"
)

@MainActor
final class HistoryPersistence {
    private let fileURL: URL
    private let writer: @Sendable (Data, URL) async throws -> Void
    private var tail: Task<Void, Never>?
    private var scheduledRevision = 0
    private var completedRevision = 0

    init(
        fileURL: URL,
        writer: @escaping @Sendable (Data, URL) async throws -> Void = HistoryPersistence.writeAtomically
    ) {
        self.fileURL = fileURL
        self.writer = writer
    }

    @discardableResult
    func enqueue(
        _ storage: HistoryStorage,
        completion: @escaping @MainActor (HistoryWriteReceipt) -> Void = { _ in }
    ) -> Int {
        scheduledRevision += 1
        let revision = scheduledRevision
        let predecessor = tail
        let writer = self.writer
        let fileURL = self.fileURL

        tail = Task { @MainActor [weak self] in
            await predecessor?.value
            defer {
                self?.completedRevision = max(self?.completedRevision ?? 0, revision)
            }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(storage)
                try await writer(data, fileURL)
                completion(HistoryWriteReceipt(revision: revision, storage: storage, succeeded: true))
                #if DEBUG
                historyPersistenceLogger.debug("History saved: \(storage.entries.count) entries")
                #endif
            } catch {
                historyPersistenceLogger.error("History persistence write failed")
                completion(HistoryWriteReceipt(revision: revision, storage: storage, succeeded: false))
            }
        }
        return revision
    }

    func flush() async {
        while completedRevision < scheduledRevision {
            await tail?.value
        }
    }

    private nonisolated static func writeAtomically(_ data: Data, to fileURL: URL) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
