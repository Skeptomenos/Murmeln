import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
enum KeyboardLayoutResolver {
    private static var cache: [String: [Character: CGKeyCode]] = [:]
    private static var currentLayoutID: String?

    static func keyCode(for character: Character) -> CGKeyCode? {
        let layoutID = getCurrentLayoutID()

        if layoutID == currentLayoutID, let cached = cache[layoutID]?[character] {
            return cached
        }

        if layoutID != currentLayoutID {
            cache.removeAll()
            currentLayoutID = layoutID
        }

        guard let keyCode = resolveKeyCode(for: character) else {
            return nil
        }

        if cache[layoutID] == nil {
            cache[layoutID] = [:]
        }
        cache[layoutID]?[character] = keyCode

        return keyCode
    }

    static func invalidateCache() {
        cache.removeAll()
        currentLayoutID = nil
    }

    private static func getCurrentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id
        }
        return "unknown"
    }

    private static func resolveKeyCode(for character: Character) -> CGKeyCode? {
        var currentKeyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)

        if rawLayoutData == nil {
            currentKeyboard = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeUnretainedValue()
            rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
        }

        guard let layoutData = rawLayoutData else {
            #if DEBUG
            print("⚠️ KeyboardLayoutResolver: Could not get keyboard layout data")
            #endif
            return nil
        }

        let cfData = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        let targetString = String(character).lowercased()

        for keyCode in UInt16(0)...UInt16(127) {
            if let translated = translate(keyCode: keyCode, layoutData: cfData),
               translated.lowercased() == targetString {
                return CGKeyCode(keyCode)
            }
        }

        #if DEBUG
        print("⚠️ KeyboardLayoutResolver: Could not find key code for '\(character)'")
        #endif
        return nil
    }

    private static func translate(keyCode: UInt16, layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0

        let status = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let layoutPtr = pointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(kUCKeyTranslateNoDeadKeysBit)
            }

            return UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0, // No modifiers
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )
        }

        guard status == noErr, actualLength > 0 else {
            return nil
        }

        return String(utf16CodeUnits: chars, count: actualLength)
    }
}

@MainActor
final class PasteService {
    static let shared = PasteService()

    private let dependencies: PasteServiceDependencies
    private let transactionGate: PasteTransactionGate

    init(
        dependencies: PasteServiceDependencies = .live,
        transactionGate: PasteTransactionGate = PasteTransactionGate()
    ) {
        self.dependencies = dependencies
        self.transactionGate = transactionGate
    }

    nonisolated static func preflightBlocker(postEventAccessAllowed: Bool, secureInputActive: Bool) -> PasteBlocker? {
        if !postEventAccessAllowed { return .postEventAccessDenied }
        if secureInputActive { return .secureInputActive }
        return nil
    }

    nonisolated static func shouldRestoreClipboard(changeCountAtWrite: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount == changeCountAtWrite
    }

    private nonisolated static func keyboardFlagsMatch(_ current: CGEventFlags, _ baseline: CGEventFlags) -> Bool {
        // This flag describes mouse/pen movement coalescing, not keyboard state.
        current.subtracting(.maskNonCoalesced) == baseline.subtracting(.maskNonCoalesced)
    }

    func copyToClipboardForRecovery(text: String) -> Bool { copyResult(text: text) == .copied }

    func copyResult(text: String) -> ClipboardCopyOutcome {
        guard transactionGate.tryAcquire() else { return .busy }
        defer { transactionGate.release() }
        let board = dependencies.pasteboard
        let snapshot = dependencies.captureClipboard(board)
        let canRestore = snapshot.isAvailable && board.changeCount == snapshot.generation
        let generation = board.clearContents()
        guard dependencies.setPasteboardString(text, board) else {
            if board.changeCount == generation {
                guard canRestore, dependencies.restoreClipboard(snapshot, board) == .restored else { return .restorationFailed }
            }
            return .failed
        }
        return .copied
    }

    func pasteAndRestore(text: String, captureID: String? = nil) async throws -> PasteTiming {
        try await pasteAndRestore(text: text, captureID: captureID, target: nil)
    }

    func pasteAndRestore(
        text: String, captureID: String? = nil, target: (any PasteTargetChecking)?
    ) async throws -> PasteTiming {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            #if DEBUG
            print("⚠️ Skipping paste: text is empty")
            #endif
            return PasteTiming(
                commandOutcome: .notAttempted,
                clipboardDisposition: .unchanged,
                commandSentElapsedMs: nil,
                totalElapsedMs: 0
            )
        }

        let resolvedCaptureID = captureID ?? dependencies.makeCaptureID()
        let pasteAttemptID = dependencies.makePasteAttemptID()
        var acquired = false
        do {
            if target != nil {
                try Task.checkCancellation()
                guard transactionGate.tryAcquire() else {
                    let timing = failPaste(.cancelled, pasteStartNs: dependencies.nowNanoseconds(),
                        clipboardDisposition: .unchanged, pasteAttemptID: pasteAttemptID,
                        postAccessState: dependencies.preflightPostEventAccess(),
                        secureInputState: dependencies.secureInputActive(),
                        decision: .init(stage: .admission, reason: .transactionBusy, targetPolicy: target?.diagnosticPolicy ?? .legacy))
                    await recordPasteAttempt(captureID: resolvedCaptureID, timing: timing)
                    return timing
                }
            } else {
                try await transactionGate.acquire()
            }
            acquired = true
            let timing = try await performPasteTransaction(text: text, pasteAttemptID: pasteAttemptID, target: target)
            transactionGate.release()
            await recordPasteAttempt(captureID: resolvedCaptureID, timing: timing)
            return timing
        } catch {
            // acquire() releases its own cancelled handoff. Release only ownership returned to us.
            if acquired { transactionGate.release() }
            if error is CancellationError {
                let timing = failPaste(.cancelled, pasteStartNs: dependencies.nowNanoseconds(),
                    clipboardDisposition: .unchanged, pasteAttemptID: pasteAttemptID,
                    postAccessState: nil, secureInputState: nil,
                    decision: .init(stage: acquired ? .initialPreflight : .admission, reason: .taskCancelled,
                                    targetPolicy: target?.diagnosticPolicy ?? .legacy))
                await recordPasteAttempt(captureID: resolvedCaptureID, timing: timing)
            }
            throw error
        }
    }

    func runDevDeliveryDiagnostic(
        target: any DevDeliveryDiagnosticTargetChecking,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> DevDeliveryDiagnosticResult {
        guard DevDeliveryDiagnostic.isEnabled(bundleIdentifier: bundleIdentifier, environment: environment) else {
            return .refused(.disabled)
        }
        guard !Task.isCancelled else { return .refused(.cancelled) }
        guard target.isStillValid() else { return .refused(.invalidTarget) }
        guard transactionGate.tryAcquire() else { return .refused(.busy) }
        defer { transactionGate.release() }
        do {
            let timing = try await performPasteTransaction(
                text: DevDeliveryDiagnostic.fixedText, pasteAttemptID: dependencies.makePasteAttemptID(),
                diagnosticTarget: target)
            return .completed(timing)
        } catch {
            return .refused(.cancelled)
        }
    }

    private func performPasteTransaction(
        text: String, pasteAttemptID: String,
        target: (any PasteTargetChecking)? = nil,
        diagnosticTarget: (any DevDeliveryDiagnosticTargetChecking)? = nil
    ) async throws -> PasteTiming {

        let pasteStartNs = dependencies.nowNanoseconds()

        let pasteboard = dependencies.pasteboard
        let targetPolicy = target?.diagnosticPolicy ?? (diagnosticTarget == nil ? .legacy : .diagnostic)
        func decision(_ stage: PasteDecisionStage, _ reason: PasteDecisionReason,
                      invalidation: PasteTargetInvalidationReason? = nil,
                      modifiers: PasteModifierObservation? = nil) -> PasteDecisionDiagnostics {
            .init(stage: stage, reason: reason, targetPolicy: targetPolicy,
                  targetInvalidation: invalidation, modifiers: modifiers)
        }

        try Task.checkCancellation()
        let initialInvalidation = target?.invalidationReason()
        let initialTargetValid = initialInvalidation == nil
        let access = dependencies.preflightPostEventAccess()
        let secure = dependencies.secureInputActive()
        if let failure = transactionBlocker(access: access, secure: secure, target: target,
            targetStillValid: initialTargetValid, diagnosticTarget: diagnosticTarget) {
            return failPaste(failure.blocker, pasteStartNs: pasteStartNs, clipboardDisposition: .unchanged,
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.initialPreflight, failure.reason, invalidation: failure.reason == .targetInvalid ? initialInvalidation : nil))
        }
        let baselineModifierFlags = dependencies.readModifierFlags()
        guard PasteServiceDependencies.modifiersPermitPaste(baselineModifierFlags) else {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs, clipboardDisposition: .unchanged,
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.initialPreflight, .modifiersHeld,
                    modifiers: .init(before: baselineModifierFlags.rawValue, atDecision: baselineModifierFlags.rawValue)))
        }
        let clipboardSnapshot = dependencies.captureClipboard(pasteboard)
        guard clipboardSnapshot.isAvailable, pasteboard.changeCount == clipboardSnapshot.generation else {
            return failPaste(.clipboardSnapshotUnavailable, pasteStartNs: pasteStartNs,
                clipboardDisposition: .unchanged, pasteAttemptID: pasteAttemptID,
                postAccessState: access, secureInputState: secure,
                decision: decision(.beforeWrite, .clipboardSnapshotUnavailable))
        }

        let beforeWriteInvalidation = target?.invalidationReason()
        if beforeWriteInvalidation != nil || !(diagnosticTarget?.isStillValid() ?? true) {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs, clipboardDisposition: .unchanged,
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.beforeWrite, .targetInvalid, invalidation: beforeWriteInvalidation ?? .unknownInvalid))
        }
        let beforeWriteModifierFlags = dependencies.readModifierFlags()
        if !Self.keyboardFlagsMatch(beforeWriteModifierFlags, baselineModifierFlags) {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs, clipboardDisposition: .unchanged,
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.beforeWrite, .modifiersChanged,
                    modifiers: .init(before: baselineModifierFlags.rawValue, atDecision: beforeWriteModifierFlags.rawValue)))
        }
        guard pasteboard.changeCount == clipboardSnapshot.generation else {
            return failPaste(.clipboardChanged, pasteStartNs: pasteStartNs, clipboardDisposition: .unchanged,
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.beforeWrite, .clipboardChanged))
        }

        let changeCountAfterClear = pasteboard.clearContents()
        let wroteTranscript = dependencies.setPasteboardString(text, pasteboard)
        if !wroteTranscript {
            let clipboardDisposition: ClipboardDisposition
            if Self.shouldRestoreClipboard(
                changeCountAtWrite: changeCountAfterClear,
                currentChangeCount: pasteboard.changeCount
            ) {
                clipboardDisposition = dependencies.restoreClipboard(clipboardSnapshot, pasteboard)
            } else {
                clipboardDisposition = .externalWritePreserved
            }
            return failPaste(
                .clipboardWriteFailed,
                pasteStartNs: pasteStartNs,
                clipboardDisposition: clipboardDisposition,
                pasteAttemptID: pasteAttemptID,
                postAccessState: access,
                secureInputState: secure,
                decision: decision(.clipboardWrite, .clipboardWriteFailed)
            )
        }
        let changeCountAtWrite = changeCountAfterClear

        do {
            try await dependencies.sleep(.milliseconds(100))
            try Task.checkCancellation()
        } catch {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID, postAccessState: access, secureInputState: secure,
                decision: decision(.settle, error is CancellationError ? .taskCancelled : .settleFailed))
        }
        guard let pasteEvents = dependencies.makePasteEvents(baselineModifierFlags) else {
            return failPaste(
                .keyEventCreationFailed,
                pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID,
                postAccessState: access,
                secureInputState: secure,
                decision: decision(.beforePost, .eventCreationFailed)
            )
        }
        let finalInvalidation = target?.invalidationReason()
        let targetStillValid = finalInvalidation == nil && (diagnosticTarget?.isStillValid() ?? true)
        let finalAccess = dependencies.preflightPostEventAccess()
        let finalSecure = dependencies.secureInputActive()
        if let failure = transactionBlocker(access: finalAccess, secure: finalSecure, target: target,
            targetStillValid: targetStillValid, diagnosticTarget: diagnosticTarget) {
            return failPaste(failure.blocker, pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID, postAccessState: finalAccess, secureInputState: finalSecure,
                decision: decision(.beforePost, failure.reason, invalidation: failure.reason == .targetInvalid ? finalInvalidation : nil))
        }
        guard targetStillValid else {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID, postAccessState: finalAccess, secureInputState: finalSecure,
                decision: decision(.beforePost, .targetInvalid, invalidation: finalInvalidation ?? .unknownInvalid))
        }
        let finalModifierFlags = dependencies.readModifierFlags()
        let modifierObservation = PasteModifierObservation(before: baselineModifierFlags.rawValue, atDecision: finalModifierFlags.rawValue)
        guard Self.keyboardFlagsMatch(finalModifierFlags, baselineModifierFlags) else {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID, postAccessState: finalAccess, secureInputState: finalSecure,
                decision: decision(.beforePost, .modifiersChanged, modifiers: modifierObservation))
        }
        guard pasteboard.changeCount == changeCountAtWrite else {
            return failPaste(.clipboardChanged, pasteStartNs: pasteStartNs,
                clipboardDisposition: .externalWritePreserved, pasteAttemptID: pasteAttemptID,
                postAccessState: finalAccess, secureInputState: finalSecure,
                decision: decision(.beforePost, .clipboardChanged, modifiers: modifierObservation))
        }
        do {
            try Task.checkCancellation()
        } catch {
            return failPaste(.cancelled, pasteStartNs: pasteStartNs,
                clipboardDisposition: restoreClipboardAfterTransaction(clipboardSnapshot,
                    pasteboard: pasteboard, changeCountAtWrite: changeCountAtWrite),
                pasteAttemptID: pasteAttemptID, postAccessState: finalAccess, secureInputState: finalSecure,
                decision: decision(.beforePost, .taskCancelled, modifiers: modifierObservation))
        }
        for event in pasteEvents.ordered {
            dependencies.postEvent(event)
        }
        let pasteTriggeredNs = dependencies.nowNanoseconds()
        let commandElapsedMs = (pasteTriggeredNs - pasteStartNs) / 1_000_000
        try? await dependencies.sleep(.milliseconds(200))
        let clipboardDisposition = restoreClipboardAfterTransaction(
            clipboardSnapshot,
            pasteboard: pasteboard,
            changeCountAtWrite: changeCountAtWrite
        )

        let pasteEndNs = dependencies.nowNanoseconds()
        let totalElapsedMs = (pasteEndNs - pasteStartNs) / 1_000_000
        return PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: clipboardDisposition,
            commandSentElapsedMs: commandElapsedMs,
            totalElapsedMs: totalElapsedMs,
            pasteAttemptID: pasteAttemptID,
            postAccessState: finalAccess,
            secureInputState: finalSecure,
            decision: decision(.posted, .commandPosted, modifiers: modifierObservation)
        )
    }

    private func transactionBlocker(
        access: Bool, secure: Bool, target: (any PasteTargetChecking)?, targetStillValid: Bool,
        diagnosticTarget: (any DevDeliveryDiagnosticTargetChecking)?
    ) -> (blocker: PasteBlocker, reason: PasteDecisionReason)? {
        if !access { return (.postEventAccessDenied, .postAccessDenied) }
        if target != nil && !targetStillValid { return (.cancelled, .targetInvalid) }
        if secure && target == nil && diagnosticTarget == nil { return (.secureInputActive, .secureInputActive) }
        return nil
    }

    private func restoreClipboardAfterTransaction(
        _ snapshot: ClipboardSnapshot,
        pasteboard: NSPasteboard,
        changeCountAtWrite: Int
    ) -> ClipboardDisposition {
        guard Self.shouldRestoreClipboard(
            changeCountAtWrite: changeCountAtWrite,
            currentChangeCount: pasteboard.changeCount
        ) else {
            #if DEBUG
            print("📋 Restore skipped — clipboard changed during paste window")
            #endif
            return .externalWritePreserved
        }

        let disposition = dependencies.restoreClipboard(snapshot, pasteboard)
        #if DEBUG
        if disposition == .restored {
            print("📋 Restored \(snapshot.itemCount) clipboard item(s)")
        } else {
            print("⚠️ Clipboard restore failed after paste transaction")
        }
        #endif
        return disposition
    }

    private func failPaste(
        _ blocker: PasteBlocker,
        pasteStartNs: UInt64,
        clipboardDisposition: ClipboardDisposition,
        pasteAttemptID: String,
        postAccessState: Bool?,
        secureInputState: Bool?,
        decision: PasteDecisionDiagnostics
    ) -> PasteTiming {
        let totalElapsedMs = (dependencies.nowNanoseconds() - pasteStartNs) / 1_000_000
        #if DEBUG
        print("⚠️ Paste blocked (\(blocker.rawValue)); clipboard: \(clipboardDisposition.rawValue)")
        #endif
        return PasteTiming(
            commandOutcome: .blocked(blocker),
            clipboardDisposition: clipboardDisposition,
            commandSentElapsedMs: nil,
            totalElapsedMs: totalElapsedMs,
            pasteAttemptID: pasteAttemptID,
            postAccessState: postAccessState,
            secureInputState: secureInputState,
            decision: decision
        )
    }

    private func makeOperationalRecord(
        captureID: String,
        timing: PasteTiming
    ) -> PasteOperationalRecord? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return PasteOperationalRecord(
            timestamp: formatter.string(from: Date()),
            appVersion: AppIdentity.version,
            appBuild: AppIdentity.build,
            appCodeHash: AppIdentity.codeHash,
            captureID: captureID,
            timing: timing
        )
    }

    private func recordPasteAttempt(captureID: String, timing: PasteTiming) async {
        guard let record = makeOperationalRecord(captureID: captureID, timing: timing) else {
            return
        }
        await dependencies.recordPasteAttempt(record)
    }

}
