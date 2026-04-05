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

    @MainActor
    func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding

    @MainActor
    func transcribe(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> String

    @MainActor
    func transcribeOutput(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitTranscriptionOutput

    @MainActor
    func inspectVADChunkDiagnostics(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitVADChunkDiagnostics?
}

extension WhisperKitTranscribing {
    @MainActor
    func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding {
        WhisperKitService.prepareDecoding(settings: settings)
    }

    @MainActor
    func transcribe(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> String {
        try await transcribe(audioURL: audioURL)
    }

    @MainActor
    func transcribeOutput(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitTranscriptionOutput {
        WhisperKitTranscriptionOutput(text: try await transcribe(audioURL: audioURL, preparedDecoding: preparedDecoding), segments: [])
    }

    @MainActor
    func inspectVADChunkDiagnostics(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitVADChunkDiagnostics? {
        nil
    }
}

extension WhisperKitService: WhisperKitTranscribing {}

private func logCaptureDiagnostics(_ event: String, captureID: String, metadata: [String: String] = [:]) {
    Task {
        await CaptureDiagnostics.shared.mark(event, captureID: captureID, metadata: metadata)
    }
}

private struct TranscriptionBackendExecution {
    let text: String
    let warmState: TranscriptionWarmState
    let backendLoadTiming: StageTiming?
    let transcriptionTiming: StageTiming
    let whisperKitRequestShape: WhisperKitDecodeRequestShape?
    let whisperKitSegmentCoverage: WhisperKitDecodedSegmentCoverageDiagnostics?
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
        let preparedDecoding = await whisperKitService.prepareDecoding(settings: request.settings)

        var backendLoadTiming: StageTiming?
        let warmState: TranscriptionWarmState

        if isWarm {
            warmState = .warmReady
            logCaptureDiagnostics("app.backend_load.skipped", captureID: request.captureID, metadata: [
                "provider": TranscriptionProvider.whisperKit.rawValue,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "reason": "already_loaded",
                "warm_state": warmState.rawValue
            ])
        } else {
            warmState = .coldLoad
            let loadStart = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_load.started", captureID: request.captureID, metadata: [
                "provider": TranscriptionProvider.whisperKit.rawValue,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "warm_state": warmState.rawValue
            ])

            do {
                try await whisperKitService.loadModel(model)
                let loadFinish = DispatchTime.now().uptimeNanoseconds
                backendLoadTiming = StageTiming(startedAt: loadStart, finishedAt: loadFinish)
                logCaptureDiagnostics("app.backend_load.completed", captureID: request.captureID, metadata: [
                    "provider": TranscriptionProvider.whisperKit.rawValue,
                    "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                    "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                    "model": model,
                    "warm_state": warmState.rawValue,
                    "elapsed_ms": String((loadFinish - loadStart) / 1_000_000)
                ])
            } catch {
                logCaptureDiagnostics("app.backend_load.failed", captureID: request.captureID, metadata: [
                    "provider": TranscriptionProvider.whisperKit.rawValue,
                    "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                    "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                    "model": model,
                    "warm_state": warmState.rawValue,
                    "reason": "load_model_failed",
                    "error": error.localizedDescription
                ])
                throw error
            }
        }

        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        var requestShapeMetadata = preparedDecoding.requestShape.diagnosticsMetadata
        requestShapeMetadata["provider"] = TranscriptionProvider.whisperKit.rawValue
        requestShapeMetadata["backend_kind"] = TranscriptionBackendKind.localNative.rawValue
        requestShapeMetadata["support_tier"] = TranscriptionSupportTier.firstClass.rawValue
        requestShapeMetadata["model"] = model
        requestShapeMetadata["warm_state"] = warmState.rawValue
        requestShapeMetadata["audio_duration_ms"] = String(request.audioDurationMs)
        logCaptureDiagnostics("app.backend_transcription.request_shape", captureID: request.captureID, metadata: requestShapeMetadata)

        do {
            if let chunkDiagnostics = try await whisperKitService.inspectVADChunkDiagnostics(
                audioURL: request.audioURL,
                preparedDecoding: preparedDecoding
            ) {
                var chunkMetadata = chunkDiagnostics.diagnosticsMetadata
                chunkMetadata["provider"] = TranscriptionProvider.whisperKit.rawValue
                chunkMetadata["backend_kind"] = TranscriptionBackendKind.localNative.rawValue
                chunkMetadata["support_tier"] = TranscriptionSupportTier.firstClass.rawValue
                chunkMetadata["model"] = model
                chunkMetadata["warm_state"] = warmState.rawValue
                logCaptureDiagnostics("app.backend_transcription.vad_chunks", captureID: request.captureID, metadata: chunkMetadata)
            }
        } catch {
            logCaptureDiagnostics("app.backend_transcription.vad_chunks_failed", captureID: request.captureID, metadata: [
                "provider": TranscriptionProvider.whisperKit.rawValue,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "warm_state": warmState.rawValue,
                "reason": "vad_chunk_inspection_failed",
                "error": error.localizedDescription
            ])
        }

        logCaptureDiagnostics("app.backend_transcription.started", captureID: request.captureID, metadata: [
            "provider": TranscriptionProvider.whisperKit.rawValue,
            "backend_kind": TranscriptionBackendKind.localNative.rawValue,
            "support_tier": TranscriptionSupportTier.firstClass.rawValue,
            "model": model,
            "warm_state": warmState.rawValue,
            "audio_duration_ms": String(request.audioDurationMs)
        ])

        do {
            let output = try await whisperKitService.transcribeOutput(audioURL: request.audioURL, preparedDecoding: preparedDecoding)
            let transcriptionFinish = DispatchTime.now().uptimeNanoseconds
            let segmentCoverage = WhisperKitService.summarizeDecodedSegmentCoverage(
                output.segments,
                processedAudioDurationMs: Int(request.audioDurationMs)
            )
            var segmentCoverageMetadata = segmentCoverage.diagnosticsMetadata
            segmentCoverageMetadata["provider"] = TranscriptionProvider.whisperKit.rawValue
            segmentCoverageMetadata["backend_kind"] = TranscriptionBackendKind.localNative.rawValue
            segmentCoverageMetadata["support_tier"] = TranscriptionSupportTier.firstClass.rawValue
            segmentCoverageMetadata["model"] = model
            segmentCoverageMetadata["warm_state"] = warmState.rawValue
            logCaptureDiagnostics("app.backend_transcription.segment_coverage", captureID: request.captureID, metadata: segmentCoverageMetadata)
            logCaptureDiagnostics("app.backend_transcription.completed", captureID: request.captureID, metadata: [
                "provider": TranscriptionProvider.whisperKit.rawValue,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "warm_state": warmState.rawValue,
                "elapsed_ms": String((transcriptionFinish - transcriptionStart) / 1_000_000),
                "characters": String(output.text.count)
            ])

            return TranscriptionBackendExecution(
                text: output.text,
                warmState: warmState,
                backendLoadTiming: backendLoadTiming,
                transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish),
                whisperKitRequestShape: preparedDecoding.requestShape,
                whisperKitSegmentCoverage: segmentCoverage
            )
        } catch {
            let failureTime = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.failed", captureID: request.captureID, metadata: [
                "provider": TranscriptionProvider.whisperKit.rawValue,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "warm_state": warmState.rawValue,
                "elapsed_ms": String((failureTime - transcriptionStart) / 1_000_000),
                "reason": "backend_transcription_failed",
                "error": error.localizedDescription
            ])
            throw error
        }
    }
}

private struct LegacyCloudMultipartTranscriptionBackend: TranscriptionBackendAdapter {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        logCaptureDiagnostics("app.backend_transcription.started", captureID: request.captureID, metadata: [
            "provider": request.settings.transcriptionProvider.rawValue,
            "backend_kind": TranscriptionBackendKind.cloud.rawValue,
            "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
            "model": request.settings.transcriptionModel,
            "warm_state": TranscriptionWarmState.notApplicable.rawValue,
            "audio_duration_ms": String(request.audioDurationMs)
        ])

        do {
            let text = try await network.transcribeOpenAICompatible(
                audioURL: request.audioURL,
                apiKey: request.settings.transcriptionAPIKey,
                baseURL: request.settings.transcriptionBaseURL,
                model: request.settings.transcriptionModel
            )
            let transcriptionFinish = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.completed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.cloud.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.notApplicable.rawValue,
                "elapsed_ms": String((transcriptionFinish - transcriptionStart) / 1_000_000),
                "characters": String(text.count)
            ])

            return TranscriptionBackendExecution(
                text: text,
                warmState: .notApplicable,
                backendLoadTiming: nil,
                transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish),
                whisperKitRequestShape: nil,
                whisperKitSegmentCoverage: nil
            )
        } catch {
            let failureTime = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.failed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.cloud.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.notApplicable.rawValue,
                "elapsed_ms": String((failureTime - transcriptionStart) / 1_000_000),
                "reason": "backend_transcription_failed",
                "error": error.localizedDescription
            ])
            throw error
        }
    }
}

private struct LegacyLocalWhisperServerBackend: TranscriptionBackendAdapter {
    private let network: LegacyTranscriptionNetworking

    init(network: LegacyTranscriptionNetworking) {
        self.network = network
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        logCaptureDiagnostics("app.backend_transcription.started", captureID: request.captureID, metadata: [
            "provider": request.settings.transcriptionProvider.rawValue,
            "backend_kind": TranscriptionBackendKind.localServer.rawValue,
            "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
            "model": request.settings.transcriptionModel,
            "warm_state": TranscriptionWarmState.unknownServerState.rawValue,
            "audio_duration_ms": String(request.audioDurationMs)
        ])

        do {
            let text = try await network.transcribeLocalWhisper(
                audioURL: request.audioURL,
                baseURL: request.settings.transcriptionBaseURL
            )
            let transcriptionFinish = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.completed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.localServer.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.unknownServerState.rawValue,
                "elapsed_ms": String((transcriptionFinish - transcriptionStart) / 1_000_000),
                "characters": String(text.count)
            ])

            return TranscriptionBackendExecution(
                text: text,
                warmState: .unknownServerState,
                backendLoadTiming: nil,
                transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish),
                whisperKitRequestShape: nil,
                whisperKitSegmentCoverage: nil
            )
        } catch {
            let failureTime = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.failed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.localServer.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.unknownServerState.rawValue,
                "elapsed_ms": String((failureTime - transcriptionStart) / 1_000_000),
                "reason": "backend_transcription_failed",
                "error": error.localizedDescription
            ])
            throw error
        }
    }
}

private struct CohereMLXTranscriptionBackend: TranscriptionBackendAdapter {
    private let cohereService: CohereMLXService

    init(cohereService: CohereMLXService) {
        self.cohereService = cohereService
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        let language = "en"  // English-only in Phase 7B
        let warmState: TranscriptionWarmState = await cohereService.modelState == .ready ? .warmReady : .coldLoad

        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        let text = try await cohereService.transcribe(audioURL: request.audioURL, language: language)
        let transcriptionFinish = DispatchTime.now().uptimeNanoseconds

        return TranscriptionBackendExecution(
            text: text,
            warmState: warmState,
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
        logCaptureDiagnostics("app.backend_transcription.started", captureID: request.captureID, metadata: [
            "provider": request.settings.transcriptionProvider.rawValue,
            "backend_kind": TranscriptionBackendKind.cloud.rawValue,
            "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
            "model": request.settings.transcriptionModel,
            "warm_state": TranscriptionWarmState.notApplicable.rawValue,
            "audio_duration_ms": String(request.audioDurationMs)
        ])

        do {
            let text = try await network.transcribeCloudAudioInput(
                audioURL: request.audioURL,
                provider: request.settings.transcriptionProvider,
                apiKey: request.settings.transcriptionAPIKey,
                baseURL: request.settings.transcriptionBaseURL,
                model: request.settings.transcriptionModel,
                systemPrompt: request.baselinePrompt
            )
            let transcriptionFinish = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.completed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.cloud.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.notApplicable.rawValue,
                "elapsed_ms": String((transcriptionFinish - transcriptionStart) / 1_000_000),
                "characters": String(text.count)
            ])

            return TranscriptionBackendExecution(
                text: text,
                warmState: .notApplicable,
                backendLoadTiming: nil,
                transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish),
                whisperKitRequestShape: nil,
                whisperKitSegmentCoverage: nil
            )
        } catch {
            let failureTime = DispatchTime.now().uptimeNanoseconds
            logCaptureDiagnostics("app.backend_transcription.failed", captureID: request.captureID, metadata: [
                "provider": request.settings.transcriptionProvider.rawValue,
                "backend_kind": TranscriptionBackendKind.cloud.rawValue,
                "support_tier": TranscriptionSupportTier.legacyCompatibility.rawValue,
                "model": request.settings.transcriptionModel,
                "warm_state": TranscriptionWarmState.notApplicable.rawValue,
                "elapsed_ms": String((failureTime - transcriptionStart) / 1_000_000),
                "reason": "backend_transcription_failed",
                "error": error.localizedDescription
            ])
            throw error
        }
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
        whisperKitService: WhisperKitService.shared,
        cohereMLXService: CohereMLXService.shared
    )

    private let whisperKitBackend: WhisperKitTranscriptionBackend
    private let cohereMLXBackend: CohereMLXTranscriptionBackend
    private let legacyCloudMultipartBackend: LegacyCloudMultipartTranscriptionBackend
    private let legacyLocalWhisperServerBackend: LegacyLocalWhisperServerBackend
    private let legacyCloudAudioInputBackend: LegacyCloudAudioInputBackend
    private let textRefinementBackend: TextRefinementBackend

    init(
        network: LegacyTranscriptionNetworking,
        whisperKitService: WhisperKitTranscribing,
        cohereMLXService: CohereMLXService
    ) {
        whisperKitBackend = WhisperKitTranscriptionBackend(whisperKitService: whisperKitService)
        cohereMLXBackend = CohereMLXTranscriptionBackend(cohereService: cohereMLXService)
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

        let languageMode: TranscriptionLanguageMode
        let languageCode: String?
        if let requestShape = execution.whisperKitRequestShape {
            languageMode = requestShape.languageMode
            languageCode = requestShape.languageCode
        } else {
            (languageMode, languageCode) = resolveLanguageContext(for: request.settings)
        }

        let (refinementProvider, refinementModel, refinementConfigFingerprint) = refinementContext(for: request.settings, mode: mode)
        let resolvedBackendConfigFingerprint: String
        if let requestShape = execution.whisperKitRequestShape {
            resolvedBackendConfigFingerprint = requestShape.backendConfigFingerprint(
                provider: descriptor.provider,
                model: request.settings.transcriptionModel,
                pipelineMode: mode
            )
        } else {
            resolvedBackendConfigFingerprint = backendConfigFingerprint(
                settings: request.settings,
                descriptor: descriptor,
                mode: mode,
                languageMode: languageMode,
                languageCode: languageCode
            )
        }

        let runContext = TranscriptionRunContext(
            provider: descriptor.provider.rawValue,
            backendKind: descriptor.kind,
            supportTier: descriptor.supportTier,
            pipelineMode: mode,
            model: request.settings.transcriptionModel,
            backendConfigFingerprint: resolvedBackendConfigFingerprint,
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
        case .firstClassLocalNativeCohereMLX:
            return cohereMLXBackend
        case .legacyCloudMultipart:
            return legacyCloudMultipartBackend
        case .legacyLocalServer:
            return legacyLocalWhisperServerBackend
        case .legacyCloudAudioInput:
            return legacyCloudAudioInputBackend
        }
    }

    private func resolveLanguageContext(for settings: PipelineSettingsSnapshot) -> (TranscriptionLanguageMode, String?) {
        switch settings.transcriptionProvider {
        case .whisperKit:
            if settings.whisperKitLanguages.count == 1,
               let language = settings.whisperKitLanguages.first {
                return (.explicit, language.code)
            }
            return (.autoDetect, nil)
        case .cohereMLX:
            return (.explicit, "en")  // English-only in Phase 7B
        default:
            return (.notApplicable, nil)
        }
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
