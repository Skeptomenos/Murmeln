import AppKit
import Carbon.HIToolbox

/// Main-actor OS boundaries used by one paste transaction.
///
/// `NSPasteboard` and `CGEvent` are intentionally kept out of Sendable values.
/// Event-post access is preflight-only here. Permission requests belong to the
/// explicit menu action and cannot be reached from an ordinary paste.
@MainActor
struct PasteServiceDependencies {
    struct PasteEvents {
        let commandDown: CGEvent
        let down: CGEvent
        let up: CGEvent
        let commandUp: CGEvent

        var ordered: [CGEvent] { [commandDown, down, up, commandUp] }
    }

    let pasteboard: NSPasteboard
    let captureClipboard: @MainActor (NSPasteboard) -> ClipboardSnapshot
    let setPasteboardString: @MainActor (String, NSPasteboard) -> Bool
    let restoreClipboard: @MainActor (ClipboardSnapshot, NSPasteboard) -> ClipboardDisposition
    let preflightPostEventAccess: @MainActor () -> Bool
    let secureInputActive: @MainActor () -> Bool
    let readModifierFlags: @MainActor () -> CGEventFlags
    let makePasteEvents: @MainActor (CGEventFlags) -> PasteEvents?
    let postEvent: @MainActor (CGEvent) -> Void
    let sleep: @MainActor (Duration) async throws -> Void
    let nowNanoseconds: @MainActor () -> UInt64
    let makePasteAttemptID: @MainActor () -> String
    let makeCaptureID: @MainActor () -> String
    let recordPasteAttempt: @MainActor (PasteOperationalRecord) async -> Void

    init(
        pasteboard: NSPasteboard,
        captureClipboard: @escaping @MainActor (NSPasteboard) -> ClipboardSnapshot = { ClipboardSnapshot.capture(from: $0) },
        setPasteboardString: @escaping @MainActor (String, NSPasteboard) -> Bool,
        restoreClipboard: @escaping @MainActor (ClipboardSnapshot, NSPasteboard) -> ClipboardDisposition = { snapshot, pasteboard in
            snapshot.restoreOutcome(to: pasteboard)
        },
        preflightPostEventAccess: @escaping @MainActor () -> Bool,
        secureInputActive: @escaping @MainActor () -> Bool,
        readModifierFlags: @escaping @MainActor () -> CGEventFlags,
        makePasteEvents: @escaping @MainActor (CGEventFlags) -> PasteEvents?,
        postEvent: @escaping @MainActor (CGEvent) -> Void,
        sleep: @escaping @MainActor (Duration) async throws -> Void,
        nowNanoseconds: @escaping @MainActor () -> UInt64,
        makePasteAttemptID: @escaping @MainActor () -> String = { UUID().uuidString },
        makeCaptureID: @escaping @MainActor () -> String = { UUID().uuidString },
        recordPasteAttempt: @escaping @MainActor (PasteOperationalRecord) async -> Void = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.captureClipboard = captureClipboard
        self.setPasteboardString = setPasteboardString
        self.restoreClipboard = restoreClipboard
        self.preflightPostEventAccess = preflightPostEventAccess
        self.secureInputActive = secureInputActive
        self.readModifierFlags = readModifierFlags
        self.makePasteEvents = makePasteEvents
        self.postEvent = postEvent
        self.sleep = sleep
        self.nowNanoseconds = nowNanoseconds
        self.makePasteAttemptID = makePasteAttemptID
        self.makeCaptureID = makeCaptureID
        self.recordPasteAttempt = recordPasteAttempt
    }

    static var live: PasteServiceDependencies {
        PasteServiceDependencies(
            pasteboard: .general,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            restoreClipboard: { snapshot, pasteboard in
                snapshot.restoreOutcome(to: pasteboard)
            },
            preflightPostEventAccess: { CGPreflightPostEventAccess() },
            secureInputActive: { IsSecureEventInputEnabled() },
            readModifierFlags: { CGEventSource.flagsState(.combinedSessionState) },
            makePasteEvents: { baselineFlags in
                let keyCode: CGKeyCode
                if let resolvedKeyCode = KeyboardLayoutResolver.keyCode(for: "v") {
                    #if DEBUG
                    print("⌨️ Simulating paste via CGEvent with resolved key code: \(resolvedKeyCode)")
                    #endif
                    keyCode = resolvedKeyCode
                } else {
                    #if DEBUG
                    print("⚠️ KeyboardLayoutResolver failed, trying hardcoded kVK_ANSI_V")
                    #endif
                    keyCode = CGKeyCode(kVK_ANSI_V)
                }

                return makeCommandPasteEvents(keyCode: keyCode, baselineFlags: baselineFlags)
            },
            postEvent: { event in
                event.post(tap: .cgSessionEventTap)
            },
            sleep: { duration in
                try await Task.sleep(for: duration)
            },
            nowNanoseconds: {
                DispatchTime.now().uptimeNanoseconds
            },
            recordPasteAttempt: { record in
                await CaptureDiagnostics.shared.recordPasteAttempt(record)
            }
        )
    }

    nonisolated static func modifiersPermitPaste(_ flags: CGEventFlags) -> Bool {
        flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty
    }

    /// Construct the complete chord before posting any part of it. This also
    /// lets tests inspect the production event construction without emitting keys.
    static func makeCommandPasteEvents(keyCode: CGKeyCode, baselineFlags: CGEventFlags) -> PasteEvents? {
        guard modifiersPermitPaste(baselineFlags),
              let source = CGEventSource(stateID: .combinedSessionState),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false) else { return nil }

        let chordFlags = baselineFlags.union(.maskCommand)
        commandDown.flags = chordFlags
        down.flags = chordFlags
        up.flags = chordFlags
        commandUp.flags = baselineFlags
        return PasteEvents(commandDown: commandDown, down: down, up: up, commandUp: commandUp)
    }
}
