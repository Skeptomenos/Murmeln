import Testing
@testable import mrml

@Suite("Paste Failure Outcome Tests")
struct PasteFailureOutcomeTests {
    @Test("Every blocker offers manual recovery without unsupported claims", arguments: [
        PasteBlocker.postEventAccessDenied, .secureInputActive, .keyEventCreationFailed,
        .clipboardWriteFailed, .clipboardChanged, .clipboardSnapshotUnavailable, .cancelled
    ])
    func everyBlocker(blocker: PasteBlocker) {
        let presentation = PasteFailurePresentation(blocker: blocker, pasteAttemptID: "private-id")
        #expect(presentation.recoveryActions == [.copyAgain, .openHistory])
        #expect(presentation.message.hasSuffix("Your text is available to copy."))
        for forbidden in ["on the clipboard", "saved in History", "private-id", "quit apps", "restart"] {
            #expect(!presentation.message.contains(forbidden))
        }
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello", pasteCommandOutcome: .blocked(blocker),
            clipboardDisposition: .unchanged, processedAudioDurationMs: 2_500, speechDetected: true)
        #expect(outcome.completionReason == "paste_command_blocked")
        #expect(outcome.userFacingMessage == presentation.message)
    }

    @Test("Restoration failure adds an honest warning")
    func restoreFailure() {
        let presentation = PasteFailurePresentation(blocker: .clipboardWriteFailed, clipboardDisposition: .restoreFailed)
        #expect(presentation.message.contains("The previous clipboard could not be restored."))
    }

    @Test("Clipboard replacement does not imply saved text or current ownership")
    func externalWrite() {
        let presentation = PasteFailurePresentation(blocker: .clipboardChanged, clipboardDisposition: .externalWritePreserved)
        #expect(presentation.message == "The clipboard changed before paste. No paste command was sent. Your text is available to copy.")
    }
}
