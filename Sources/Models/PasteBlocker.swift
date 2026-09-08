import Foundation

/// A detectable reason Murmeln cannot post a synthetic Cmd+V.
///
/// Event posting does not acknowledge target delivery. Tier 2 dogfood remains
/// the authority for whether a destination received the clipboard contents.
enum PasteBlocker: String, Codable, Sendable {
    case clipboardWriteFailed = "clipboard_write_failed"
    case postEventAccessDenied = "post_event_access_denied"
    case secureInputActive = "secure_input_active"
    case keyEventCreationFailed = "key_event_creation_failed"
    case clipboardChanged = "clipboard_changed"
    case clipboardSnapshotUnavailable = "clipboard_snapshot_unavailable"
    case cancelled = "cancelled"
}
