import Foundation

/// Privacy-allowlisted evidence for one non-empty paste attempt.
///
/// The stored fields are deliberately closed. Transcript and clipboard data
/// cannot enter this record through metadata or an open dictionary.
struct PasteOperationalRecord: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let event: String
    let level: String
    let timestamp: String
    let appVersion: String
    let appBuild: String
    let appCodeHash: String?
    let captureID: String
    let pasteAttemptID: String
    let commandOutcome: String
    let clipboardDisposition: ClipboardDisposition
    let blocker: PasteBlocker?
    let postAccessState: Bool?
    let secureInputState: Bool?
    let elapsedMilliseconds: UInt64
    let decision: PasteDecisionDiagnostics?

    init?(
        timestamp: String,
        appVersion: String,
        appBuild: String,
        appCodeHash: String? = nil,
        captureID: String,
        timing: PasteTiming
    ) {
        let level: String
        let commandOutcome: String
        let blocker: PasteBlocker?

        switch timing.commandOutcome {
        case .notAttempted:
            return nil
        case .posted:
            level = "info"
            commandOutcome = "posted"
            blocker = nil
        case .blocked(let detectedBlocker):
            level = "warning"
            commandOutcome = "blocked"
            blocker = detectedBlocker
        }

        guard let pasteAttemptID = timing.pasteAttemptID else {
            return nil
        }

        guard Self.validCodeHash(appCodeHash), Self.validDecision(timing.decision, outcome: commandOutcome, blocker: blocker) else { return nil }
        self.schemaVersion = 2
        self.event = "paste_attempt"
        self.level = level
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.appCodeHash = appCodeHash
        self.captureID = captureID
        self.pasteAttemptID = pasteAttemptID
        self.commandOutcome = commandOutcome
        self.clipboardDisposition = timing.clipboardDisposition
        self.blocker = blocker
        self.postAccessState = timing.postAccessState
        self.secureInputState = timing.secureInputState
        self.elapsedMilliseconds = timing.totalElapsedMs
        self.decision = timing.decision
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case event
        case level
        case timestamp
        case appVersion = "app_version"
        case appBuild = "app_build"
        case appCodeHash = "app_code_hash"
        case captureID = "capture_id"
        case pasteAttemptID = "paste_attempt_id"
        case commandOutcome = "command_outcome"
        case clipboardDisposition = "clipboard_disposition"
        case blocker
        case postAccessState = "post_access_state"
        case secureInputState = "secure_input_state"
        case elapsedMilliseconds = "elapsed_ms"
        case decisionStage = "decision_stage"
        case decisionReason = "decision_reason"
        case targetPolicy = "target_policy"
        case targetInvalidation = "target_invalidation"
        case modifierFlagsBefore = "modifier_flags_before"
        case modifierFlagsAtDecision = "modifier_flags_at_decision"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(event, forKey: .event)
        try container.encode(level, forKey: .level)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(appBuild, forKey: .appBuild)
        try container.encode(captureID, forKey: .captureID)
        try container.encode(pasteAttemptID, forKey: .pasteAttemptID)
        try container.encode(commandOutcome, forKey: .commandOutcome)
        try container.encode(clipboardDisposition, forKey: .clipboardDisposition)
        if let blocker {
            try container.encode(blocker, forKey: .blocker)
        } else {
            try container.encodeNil(forKey: .blocker)
        }
        if let postAccessState {
            try container.encode(postAccessState, forKey: .postAccessState)
        } else {
            try container.encodeNil(forKey: .postAccessState)
        }
        if let secureInputState {
            try container.encode(secureInputState, forKey: .secureInputState)
        } else {
            try container.encodeNil(forKey: .secureInputState)
        }
        try container.encode(elapsedMilliseconds, forKey: .elapsedMilliseconds)
        if schemaVersion == 2 {
            try container.encode(appCodeHash, forKey: .appCodeHash)
            try container.encode(decision?.stage, forKey: .decisionStage)
            try container.encode(decision?.reason, forKey: .decisionReason)
            try container.encode(decision?.targetPolicy, forKey: .targetPolicy)
            try container.encode(decision?.targetInvalidation, forKey: .targetInvalidation)
            try container.encode(decision?.modifiers?.before, forKey: .modifierFlagsBefore)
            try container.encode(decision?.modifiers?.atDecision, forKey: .modifierFlagsAtDecision)
        }
    }

    init(from decoder: Decoder) throws {
        let allFields = try decoder.container(keyedBy: FieldKey.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let newFields: Set<CodingKeys> = [.appCodeHash, .decisionStage, .decisionReason, .targetPolicy, .targetInvalidation, .modifierFlagsBefore, .modifierFlagsAtDecision]
        let allowed = Set(CodingKeys.allCases.filter { schemaVersion == 2 || !newFields.contains($0) }.map(\.rawValue))
        guard allFields.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "Unexpected paste operational field"))
        }
        let event = try container.decode(String.self, forKey: .event)
        let level = try container.decode(String.self, forKey: .level)
        let commandOutcome = try container.decode(String.self, forKey: .commandOutcome)
        let blocker = try container.decodeIfPresent(PasteBlocker.self, forKey: .blocker)

        guard (schemaVersion == 1 || schemaVersion == 2),
              event == "paste_attempt",
              (level == "info" || level == "warning"),
              (commandOutcome == "posted" || commandOutcome == "blocked"),
              (commandOutcome == "posted"
                ? level == "info" && blocker == nil
                : level == "warning" && blocker != nil) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid paste operational record invariant")
            )
        }

        self.schemaVersion = schemaVersion
        self.event = event
        self.level = level
        self.timestamp = try container.decode(String.self, forKey: .timestamp)
        self.appVersion = try container.decode(String.self, forKey: .appVersion)
        self.appBuild = try container.decode(String.self, forKey: .appBuild)
        if schemaVersion == 2 {
            self.appCodeHash = try container.decode(String?.self, forKey: .appCodeHash)
            let stage = try container.decode(PasteDecisionStage?.self, forKey: .decisionStage)
            let reason = try container.decode(PasteDecisionReason?.self, forKey: .decisionReason)
            let policy = try container.decode(PasteTargetPolicy?.self, forKey: .targetPolicy)
            let invalidation = try container.decode(PasteTargetInvalidationReason?.self, forKey: .targetInvalidation)
            let flagsBefore = try container.decode(UInt64?.self, forKey: .modifierFlagsBefore)
            let flagsAtDecision = try container.decode(UInt64?.self, forKey: .modifierFlagsAtDecision)
            guard (flagsBefore == nil) == (flagsAtDecision == nil) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Incomplete modifier observation"))
            }
            let modifiers = flagsBefore.flatMap { before in flagsAtDecision.map { PasteModifierObservation(before: before, atDecision: $0) } }
            if let stage, let reason, let policy {
                self.decision = PasteDecisionDiagnostics(stage: stage, reason: reason, targetPolicy: policy, targetInvalidation: invalidation, modifiers: modifiers)
            } else if stage == nil && reason == nil && policy == nil && invalidation == nil && modifiers == nil {
                self.decision = nil
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Incomplete paste decision"))
            }
            guard Self.validCodeHash(appCodeHash), Self.validDecision(decision, outcome: commandOutcome, blocker: blocker) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid paste decision or code hash"))
            }
        } else {
            self.appCodeHash = nil
            self.decision = nil
        }
        self.captureID = try container.decode(String.self, forKey: .captureID)
        self.pasteAttemptID = try container.decode(String.self, forKey: .pasteAttemptID)
        self.commandOutcome = commandOutcome
        self.clipboardDisposition = try container.decode(ClipboardDisposition.self, forKey: .clipboardDisposition)
        self.blocker = blocker
        self.postAccessState = try container.decodeIfPresent(Bool.self, forKey: .postAccessState)
        self.secureInputState = try container.decodeIfPresent(Bool.self, forKey: .secureInputState)
        self.elapsedMilliseconds = try container.decode(UInt64.self, forKey: .elapsedMilliseconds)
    }

    private static func validCodeHash(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.utf8.count == 40 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func validDecision(_ decision: PasteDecisionDiagnostics?, outcome: String, blocker: PasteBlocker?) -> Bool {
        guard let decision else { return true }
        if outcome == "posted" {
            return decision.stage == .posted && decision.reason == .commandPosted && decision.targetInvalidation == nil
        }
        guard decision.stage != .posted, decision.reason != .commandPosted,
              (decision.targetInvalidation != nil) == (decision.reason == .targetInvalid) else { return false }
        let stages: Set<PasteDecisionStage>
        switch decision.reason {
        case .transactionBusy: stages = [.admission]
        case .targetInvalid: stages = [.initialPreflight, .beforeWrite, .beforePost]
        case .modifiersHeld: stages = [.initialPreflight]
        case .modifiersChanged: stages = [.beforeWrite, .beforePost]
        case .taskCancelled: stages = [.admission, .initialPreflight, .settle, .beforePost]
        case .settleFailed: stages = [.settle]
        case .postAccessDenied, .secureInputActive: stages = [.initialPreflight, .beforePost]
        case .clipboardSnapshotUnavailable: stages = [.beforeWrite]
        case .clipboardChanged: stages = [.beforeWrite, .beforePost]
        case .clipboardWriteFailed: stages = [.clipboardWrite]
        case .eventCreationFailed: stages = [.beforePost]
        case .commandPosted: return false
        }
        guard stages.contains(decision.stage) else { return false }
        switch decision.reason {
        case .transactionBusy, .targetInvalid, .modifiersHeld, .modifiersChanged, .taskCancelled, .settleFailed: return blocker == .cancelled
        case .postAccessDenied: return blocker == .postEventAccessDenied
        case .secureInputActive: return blocker == .secureInputActive
        case .clipboardSnapshotUnavailable: return blocker == .clipboardSnapshotUnavailable
        case .clipboardChanged: return blocker == .clipboardChanged
        case .clipboardWriteFailed: return blocker == .clipboardWriteFailed
        case .eventCreationFailed: return blocker == .keyEventCreationFailed
        case .commandPosted: return false
        }
    }

    private struct FieldKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
