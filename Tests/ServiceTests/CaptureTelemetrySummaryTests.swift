import Testing
import Foundation
@testable import mrml

@Suite("CaptureTelemetrySummary Tests")
struct CaptureTelemetrySummaryTests {
    @MainActor
    @Test("Two-call summary includes refinement attribution")
    func twoCallSummaryIncludesRefinementAttribution() async throws {
        let network = MockLegacyTranscriptionNetworkingForSummaryTests()
        let whisper = SummaryTestWhisperKitService()
        let service = TranscriptionPipelineService(network: network, whisperKitService: whisper, cohereMLXService: CohereMLXService())

        let settings = PipelineSettingsSnapshot(
            transcriptionProvider: .openAIWhisper,
            transcriptionAPIKey: "transcription-key",
            transcriptionBaseURL: "https://example.test/v1",
            transcriptionModel: "whisper-1",
            refinementProvider: .openAI,
            refinementAPIKey: "refinement-key",
            refinementBaseURL: "https://example.test/v1",
            refinementModel: "gpt-4o-mini",
            skipRefinement: false,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: [.english],
            cohereLanguage: .english
        )

        let transcription = try await service.executeTranscription(
            request: TranscriptionRequest(
                captureID: "capture-1",
                audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
                audioDurationMs: 1_200,
                baselinePrompt: "",
                settings: settings
            )
        )

        let summary = CaptureTelemetrySummary(
            captureID: "capture-1",
            context: transcription.runContext,
            timeline: CaptureStageTimeline(
                stopRequestedAt: 1_000,
                audioReadyAt: 1_100,
                backendLoadStartedAt: nil,
                backendLoadFinishedAt: nil,
                transcriptionStartedAt: 1_200,
                transcriptionFinishedAt: 1_500,
                refinementStartedAt: 1_600,
                refinementFinishedAt: 1_900,
                finalResultReadyAt: 1_900,
                pasteCommandSentAt: 2_000,
                pasteCompletedAt: 2_100,
                pasteSucceeded: true
            )
        )

        let metadata = summary.metadata
        #expect(metadata["refinement_provider"] == Provider.openAI.rawValue)
        #expect(metadata["refinement_model"] == settings.refinementModel)
        #expect(metadata["refinement_config_fingerprint"]?.isEmpty == false)
    }

    @Test("Summary metadata includes paste outcome")
    func summaryIncludesPasteOutcome() {
        let context = TranscriptionRunContext(
            provider: TranscriptionProvider.whisperKit.rawValue,
            backendKind: .localNative,
            supportTier: .firstClass,
            pipelineMode: .transcribeOnly,
            model: "openai_whisper-medium",
            backendConfigFingerprint: "fingerprint",
            refinementProvider: nil,
            refinementModel: nil,
            refinementConfigFingerprint: nil,
            languageMode: .explicit,
            languageCode: "en",
            audioDurationMs: 1_200,
            warmState: .warmReady,
            refinementEnabled: false
        )
        let summary = CaptureTelemetrySummary(
            captureID: "capture-1",
            context: context,
            timeline: CaptureStageTimeline(
                stopRequestedAt: 1_000,
                audioReadyAt: 1_100,
                backendLoadStartedAt: nil,
                backendLoadFinishedAt: nil,
                transcriptionStartedAt: 1_200,
                transcriptionFinishedAt: 1_500,
                refinementStartedAt: nil,
                refinementFinishedAt: nil,
                finalResultReadyAt: 1_500,
                pasteCommandSentAt: 1_550,
                pasteCompletedAt: 1_650,
                pasteSucceeded: true
            )
        )

        #expect(summary.metadata["paste_succeeded"] == "true")
    }

    @Test("Parallel audit summary exposes selected-result and fanout attribution separately")
    func parallelAuditSummaryIncludesAuditAttribution() {
        let context = TranscriptionRunContext(
            provider: TranscriptionProvider.openAIWhisper.rawValue,
            backendKind: .cloud,
            supportTier: .legacyCompatibility,
            pipelineMode: .twoCallRefinement,
            model: "whisper-1",
            backendConfigFingerprint: "fingerprint",
            refinementProvider: Provider.openAI.rawValue,
            refinementModel: "gpt-4o-mini",
            refinementConfigFingerprint: "refinement-fingerprint",
            languageMode: .notApplicable,
            languageCode: nil,
            audioDurationMs: 1_500,
            warmState: .notApplicable,
            refinementEnabled: true
        )
        let summary = CaptureTelemetrySummary(
            captureID: "capture-2",
            context: context,
            timeline: CaptureStageTimeline(
                stopRequestedAt: 1_000,
                audioReadyAt: 1_100,
                backendLoadStartedAt: nil,
                backendLoadFinishedAt: nil,
                transcriptionStartedAt: 1_200,
                transcriptionFinishedAt: 1_500,
                refinementStartedAt: 1_550,
                refinementFinishedAt: 1_900,
                selectedResultReadyAt: 1_700,
                auditFanoutFinishedAt: 1_900,
                auditVariantSuccessCount: 3,
                auditVariantFailureCount: 1,
                finalResultReadyAt: 1_900,
                pasteCommandSentAt: 2_000,
                pasteCompletedAt: 2_100,
                pasteSucceeded: true
            )
        )

        #expect(summary.metadata["selected_result_ready_at"] == "1700")
        #expect(summary.metadata["audit_fanout_finished_at"] == "1900")
        #expect(summary.metadata["audit_variant_success_count"] == "3")
        #expect(summary.metadata["audit_variant_failure_count"] == "1")
        #expect(summary.metadata["audit_fanout_elapsed_ms"] == "0")
    }

    @Test("Summary metadata includes raw and processed audio observations")
    func summaryIncludesProcessingObservations() {
        let context = TranscriptionRunContext(
            provider: TranscriptionProvider.whisperKit.rawValue,
            backendKind: .localNative,
            supportTier: .firstClass,
            pipelineMode: .transcribeOnly,
            model: "openai_whisper-medium",
            backendConfigFingerprint: "fingerprint",
            refinementProvider: nil,
            refinementModel: nil,
            refinementConfigFingerprint: nil,
            languageMode: .explicit,
            languageCode: "en",
            audioDurationMs: 800,
            warmState: .warmReady,
            refinementEnabled: false
        )

        let summary = CaptureTelemetrySummary(
            captureID: "capture-3",
            context: context,
            timeline: CaptureStageTimeline(
                stopRequestedAt: 1_000,
                audioReadyAt: 1_100,
                backendLoadStartedAt: nil,
                backendLoadFinishedAt: nil,
                transcriptionStartedAt: 1_200,
                transcriptionFinishedAt: 1_500,
                refinementStartedAt: nil,
                refinementFinishedAt: nil,
                finalResultReadyAt: 1_500,
                pasteCommandSentAt: 1_550,
                pasteCompletedAt: 1_650,
                pasteSucceeded: false
            ),
            processing: CaptureProcessingObservations(
                rawAudioDurationMs: 900,
                rawAudioFileSizeBytes: 55_296,
                processedAudioDurationMs: 800,
                processedAudioFileSizeBytes: 49_152,
                speechDetected: true,
                trimResult: .completed,
                transcriptionCharacterCount: 0,
                completionReason: "empty_transcript_skipped"
            )
        )

        #expect(summary.metadata["raw_audio_duration_ms"] == "900")
        #expect(summary.metadata["processed_audio_duration_ms"] == "800")
        #expect(summary.metadata["trim_result"] == "completed")
        #expect(summary.metadata["speech_detected"] == "true")
        #expect(summary.metadata["transcription_character_count"] == "0")
        #expect(summary.metadata["completion_reason"] == "empty_transcript_skipped")
    }
}

private final class MockLegacyTranscriptionNetworkingForSummaryTests: LegacyTranscriptionNetworking {
    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        "transcribed"
    }

    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        "local"
    }

    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        "one call"
    }

    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        "refined"
    }
}

@MainActor
private final class SummaryTestWhisperKitService: WhisperKitTranscribing {
    var modelState: WhisperKitService.ModelState = .ready
    var selectedModel: String = "openai_whisper-small"

    func loadModel(_ variant: String) async throws {}
    func transcribe(audioURL: URL) async throws -> String { "whisper" }
}
