import Testing
import Foundation
@testable import mrml

@Suite("Transcription Pipeline Concurrency Tests")
struct TranscriptionPipelineConcurrencyTests {
    @Test("Legacy multipart path does not force main-thread execution")
    func legacyMultipartPathDoesNotForceMainThreadExecution() async throws {
        let network = ThreadCapturingLegacyTranscriptionNetworking()
        let whisper = await MainActor.run { ConcurrencyTestWhisperKitService() }
        let cohereMLX = await MainActor.run { CohereMLXService() }
        let service = TranscriptionPipelineService(network: network, whisperKitService: whisper, cohereMLXService: cohereMLX)

        let settings = PipelineSettingsSnapshot(
            transcriptionProvider: .openAIWhisper,
            transcriptionAPIKey: "transcription-key",
            transcriptionBaseURL: "https://example.test/v1",
            transcriptionModel: "whisper-1",
            refinementProvider: .openAI,
            refinementAPIKey: "refinement-key",
            refinementBaseURL: "https://example.test/v1",
            refinementModel: "gpt-4o-mini",
            skipRefinement: true,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: [.english]
        )

        _ = try await Task.detached(priority: .userInitiated) {
            try await service.executeTranscription(
                request: TranscriptionRequest(
                    captureID: "capture-1",
                    audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
                    audioDurationMs: 1_200,
                    baselinePrompt: "",
                    settings: settings
                )
            )
        }.value

        let invocationWasOnMainThread = await MainActor.run {
            network.invocationWasOnMainThread
        }
        #expect(invocationWasOnMainThread == false)
    }
}

private final class ThreadCapturingLegacyTranscriptionNetworking: LegacyTranscriptionNetworking, @unchecked Sendable {
    var invocationWasOnMainThread = false

    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "multipart transcript"
    }

    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "local"
    }

    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "one call"
    }

    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "refined"
    }
}

@MainActor
private final class ConcurrencyTestWhisperKitService: WhisperKitTranscribing {
    var modelState: WhisperKitService.ModelState = .ready
    var selectedModel: String = "openai_whisper-small"

    func loadModel(_ variant: String) async throws {}
    func transcribe(audioURL: URL) async throws -> String { "whisper" }
}
