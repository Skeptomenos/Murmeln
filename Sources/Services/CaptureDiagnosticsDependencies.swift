import Foundation
import OSLog

/// Sendable file-system seams used by the diagnostics actor.
///
/// The actor still owns ordering. These closures make serialization, rotation,
/// append, and safe fallback behavior independently falsifiable.
struct CaptureDiagnosticsDependencies: Sendable {
    struct OperationalPersistenceFailure: Sendable, Equatable {
        let event: String
        let level: String
        let pasteAttemptID: String
        let blocker: PasteBlocker?

        init(pasteAttemptID: String, blocker: PasteBlocker?) {
            self.event = "paste_diagnostics_persistence_failed"
            self.level = "warning"
            self.pasteAttemptID = pasteAttemptID
            self.blocker = blocker
        }
    }

    let encodeOperationalRecord: @Sendable (PasteOperationalRecord) -> Data?
    let rotateLogIfNeeded: @Sendable (URL, Int, Int) -> Bool
    let appendLine: @Sendable (Data, URL) -> Bool
    let reportOperationalPersistenceFailure: @Sendable (OperationalPersistenceFailure) async -> Void

    init(
        encodeOperationalRecord: @escaping @Sendable (PasteOperationalRecord) -> Data? = Self.encode,
        rotateLogIfNeeded: @escaping @Sendable (URL, Int, Int) -> Bool = Self.rotate,
        appendLine: @escaping @Sendable (Data, URL) -> Bool = Self.append,
        reportOperationalPersistenceFailure: @escaping @Sendable (OperationalPersistenceFailure) async -> Void = Self.report
    ) {
        self.encodeOperationalRecord = encodeOperationalRecord
        self.rotateLogIfNeeded = rotateLogIfNeeded
        self.appendLine = appendLine
        self.reportOperationalPersistenceFailure = reportOperationalPersistenceFailure
    }

    static let live = CaptureDiagnosticsDependencies()

    private static func encode(_ record: PasteOperationalRecord) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(record)
    }

    private static func rotate(fileURL: URL, maxLogSizeBytes: Int, incomingSizeBytes: Int) -> Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int,
              size + incomingSizeBytes > maxLogSizeBytes else {
            return true
        }

        let rotatedURL = fileURL.appendingPathExtension("1")
        do {
            if FileManager.default.fileExists(atPath: rotatedURL.path) {
                try FileManager.default.removeItem(at: rotatedURL)
            }
            try FileManager.default.moveItem(at: fileURL, to: rotatedURL)
            return true
        } catch {
            return false
        }
    }

    private static func append(data: Data, fileURL: URL) -> Bool {
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            return FileManager.default.createFile(atPath: fileURL.path, contents: line)
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    private static func report(_ failure: OperationalPersistenceFailure) async {
        let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "CaptureDiagnostics")
        let blocker = failure.blocker?.rawValue ?? "none"
        logger.warning(
            "event=\(failure.event, privacy: .public) level=\(failure.level, privacy: .public) paste_attempt_id=\(failure.pasteAttemptID, privacy: .public) blocker=\(blocker, privacy: .public)"
        )
    }
}
