import Foundation

enum PasteTargetPolicy: String, Codable, Sendable {
    case legacy
    case capturedUnknown = "captured_unknown"
    case capturedTextEdit = "captured_textedit"
    case capturedNotion = "captured_notion"
    case unverifiedNotion = "unverified_notion"
    case diagnostic
}

enum PasteTargetInvalidationReason: String, Codable, Sendable {
    case initialCaptureUnverifiable = "initial_capture_unverifiable"
    case focusChanged = "focus_changed"
    case caretChanged = "caret_changed"
    case modifiersHeld = "modifiers_held"
    case accessibilityUnavailable = "accessibility_unavailable"
    case structureUnverifiable = "structure_unverifiable"
    case inspectionTimedOut = "inspection_timed_out"
    case metadataUnavailable = "metadata_unavailable"
    case unsupportedStructure = "unsupported_structure"
    case structureChanged = "structure_changed"
    case unknownInvalid = "unknown_invalid"
}

enum PasteDecisionStage: String, Codable, Sendable {
    case admission
    case initialPreflight = "initial_preflight"
    case beforeWrite = "before_write"
    case clipboardWrite = "clipboard_write"
    case settle
    case beforePost = "before_post"
    case posted
}

enum PasteDecisionReason: String, Codable, Sendable {
    case transactionBusy = "transaction_busy"
    case targetInvalid = "target_invalid"
    case modifiersHeld = "modifiers_held"
    case modifiersChanged = "modifiers_changed"
    case taskCancelled = "task_cancelled"
    case settleFailed = "settle_failed"
    case postAccessDenied = "post_access_denied"
    case secureInputActive = "secure_input_active"
    case clipboardSnapshotUnavailable = "clipboard_snapshot_unavailable"
    case clipboardChanged = "clipboard_changed"
    case clipboardWriteFailed = "clipboard_write_failed"
    case eventCreationFailed = "event_creation_failed"
    case commandPosted = "command_posted"
}

struct PasteDecisionDiagnostics: Sendable, Equatable {
    let stage: PasteDecisionStage
    let reason: PasteDecisionReason
    let targetPolicy: PasteTargetPolicy
    var targetInvalidation: PasteTargetInvalidationReason? = nil
    var modifiers: PasteModifierObservation? = nil
}

struct PasteModifierObservation: Sendable, Equatable {
    let before: UInt64
    let atDecision: UInt64
}

struct PasteTiming: Sendable {
    let commandOutcome: PasteCommandOutcome
    let clipboardDisposition: ClipboardDisposition
    let commandSentElapsedMs: UInt64?
    let totalElapsedMs: UInt64
    let pasteAttemptID: String?
    let postAccessState: Bool?
    let secureInputState: Bool?
    let decision: PasteDecisionDiagnostics?

    init(
        commandOutcome: PasteCommandOutcome,
        clipboardDisposition: ClipboardDisposition,
        commandSentElapsedMs: UInt64?,
        totalElapsedMs: UInt64,
        pasteAttemptID: String? = nil,
        postAccessState: Bool? = nil,
        secureInputState: Bool? = nil,
        decision: PasteDecisionDiagnostics? = nil
    ) {
        self.commandOutcome = commandOutcome
        self.clipboardDisposition = clipboardDisposition
        self.commandSentElapsedMs = commandSentElapsedMs
        self.totalElapsedMs = totalElapsedMs
        self.pasteAttemptID = pasteAttemptID
        self.postAccessState = postAccessState
        self.secureInputState = secureInputState
        self.decision = decision
    }
}
