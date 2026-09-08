import Foundation

/// The clipboard state that Murmeln can observe after a paste attempt.
enum ClipboardDisposition: String, Codable, Sendable {
    case unchanged
    case restored
    case transcriptPreserved = "transcript_preserved"
    case externalWritePreserved = "external_write_preserved"
    case restoreFailed = "restore_failed"
}
