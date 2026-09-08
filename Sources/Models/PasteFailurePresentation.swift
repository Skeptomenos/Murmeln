import Foundation

/// Attempt feedback never asserts current clipboard ownership or a disk save.
struct PasteFailurePresentation: Sendable, Equatable {
    enum RecoveryAction: String, Sendable, Equatable {
        case openHistory, copyAgain
    }
    let message: String
    let recoveryActions: [RecoveryAction]

    init(blocker: PasteBlocker, clipboardDisposition: ClipboardDisposition = .unchanged,
         pasteAttemptID: String? = nil) {
        let reason: String
        switch blocker {
        case .cancelled:
            reason = "Automatic paste stopped before the command was sent."
        case .secureInputActive:
            reason = "Automatic paste was blocked while Secure Input was active."
        case .postEventAccessDenied:
            reason = "Automatic paste was blocked because paste permission is denied."
        case .keyEventCreationFailed:
            reason = "Murmeln could not create the paste command."
        case .clipboardWriteFailed:
            reason = "Murmeln could not copy the transcript."
        case .clipboardChanged:
            reason = "The clipboard changed before paste. No paste command was sent."
        case .clipboardSnapshotUnavailable:
            reason = "Murmeln could not safely preserve the previous clipboard. Automatic paste was skipped."
        }
        let restoration = clipboardDisposition == .restoreFailed
            ? " The previous clipboard could not be restored." : ""
        message = reason + restoration + " Your text is available to copy."
        recoveryActions = [.copyAgain, .openHistory]
    }
}
