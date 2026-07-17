import Foundation
import Testing
@testable import mrml

/// Slice 2 regression contract: the transcript and the FULL per-capture
/// telemetry metadata produced by the WhisperKit path, snapshotted against
/// the pre-rewire `WhisperKitTranscriptionBackend` and required to stay
/// byte-identical when the generic `RuntimeTranscriptionBackend` takes over.
/// New fields may be ADDED (they appear only in the live dict and are
/// compared key-by-key against the fixture's keys), none may change/vanish.
///
/// Re-record (only when a contract change is intentional and documented in
/// the plan): MURMELN_RECORD_GOLDEN=1 swift test --filter WhisperKitGoldenMaster
@MainActor
@Suite("WhisperKit Golden Master Tests")
struct WhisperKitGoldenMasterTests {

    struct GoldenSnapshot: Codable, Equatable {
        let text: String
        let hasBackendLoadTiming: Bool
        let telemetryMetadata: [String: String]
    }

    // MARK: Scenarios

    @Test("Warm run, explicit German, raw mode matches golden master")
    func warmExplicitGermanRawMode() async throws {
        let whisper = GoldenMockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        whisper.transcribeResult = "Guten Morgen, dies ist der goldene Standard."

        let snapshot = try await runScenario(
            whisper: whisper,
            settings: goldenSettings(
                skipRefinement: true,
                whisperKitLanguages: [.german]
            )
        )
        try compare(snapshot, against: "warm-explicit-de-raw")
    }

    @Test("Cold run, auto-detect, two-call refinement matches golden master")
    func coldAutoDetectTwoCall() async throws {
        let whisper = GoldenMockWhisperKitService()
        whisper.modelState = .unloaded
        whisper.selectedModel = "openai_whisper-base"
        whisper.transcribeResult = "Cold start golden transcript."

        let snapshot = try await runScenario(
            whisper: whisper,
            settings: goldenSettings(
                skipRefinement: false,
                whisperKitLanguages: [.english, .german]
            )
        )
        try compare(snapshot, against: "cold-auto-twocall")
    }

    @Test("Warm run, VAD + timestamps enabled matches golden master")
    func warmVADTimestamps() async throws {
        let whisper = GoldenMockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        whisper.transcribeResult = "VAD timestamped golden transcript."

        let snapshot = try await runScenario(
            whisper: whisper,
            settings: goldenSettings(
                skipRefinement: true,
                whisperKitLanguages: [.english],
                enableTimestamps: true,
                useVAD: true
            )
        )
        try compare(snapshot, against: "warm-vad-timestamps")
    }

    // MARK: Harness

    private func runScenario(
        whisper: GoldenMockWhisperKitService,
        settings: PipelineSettingsSnapshot
    ) async throws -> GoldenSnapshot {
        let service = TranscriptionPipelineService(
            network: GoldenNoopNetworking(),
            whisperKitService: whisper
        )
        let request = TranscriptionRequest(
            captureID: "golden-capture",
            audioURL: URL(fileURLWithPath: "/tmp/golden.wav"),
            audioDurationMs: 4_321,
            baselinePrompt: "",
            settings: settings
        )

        let result = try await service.executeTranscription(request: request)

        // Fixed timeline so every derived elapsed field is deterministic.
        let timeline = CaptureStageTimeline(
            stopRequestedAt: 1_000_000_000,
            audioReadyAt: 1_050_000_000,
            backendLoadStartedAt: result.backendLoadTiming == nil ? nil : 1_060_000_000,
            backendLoadFinishedAt: result.backendLoadTiming == nil ? nil : 1_460_000_000,
            transcriptionStartedAt: 1_500_000_000,
            transcriptionFinishedAt: 2_500_000_000,
            refinementStartedAt: nil,
            refinementFinishedAt: nil,
            finalResultReadyAt: 2_600_000_000,
            pasteCommandSentAt: 2_700_000_000,
            pasteCompletedAt: 2_800_000_000,
            pasteSucceeded: true
        )
        let summary = CaptureTelemetrySummary(
            captureID: "golden-capture",
            context: result.runContext,
            timeline: timeline
        )
        return GoldenSnapshot(
            text: result.text,
            hasBackendLoadTiming: result.backendLoadTiming != nil,
            telemetryMetadata: summary.metadata
        )
    }

    private func goldenSettings(
        skipRefinement: Bool,
        whisperKitLanguages: [WhisperKitLanguage],
        enableTimestamps: Bool = false,
        useVAD: Bool = false
    ) -> PipelineSettingsSnapshot {
        PipelineSettingsSnapshot(
            transcriptionProvider: .whisperKit,
            transcriptionAPIKey: "",
            transcriptionBaseURL: "",
            transcriptionModel: "openai_whisper-small",
            refinementProvider: .openAI,
            refinementAPIKey: "refinement-key",
            refinementBaseURL: "https://example.test/v1",
            refinementModel: "gpt-4o-mini",
            skipRefinement: skipRefinement,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: true,
            whisperKitEnableTimestamps: enableTimestamps,
            whisperKitUseVAD: useVAD,
            whisperKitLanguages: whisperKitLanguages
        )
    }

    // MARK: Fixture plumbing

    private static let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/golden")

    private var recordMode: Bool {
        ProcessInfo.processInfo.environment["MURMELN_RECORD_GOLDEN"] == "1"
    }

    private func compare(_ snapshot: GoldenSnapshot, against name: String) throws {
        let url = Self.fixturesDir.appendingPathComponent("whisperkit-\(name).json")

        if recordMode {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try FileManager.default.createDirectory(
                at: Self.fixturesDir, withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: url)
            Issue.record("Recorded golden fixture \(url.lastPathComponent) — rerun without MURMELN_RECORD_GOLDEN")
            return
        }

        let golden = try JSONDecoder().decode(GoldenSnapshot.self, from: Data(contentsOf: url))

        #expect(snapshot.text == golden.text)
        #expect(snapshot.hasBackendLoadTiming == golden.hasBackendLoadTiming)
        // Additive-only contract: every golden key must exist with an
        // identical value; keys present only in the live run are new fields
        // and are allowed.
        for (key, goldenValue) in golden.telemetryMetadata {
            #expect(
                snapshot.telemetryMetadata[key] == goldenValue,
                "telemetry field '\(key)' drifted: '\(snapshot.telemetryMetadata[key] ?? "<missing>")' != golden '\(goldenValue)'"
            )
        }
    }
}

// MARK: Scenario mocks (independent of the pipeline test suite's private mocks)

@MainActor
private final class GoldenMockWhisperKitService: WhisperKitTranscribing {
    var modelState: WhisperKitService.ModelState = .ready
    var selectedModel = "openai_whisper-small"
    var transcribeResult = "golden transcript"

    func loadModel(_ variant: String) async throws {
        selectedModel = variant
        modelState = .ready
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcribeResult
    }

    func transcribe(audioURL: URL, languageCode: String?) async throws -> String {
        transcribeResult
    }

    func transcribe(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> String {
        transcribeResult
    }
}

private final class GoldenNoopNetworking: LegacyTranscriptionNetworking, @unchecked Sendable {
    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String { "" }
    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String { "" }
    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String { "" }
    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String { "" }
}
