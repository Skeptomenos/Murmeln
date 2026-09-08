import Foundation

/// What Murmeln can prove about one synthetic paste command attempt.
///
/// `.posted` means both key events were handed to macOS. It does not prove
/// that macOS accepted, queued, or delivered the command to a target app.
enum PasteCommandOutcome: Sendable, Equatable {
    case notAttempted
    case posted
    case blocked(PasteBlocker)

    var telemetryValue: String {
        switch self {
        case .notAttempted:
            "not_attempted"
        case .posted:
            "posted"
        case .blocked:
            "blocked"
        }
    }
}
