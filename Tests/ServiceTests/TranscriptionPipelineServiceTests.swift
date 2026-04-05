import Testing
import Foundation
@testable import mrml

@Suite("Transcription Backend Descriptor Tests")
struct TranscriptionBackendDescriptorTests {
    @Test("WhisperKit is first-class local-native")
    func whisperKitDescriptor() {
        let descriptor = TranscriptionProvider.whisperKit.backendDescriptor

        #expect(descriptor.kind == .localNative)
        #expect(descriptor.supportTier == .firstClass)
        #expect(descriptor.family == .firstClassLocalNativeWhisperKit)
        #expect(descriptor.capabilities.requiresAPIKey == false)
        #expect(descriptor.capabilities.supportsLanguageOverride == true)
        #expect(descriptor.capabilities.supportsLocalModelLifecycle == true)
    }

    @Test("Cloud multipart providers are legacy compatibility")
    func cloudMultipartDescriptors() {
        let openAI = TranscriptionProvider.openAIWhisper.backendDescriptor
        let groq = TranscriptionProvider.groqWhisper.backendDescriptor

        #expect(openAI.kind == .cloud)
        #expect(openAI.supportTier == .legacyCompatibility)
        #expect(openAI.family == .legacyCloudMultipart)

        #expect(groq.kind == .cloud)
        #expect(groq.supportTier == .legacyCompatibility)
        #expect(groq.family == .legacyCloudMultipart)
    }

    @Test("Legacy local-server and cloud-audio families are distinct")
    func legacyFamilyDescriptors() {
        let localServer = TranscriptionProvider.localWhisper.backendDescriptor
        let oneCallCloud = TranscriptionProvider.gpt4oAudio.backendDescriptor

        #expect(localServer.kind == .localServer)
        #expect(localServer.family == .legacyLocalServer)
        #expect(localServer.supportTier == .legacyCompatibility)

        #expect(oneCallCloud.kind == .cloud)
        #expect(oneCallCloud.family == .legacyCloudAudioInput)
        #expect(oneCallCloud.capabilities.supportsOneCallRefinement == true)
    }
}

@MainActor
@Suite("Transcription Pipeline Service Tests")
struct TranscriptionPipelineServiceTests {
    @Test("Pipeline mode selects transcribe-only when refinement skipped")
    func pipelineModeTranscribeOnly() {
        let service = makeService()
        let settings = makeSettings(skipRefinement: true)

        #expect(service.pipelineMode(for: settings) == .transcribeOnly)
    }

    @Test("Pipeline mode selects one-call for cloud audio input")
    func pipelineModeOneCall() {
        let service = makeService()
        let settings = makeSettings(transcriptionProvider: .gpt4oAudio, skipRefinement: false)

        #expect(service.pipelineMode(for: settings) == .oneCallTranscriptionAndRefinement)
    }

    @Test("Pipeline mode selects two-call for transcription-only backends")
    func pipelineModeTwoCall() {
        let service = makeService()
        let settings = makeSettings(transcriptionProvider: .openAIWhisper, skipRefinement: false)

        #expect(service.pipelineMode(for: settings) == .twoCallRefinement)
    }

    @Test("Warm WhisperKit run skips model load")
    func executeTranscriptionWarmWhisperKit() async throws {
        let network = MockLegacyTranscriptionNetworking()
        let whisper = MockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        whisper.transcribeResult = "warm transcript"

        let service = makeService(network: network, whisper: whisper)
        let request = makeTranscriptionRequest(
            settings: makeSettings(transcriptionProvider: .whisperKit, transcriptionModel: "openai_whisper-small")
        )

        let result = try await service.executeTranscription(request: request)

        #expect(result.text == "warm transcript")
        #expect(result.runContext.warmState == .warmReady)
        #expect(result.backendLoadTiming == nil)
        #expect(whisper.loadModelCalls.isEmpty)
        #expect(whisper.transcribeCalls == 1)
    }

    @Test("Cold WhisperKit run loads model and records load timing")
    func executeTranscriptionColdWhisperKit() async throws {
        let network = MockLegacyTranscriptionNetworking()
        let whisper = MockWhisperKitService()
        whisper.modelState = .unloaded
        whisper.selectedModel = "openai_whisper-base"
        whisper.transcribeResult = "cold transcript"

        let service = makeService(network: network, whisper: whisper)
        let request = makeTranscriptionRequest(
            settings: makeSettings(transcriptionProvider: .whisperKit, transcriptionModel: "openai_whisper-small")
        )

        let result = try await service.executeTranscription(request: request)

        #expect(result.text == "cold transcript")
        #expect(result.runContext.warmState == .coldLoad)
        #expect(result.backendLoadTiming != nil)
        #expect(whisper.loadModelCalls == ["openai_whisper-small"])
        #expect(whisper.transcribeCalls == 1)
    }

    @Test("OpenAI-compatible legacy multipart path uses multipart adapter")
    func executeTranscriptionLegacyMultipart() async throws {
        let network = MockLegacyTranscriptionNetworking()
        network.openAIResult = "multipart transcript"
        let whisper = MockWhisperKitService()
        let service = makeService(network: network, whisper: whisper)
        let request = makeTranscriptionRequest(
            settings: makeSettings(transcriptionProvider: .openAIWhisper, skipRefinement: false)
        )

        let result = try await service.executeTranscription(request: request)

        #expect(result.text == "multipart transcript")
        #expect(result.runContext.backendKind == .cloud)
        #expect(result.runContext.supportTier == .legacyCompatibility)
        #expect(result.runContext.pipelineMode == .twoCallRefinement)
        #expect(result.runContext.warmState == .notApplicable)
        #expect(network.openAICalls == 1)
        #expect(network.localWhisperCalls == 0)
        #expect(network.cloudAudioInputCalls.count == 0)
    }

    @Test("Legacy local-server path uses local whisper adapter")
    func executeTranscriptionLegacyLocalServer() async throws {
        let network = MockLegacyTranscriptionNetworking()
        network.localWhisperResult = "local server transcript"
        let whisper = MockWhisperKitService()
        let service = makeService(network: network, whisper: whisper)
        let settings = makeSettings(transcriptionProvider: .localWhisper, skipRefinement: false)
        let request = makeTranscriptionRequest(settings: settings)

        let result = try await service.executeTranscription(request: request)

        #expect(result.text == "local server transcript")
        #expect(result.runContext.backendKind == .localServer)
        #expect(result.runContext.supportTier == .legacyCompatibility)
        #expect(result.runContext.pipelineMode == .twoCallRefinement)
        #expect(result.runContext.warmState == .unknownServerState)
        #expect(network.localWhisperCalls == 1)
        #expect(network.openAICalls == 0)
        #expect(network.cloudAudioInputCalls.count == 0)
    }

    @Test("Cloud audio-input one-call path receives baseline prompt")
    func executeTranscriptionCloudAudioInput() async throws {
        let network = MockLegacyTranscriptionNetworking()
        network.cloudAudioInputResult = "one call result"
        let whisper = MockWhisperKitService()
        let service = makeService(network: network, whisper: whisper)
        let settings = makeSettings(transcriptionProvider: .gpt4oAudio, skipRefinement: false)
        let request = makeTranscriptionRequest(settings: settings, baselinePrompt: "system baseline")

        let result = try await service.executeTranscription(request: request)

        #expect(result.text == "one call result")
        #expect(result.runContext.pipelineMode == .oneCallTranscriptionAndRefinement)
        #expect(network.cloudAudioInputCalls.count == 1)
        #expect(network.cloudAudioInputCalls[0].systemPrompt == "system baseline")
        #expect(network.cloudAudioInputCalls[0].provider == .gpt4oAudio)
    }

    @Test("Refinement execution routes through text refinement backend")
    func executeRefinement() async throws {
        let network = MockLegacyTranscriptionNetworking()
        network.refineResult = "refined text"
        let whisper = MockWhisperKitService()
        let service = makeService(network: network, whisper: whisper)

        let result = try await service.executeRefinement(
            request: RefinementRequest(
                captureID: "capture-1",
                text: "raw text",
                systemPrompt: "refine this",
                settings: makeSettings()
            )
        )

        #expect(result.text == "refined text")
        #expect(network.refineCalls.count == 1)
        #expect(network.refineCalls[0].text == "raw text")
        #expect(network.refineCalls[0].systemPrompt == "refine this")
    }

    @Test("WhisperKit language context is explicit with single language")
    func executeTranscriptionWhisperKitExplicitLanguageContext() async throws {
        let network = MockLegacyTranscriptionNetworking()
        let whisper = MockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        let service = makeService(network: network, whisper: whisper)

        let settings = makeSettings(
            transcriptionProvider: .whisperKit,
            whisperKitLanguages: [.german]
        )
        let result = try await service.executeTranscription(
            request: makeTranscriptionRequest(settings: settings)
        )

        #expect(result.runContext.languageMode == .explicit)
        #expect(result.runContext.languageCode == "de")
    }

    @Test("WhisperKit language context is auto-detect with multiple languages")
    func executeTranscriptionWhisperKitAutoLanguageContext() async throws {
        let network = MockLegacyTranscriptionNetworking()
        let whisper = MockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        let service = makeService(network: network, whisper: whisper)

        let settings = makeSettings(
            transcriptionProvider: .whisperKit,
            whisperKitLanguages: [.english, .german]
        )
        let result = try await service.executeTranscription(
            request: makeTranscriptionRequest(settings: settings)
        )

        #expect(result.runContext.languageMode == .autoDetect)
        #expect(result.runContext.languageCode == nil)
    }

    @Test("WhisperKit backend fingerprint uses actual normalized decode request")
    func executeTranscriptionWhisperKitFingerprintReflectsActualDecodeRequest() async throws {
        let network = MockLegacyTranscriptionNetworking()
        let whisper = MockWhisperKitService()
        whisper.modelState = .ready
        whisper.selectedModel = "openai_whisper-small"
        let service = makeService(network: network, whisper: whisper)

        let settings = makeSettings(
            transcriptionProvider: .whisperKit,
            skipRefinement: true,
            whisperKitLanguages: [.english]
        )
        let result = try await service.executeTranscription(
            request: makeTranscriptionRequest(settings: settings)
        )

        let prepared = try #require(whisper.lastPreparedDecoding)
        #expect(prepared.requestShape.usePrefillPrompt == true)
        #expect(prepared.requestShape.usePrefillCache == true)
        #expect(prepared.requestShape.withoutTimestamps == false)
        #expect(prepared.requestShape.suppressTokens.isEmpty)
        #expect(prepared.requestShape.droppedSuppressTokens == [-1])

        #expect(result.runContext.backendConfigFingerprint.contains("without_timestamps=false"))
        #expect(result.runContext.backendConfigFingerprint.contains("detect_language=false"))
        #expect(result.runContext.backendConfigFingerprint.contains("prompt_prefill=true"))
        #expect(result.runContext.backendConfigFingerprint.contains("prefill_cache=true"))
        #expect(result.runContext.backendConfigFingerprint.contains("chunking=none"))
        #expect(result.runContext.backendConfigFingerprint.contains("dropped_suppress_tokens=-1"))
    }

    private func makeService(
        network: LegacyTranscriptionNetworking = MockLegacyTranscriptionNetworking(),
        whisper: WhisperKitTranscribing = MockWhisperKitService()
    ) -> TranscriptionPipelineService {
        TranscriptionPipelineService(network: network, whisperKitService: whisper, cohereMLXService: CohereMLXService())
    }

    private func makeTranscriptionRequest(
        settings: PipelineSettingsSnapshot,
        baselinePrompt: String = ""
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            captureID: "capture-1",
            audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
            audioDurationMs: 1_230,
            baselinePrompt: baselinePrompt,
            settings: settings
        )
    }

    private func makeSettings(
        transcriptionProvider: TranscriptionProvider = .openAIWhisper,
        transcriptionModel: String = "whisper-1",
        skipRefinement: Bool = false,
        whisperKitLanguages: [WhisperKitLanguage] = [.english]
    ) -> PipelineSettingsSnapshot {
        PipelineSettingsSnapshot(
            transcriptionProvider: transcriptionProvider,
            transcriptionAPIKey: "transcription-key",
            transcriptionBaseURL: "https://example.test/v1",
            transcriptionModel: transcriptionModel,
            refinementProvider: .openAI,
            refinementAPIKey: "refinement-key",
            refinementBaseURL: "https://example.test/v1",
            refinementModel: "gpt-4o-mini",
            skipRefinement: skipRefinement,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: whisperKitLanguages
        )
    }
}

private final class MockLegacyTranscriptionNetworking: LegacyTranscriptionNetworking, @unchecked Sendable {
    struct CloudAudioInputCall {
        let provider: TranscriptionProvider
        let systemPrompt: String
    }

    struct RefineCall {
        let text: String
        let systemPrompt: String
    }

    var openAIResult = "openai result"
    var localWhisperResult = "local whisper result"
    var cloudAudioInputResult = "cloud audio input result"
    var refineResult = "refined result"

    var openAICalls = 0
    var localWhisperCalls = 0
    var cloudAudioInputCalls: [CloudAudioInputCall] = []
    var refineCalls: [RefineCall] = []

    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        openAICalls += 1
        return openAIResult
    }

    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        localWhisperCalls += 1
        return localWhisperResult
    }

    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        cloudAudioInputCalls.append(CloudAudioInputCall(provider: provider, systemPrompt: systemPrompt))
        return cloudAudioInputResult
    }

    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        refineCalls.append(RefineCall(text: text, systemPrompt: systemPrompt))
        return refineResult
    }
}

@MainActor
private final class MockWhisperKitService: WhisperKitTranscribing {
    var modelState: WhisperKitService.ModelState = .ready
    var selectedModel: String = "openai_whisper-small"

    var transcribeResult = "whisper result"
    var loadModelCalls: [String] = []
    var transcribeCalls = 0
    var lastPreparedDecoding: WhisperKitPreparedDecoding?

    func loadModel(_ variant: String) async throws {
        loadModelCalls.append(variant)
        selectedModel = variant
        modelState = .ready
    }

    func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding {
        let prepared = WhisperKitService.prepareDecoding(settings: settings)
        lastPreparedDecoding = prepared
        return prepared
    }

    func transcribe(audioURL: URL) async throws -> String {
        transcribeCalls += 1
        return transcribeResult
    }

    func transcribe(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> String {
        transcribeCalls += 1
        lastPreparedDecoding = preparedDecoding
        return transcribeResult
    }
}
