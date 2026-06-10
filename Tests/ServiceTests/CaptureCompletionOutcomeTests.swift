import Testing
@testable import mrml

@Suite("CaptureCompletionOutcome Tests")
struct CaptureCompletionOutcomeTests {
    @Test("Short speech with empty decode gets explicit short-audio outcome")
    func shortSpeechEmptyDecodeGetsExplicitOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "",
            pasteSucceeded: false,
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
            pasteSucceeded: false,
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "empty_transcript_skipped")
        #expect(outcome.userFacingMessage == nil)
    }

    @Test("Non-empty transcript with failed paste reports paste_failed and keeps text on clipboard")
    func failedPasteWithTranscriptReportsPasteFailed() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteSucceeded: false,
            processedAudioDurationMs: 2_500,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed_no_paste")
        #expect(outcome.completionReason == "paste_failed")
        #expect(outcome.userFacingMessage == "Paste failed — the text is on your clipboard.")
    }

    @Test("Successful paste keeps paste-completed outcome")
    func successfulPasteKeepsCompletedOutcome() {
        let outcome = CaptureCompletionOutcome.classify(
            transcriptionText: "hello world",
            pasteSucceeded: true,
            processedAudioDurationMs: 590,
            speechDetected: true
        )

        #expect(outcome.completionOutcome == "completed")
        #expect(outcome.completionReason == "paste_completed")
        #expect(outcome.userFacingMessage == nil)
    }
}
