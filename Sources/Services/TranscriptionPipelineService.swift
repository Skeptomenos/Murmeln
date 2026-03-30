import Foundation

protocol LegacyTranscriptionNetworking: Sendable {
    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String
    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String
    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String
    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String
}

extension NetworkService: LegacyTranscriptionNetworking {}

protocol WhisperKitTranscribing: AnyObject, Sendable {
    @MainActor
    var modelState: WhisperKitService.ModelState { get }

    @MainActor
    var selectedModel: String { get }

    @MainActor
    func loadModel(_ variant: String) async throws

    @MainActor
    func transcribe(audioURL: URL) async throws -> String
}

extension WhisperKitService: WhisperKitTranscribing {}

private struct TranscriptionBackendExecution {
    let text: String
    let warmState: TranscriptionWarmState
    let backendLoadTiming: StageTiming?
    let transcriptionTiming: StageTiming
}

private protocol TranscriptionBackendAdapter {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution
}

private struct WhisperKitTranscriptionBackend: TranscriptionBackendAdapter {
    private let whisperKitService: WhisperKitTranscribing

    init(whisperKitService: WhisperKitTranscribing) {
        self.whisperKitService = whisperKitService
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let model = request.settings.transcriptionModel
        let currentState = await whisperKitService.modelState
        let currentModel = await whisperKitService.selectedModel
        let isWarm = currentState == .ready && currentModel == model

        var backendLoadTiming: StageTiming?
        let warmState: TranscriptionWarmState

        if isWarm {
            warmState = .warmReady
        } else {
            warmState = .coldLoad
            let loadStart = DispatchTime.now().uptimeNanoseconds
            try await whisperKitService.loadModel(model)
            let loadFinish = DispatchTime.now().uptimeNanoseconds
            backendLoadTiming = StageTiming(startedAt: loadStart, finishedAt: loadFinish)
        }

        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        let text = try await whisperKitService.transcribe(audioURL: request.audioURL)
        let transcriptionFinish = DispatchTime.now().uptimeNanoseconds

        return TranscriptionBackendExecution(
            text: text,
            warmState: warmState,
            backendLoadTiming: backendLoadTiming,
            transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish)
        )
    }
}

private struct LegacyCloudMultipartTranscriptionBackend: TranscriptionBackendAdapter {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        let text = try await network.transcribeOpenAICompatible(
            audioURL: request.audioURL,
            apiKey: request.settings.transcriptionAPIKey,
            baseURL: request.settings.transcriptionBaseURL,
            model: request.settings.transcriptionModel
        )
        let transcriptionFinish = DispatchTime.now().uptimeNanoseconds

        return TranscriptionBackendExecution(
            text: text,
            warmState: .notApplicable,
            backendLoadTiming: nil,
            transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish)
        )
    }
}

private struct LegacyLocalWhisperServerBackend: TranscriptionBackendAdapter {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        let text = try await network.transcribeLocalWhisper(
            audioURL: request.audioURL,
            baseURL: request.settings.transcriptionBaseURL
        )
        let transcriptionFinish = DispatchTime.now().uptimeNanoseconds

        return TranscriptionBackendExecution(
            text: text,
            warmState: .unknownServerState,
            backendLoadTiming: nil,
            transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish)
        )
    }
}

private struct LegacyCloudAudioInputBackend: TranscriptionBackendAdapter {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        let text = try await network.transcribeCloudAudioInput(
            audioURL: request.audioURL,
            provider: request.settings.transcriptionProvider,
            apiKey: request.settings.transcriptionAPIKey,
            baseURL: request.settings.transcriptionBaseURL,
            model: request.settings.transcriptionModel,
            systemPrompt: request.baselinePrompt
        )
        let transcriptionFinish = DispatchTime.now().uptimeNanoseconds

        return TranscriptionBackendExecution(
            text: text,
            warmState: .notApplicable,
            backendLoadTiming: nil,
            transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish)
        )
    }
}

private struct TextRefinementBackend {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func refine(request: RefinementRequest) async throws -> RefinementExecutionResult {
        let refinementStart = DispatchTime.now().uptimeNanoseconds
        let text = try await network.refine(
            text: request.text,
            provider: request.settings.refinementProvider,
            apiKey: request.settings.refinementAPIKey,
            baseURL: request.settings.refinementBaseURL,
            model: request.settings.refinementModel,
            systemPrompt: request.systemPrompt
        )
        let refinementFinish = DispatchTime.now().uptimeNanoseconds

        return RefinementExecutionResult(
            text: text,
            timing: StageTiming(startedAt: refinementStart, finishedAt: refinementFinish)
        )
    }
}

final class TranscriptionPipelineService: @unchecked Sendable {
    @MainActor
    static let shared = TranscriptionPipelineService(
        network: NetworkService.shared,
        whisperKitService: WhisperKitService.shared
    )

    private let whisperKitBackend: WhisperKitTranscriptionBackend
    private let legacyCloudMultipartBackend: LegacyCloudMultipartTranscriptionBackend
    private let legacyLocalWhisperServerBackend: LegacyLocalWhisperServerBackend
    private let legacyCloudAudioInputBackend: LegacyCloudAudioInputBackend
    private let textRefinementBackend: TextRefinementBackend

    init(
        network: LegacyTranscriptionNetworking,
        whisperKitService: WhisperKitTranscribing
    ) {
        whisperKitBackend = WhisperKitTranscriptionBackend(whisperKitService: whisperKitService)
        legacyCloudMultipartBackend = LegacyCloudMultipartTranscriptionBackend(network: network)
        legacyLocalWhisperServerBackend = LegacyLocalWhisperServerBackend(network: network)
        legacyCloudAudioInputBackend = LegacyCloudAudioInputBackend(network: network)
        textRefinementBackend = TextRefinementBackend(network: network)
    }

    func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode {
        if settings.skipRefinement {
            return .transcribeOnly
        }

        if settings.transcriptionProvider.backendDescriptor.capabilities.supportsOneCallRefinement {
            return .oneCallTranscriptionAndRefinement
        }

        return .twoCallRefinement
    }

    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult {
        let descriptor = request.settings.transcriptionProvider.backendDescriptor
        let mode = pipelineMode(for: request.settings)

        let backend = transcriptionBackend(for: descriptor.family)
        let execution = try await backend.transcribe(request: request)

        let (languageMode, languageCode) = resolveLanguageContext(for: request.settings)
        let (refinementProvider, refinementModel, refinementConfigFingerprint) = refinementContext(for: request.settings, mode: mode)
        let runContext = TranscriptionRunContext(
            provider: descriptor.provider.rawValue,
            backendKind: descriptor.kind,
            supportTier: descriptor.supportTier,
            pipelineMode: mode,
            model: request.settings.transcriptionModel,
            backendConfigFingerprint: backendConfigFingerprint(
                settings: request.settings,
                descriptor: descriptor,
                mode: mode,
                languageMode: languageMode,
                languageCode: languageCode
            ),
            refinementProvider: refinementProvider,
            refinementModel: refinementModel,
            refinementConfigFingerprint: refinementConfigFingerprint,
            languageMode: languageMode,
            languageCode: languageCode,
            audioDurationMs: request.audioDurationMs,
            warmState: execution.warmState,
            refinementEnabled: !request.settings.skipRefinement
        )

        return TranscriptionExecutionResult(
            text: execution.text,
            runContext: runContext,
            backendLoadTiming: execution.backendLoadTiming,
            transcriptionTiming: execution.transcriptionTiming
        )
    }

    func executeRefinement(request: RefinementRequest) async throws -> RefinementExecutionResult {
        try await textRefinementBackend.refine(request: request)
    }

    private func transcriptionBackend(for family: TranscriptionBackendFamily) -> TranscriptionBackendAdapter {
        switch family {
        case .firstClassLocalNativeWhisperKit:
            return whisperKitBackend
        case .legacyCloudMultipart:
            return legacyCloudMultipartBackend
        case .legacyLocalServer:
            return legacyLocalWhisperServerBackend
        case .legacyCloudAudioInput:
            return legacyCloudAudioInputBackend
        }
    }

    private func resolveLanguageContext(for settings: PipelineSettingsSnapshot) -> (TranscriptionLanguageMode, String?) {
        guard settings.transcriptionProvider == .whisperKit else {
            return (.notApplicable, nil)
        }

        if settings.whisperKitLanguages.count == 1,
           let language = settings.whisperKitLanguages.first {
            return (.explicit, language.code)
        }

        return (.autoDetect, nil)
    }

    private func refinementContext(
        for settings: PipelineSettingsSnapshot,
        mode: TranscriptionPipelineMode
    ) -> (String?, String?, String?) {
        guard mode == .twoCallRefinement else {
            return (nil, nil, nil)
        }

        return (
            settings.refinementProvider.rawValue,
            settings.refinementModel,
            refinementConfigFingerprint(settings: settings)
        )
    }

    private func backendConfigFingerprint(
        settings: PipelineSettingsSnapshot,
        descriptor: TranscriptionBackendDescriptor,
        mode: TranscriptionPipelineMode,
        languageMode: TranscriptionLanguageMode,
        languageCode: String?
    ) -> String {
        if descriptor.provider == .whisperKit {
            let languages = settings.whisperKitLanguages.map(\.rawValue).sorted().joined(separator: ",")
            let resolvedLanguage = languageCode ?? "auto"
            return "provider=\(descriptor.provider.rawValue)|model=\(settings.transcriptionModel)|profile=\(settings.whisperKitProfile.rawValue)|language_mode=\(languageMode.rawValue)|language_code=\(resolvedLanguage)|languages=\(languages)|timestamps=\(settings.whisperKitEnableTimestamps)|vad=\(settings.whisperKitUseVAD)|prompt_prefill=\(settings.whisperKitPromptPrefill)|temperature=\(settings.whisperKitTemperature)|pipeline_mode=\(mode.rawValue)"
        }

        return "provider=\(descriptor.provider.rawValue)|model=\(settings.transcriptionModel)|base_url=\(settings.transcriptionBaseURL)|pipeline_mode=\(mode.rawValue)"
    }

    private func refinementConfigFingerprint(settings: PipelineSettingsSnapshot) -> String {
        "provider=\(settings.refinementProvider.rawValue)|model=\(settings.refinementModel)|base_url=\(settings.refinementBaseURL)"
    }
}
