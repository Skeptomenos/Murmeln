enum ClipboardCopyOutcome: Sendable, Equatable {
    case copied, busy, failed, restorationFailed

    var message: String {
        switch self {
        case .copied: "Copied. Return to your text field and press Cmd+V."
        case .busy: "Another paste is in progress. Click Copy again when it finishes."
        case .failed: "Copy failed. Your text remains available. Try Copy again."
        case .restorationFailed: "Copy failed, and the previous clipboard could not be restored. Your text remains available."
        }
    }
}
