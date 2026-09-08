import Testing
@testable import mrml

@Suite("CaptureCompletionOutcome Tests")
struct CaptureCompletionOutcomeTests {
    @Test("Short speech with empty decode gets explicit short-audio outcome")
    func shortSpeechEmptyDecodeGetsExplicitOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "",
            pasteCommandOutcome: .notAttempted,
            clipboardDisposition: .unchanged,
            processedAudioDurationMs: 590,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "short_audio_empty_decode")
        #expect(outcome.userFacingMessage == "Too short to transcribe reliably.")
    }

    @Test("Longer empty decode keeps generic empty-transcript outcome")
    func longerEmptyDecodeKeepsGenericOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "",
            pasteCommandOutcome: .notAttempted,
            clipboardDisposition: .unchanged,
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "empty_transcript_skipped")
        #expect(outcome.userFacingMessage == nil)
    }

    @Test("Non-empty transcript uses the exact blocker presentation")
    func blockedPasteCommandUsesExactPresentation() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteCommandOutcome: .blocked(.keyEventCreationFailed),
            clipboardDisposition: .transcriptPreserved,
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "paste_command_blocked")
        #expect(
            outcome.userFacingMessage
                == "Murmeln could not create the paste command. Your text is available to copy."
        )
    }

    @Test("Blocked completion keeps operational identifiers out of the notice")
    func blockedCompletionCarriesPasteAttemptReference() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteCommandOutcome: .blocked(.postEventAccessDenied),
            clipboardDisposition: .transcriptPreserved,
            pasteAttemptID: "12345678-ABCD-EF00-1234-567890ABCDEF",
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.userFacingMessage?.contains("12345678") == false)
        #expect(outcome.userFacingMessage?.contains("12345678-ABCD") == false)
    }

    @Test("Posted paste command reports only that the command was posted")
    func postedPasteCommandReportsPostedOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteCommandOutcome: .posted,
            clipboardDisposition: .restored,
            processedAudioDurationMs: 590,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed")
        #expect(outcome.completionReason == "paste_command_posted")
        #expect(outcome.userFacingMessage == nil)
    }

    @Test("Clipboard restoration failure warns without changing posted command outcome")
    func restorationFailureWarnsWithoutChangingPostedOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteCommandOutcome: .posted,
            clipboardDisposition: .restoreFailed,
            processedAudioDurationMs: 590,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed")
        #expect(outcome.completionReason == "paste_command_posted")
        #expect(
            outcome.userFacingMessage
                == "Paste command sent, but Murmeln could not restore your previous clipboard contents."
        )
    }

    @Test(
        "Blocked command does not claim transcript is on a clipboard that does not contain it",
        arguments: [
            ClipboardDisposition.externalWritePreserved,
            .restoreFailed,
        ]
    )
    func blockedCommandDoesNotMakeFalseClipboardClaim(clipboardDisposition: ClipboardDisposition) {
        let presentation = PasteFailurePresentation(
            blocker: .secureInputActive,
            clipboardDisposition: clipboardDisposition
        )
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteCommandOutcome: .blocked(.secureInputActive),
            clipboardDisposition: clipboardDisposition,
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "paste_command_blocked")
        #expect(outcome.userFacingMessage == presentation.message)
        #expect(outcome.userFacingMessage?.contains("Secure Input was active.") == true)
        #expect(outcome.userFacingMessage?.contains("on the clipboard") == false)
        #expect(outcome.userFacingMessage?.contains("available to copy") == true)
    }
}
