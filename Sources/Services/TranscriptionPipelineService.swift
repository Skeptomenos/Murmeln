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
    func transcribe(audioURL: URL, languageCode: String?) async throws -> String

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

struct TranscriptionBackendExecution {
    let text: String
    let warmState: TranscriptionWarmState
    let backendLoadTiming: StageTiming?
    let transcriptionTiming: StageTiming
    let whisperKitRequestShape: WhisperKitDecodeRequestShape?
    let whisperKitSegmentCoverage: WhisperKitDecodedSegmentCoverageDiagnostics?
    // Phase 8 additive telemetry: which runtime served the capture.
    var runtimeID: String? = nil
    var quantization: String? = nil
}

protocol TranscriptionBackendAdapter {
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution
}

/// Phase 8 generic local-native adapter (Slice 2). One adapter serves every
/// catalog-driven runtime; WhisperKit's decode-shape/VAD/segment-coverage
/// diagnostics ride the optional `whisperKitHook` (nil for other runtimes),
/// keeping its telemetry byte-identical to the pre-Phase-8 adapter (proven
/// by WhisperKitGoldenMasterTests).
struct RuntimeTranscriptionBackend: TranscriptionBackendAdapter {
    private let whisperKitHook: WhisperKitTranscribing?
    private let runtime: (any TranscriptionRuntime)?
    private let providerLabel: String
    private let runtimeLabel: String
    private let resolveModelID: @Sendable (TranscriptionRequest) -> TranscriptionModelID
    private let resolveLanguageCode: @Sendable (TranscriptionRequest) -> String?
    private let resolveQuantization: @Sendable (TranscriptionRequest) -> String?

    static func whisperKit(_ service: WhisperKitTranscribing) -> RuntimeTranscriptionBackend {
        RuntimeTranscriptionBackend(
            whisperKitHook: service,
            runtime: nil,
            providerLabel: TranscriptionProvider.whisperKit.rawValue,
            runtimeLabel: RuntimeID.whisperKit.rawValue,
            resolveModelID: { TranscriptionModelID(rawValue: $0.settings.transcriptionModel) },
            resolveLanguageCode: { _ in nil },
            resolveQuantization: { _ in nil }
        )
    }

    /// Generic lane for catalog runtimes (Slice 3/4). The catalog model ID
    /// travels in `settings.selectedCatalogModelID`; language comes from the
    /// unified `preferredLanguage` resolved per model capability.
    static func runtime(
        _ runtime: any TranscriptionRuntime,
        providerLabel: String
    ) -> RuntimeTranscriptionBackend {
        RuntimeTranscriptionBackend(
            whisperKitHook: nil,
            runtime: runtime,
            providerLabel: providerLabel,
            runtimeLabel: "",
            resolveModelID: { TranscriptionModelID(rawValue: $0.settings.selectedCatalogModelID) },
            resolveLanguageCode: { request in
                AppSettings.resolvedLanguageCode(
                    preferred: request.settings.preferredLanguage,
                    for: TranscriptionModelID(rawValue: request.settings.selectedCatalogModelID))
            },
            resolveQuantization: { request in
                ModelCatalog.entry(for: TranscriptionModelID(rawValue: request.settings.selectedCatalogModelID))?.quantization
            }
        )
    }

    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionBackendExecution {
        if let whisperKitHook {
            return try await transcribeWhisperKit(service: whisperKitHook, request: request)
        }
        guard let runtime else {
            fatalError("RuntimeTranscriptionBackend constructed without a lane")
        }
        return try await transcribeGeneric(runtime: runtime, request: request)
    }

    // MARK: Generic runtime lane

    private func transcribeGeneric(
        runtime: any TranscriptionRuntime,
        request: TranscriptionRequest
    ) async throws -> TranscriptionBackendExecution {
        let modelID = resolveModelID(request)
        let model = modelID.rawValue
        let runtimeName = await runtime.id.rawValue
        let quantization = resolveQuantization(request)

        var baseMetadata: [String: String] {
            [
                "provider": providerLabel,
                "backend_kind": TranscriptionBackendKind.localNative.rawValue,
                "support_tier": TranscriptionSupportTier.firstClass.rawValue,
                "model": model,
                "runtime": runtimeName
            ]
        }

        let isWarm = await runtime.isReady(modelID)
        var backendLoadTiming: StageTiming?
        let warmState: TranscriptionWarmState

        if isWarm {
            warmState = .warmReady
            var metadata = baseMetadata
            metadata["reason"] = "already_loaded"
            metadata["warm_state"] = warmState.rawValue
            logCaptureDiagnostics("app.backend_load.skipped", captureID: request.captureID, metadata: metadata)
        } else {
            warmState = .coldLoad
            let loadStart = DispatchTime.now().uptimeNanoseconds
            var startMetadata = baseMetadata
            startMetadata["warm_state"] = warmState.rawValue
            logCaptureDiagnostics("app.backend_load.started", captureID: request.captureID, metadata: startMetadata)

            do {
                try await runtime.load(modelID)
                let loadFinish = DispatchTime.now().uptimeNanoseconds
                backendLoadTiming = StageTiming(startedAt: loadStart, finishedAt: loadFinish)
                var doneMetadata = startMetadata
                doneMetadata["elapsed_ms"] = String((loadFinish - loadStart) / 1_000_000)
                logCaptureDiagnostics("app.backend_load.completed", captureID: request.captureID, metadata: doneMetadata)
            } catch {
                var failMetadata = startMetadata
                failMetadata["reason"] = "load_model_failed"
                failMetadata["error"] = error.localizedDescription
                logCaptureDiagnostics("app.backend_load.failed", captureID: request.captureID, metadata: failMetadata)
                throw error
            }
        }

        let transcriptionStart = DispatchTime.now().uptimeNanoseconds
        var startedMetadata = baseMetadata
        startedMetadata["warm_state"] = warmState.rawValue
        startedMetadata["audio_duration_ms"] = String(request.audioDurationMs)
        logCaptureDiagnostics("app.backend_transcription.started", captureID: request.captureID, metadata: startedMetadata)

        do {
            let options = TranscriptionOptions(languageCode: resolveLanguageCode(request))
            let text = try await runtime.transcribe(audioURL: request.audioURL, options: options)
            let transcriptionFinish = DispatchTime.now().uptimeNanoseconds
            var completedMetadata = startedMetadata
            completedMetadata["elapsed_ms"] = String((transcriptionFinish - transcriptionStart) / 1_000_000)
            completedMetadata["characters"] = String(text.count)
            logCaptureDiagnostics("app.backend_transcription.completed", captureID: request.captureID, metadata: completedMetadata)

            return TranscriptionBackendExecution(
                text: text,
                warmState: warmState,
                backendLoadTiming: backendLoadTiming,
                transcriptionTiming: StageTiming(startedAt: transcriptionStart, finishedAt: transcriptionFinish),
                whisperKitRequestShape: nil,
                whisperKitSegmentCoverage: nil,
                runtimeID: runtimeName,
                quantization: quantization
            )
        } catch {
            let failureTime = DispatchTime.now().uptimeNanoseconds
            var failMetadata = startedMetadata
            failMetadata["elapsed_ms"] = String((failureTime - transcriptionStart) / 1_000_000)
            failMetadata["reason"] = "backend_transcription_failed"
            failMetadata["error"] = error.localizedDescription
            logCaptureDiagnostics("app.backend_transcription.failed", captureID: request.captureID, metadata: failMetadata)
            throw error
        }
    }

    // MARK: WhisperKit diagnostics-rich lane (telemetry contract under golden master)

    private func transcribeWhisperKit(
        service whisperKitService: WhisperKitTranscribing,
        request: TranscriptionRequest
    ) async throws -> TranscriptionBackendExecution {
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
                whisperKitSegmentCoverage: segmentCoverage,
                runtimeID: runtimeLabel,
                quantization: nil
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
        whisperKitService: WhisperKitService.shared
    )

    private let whisperKitBackend: RuntimeTranscriptionBackend
    private let legacyCloudMultipartBackend: LegacyCloudMultipartTranscriptionBackend
    private let legacyLocalWhisperServerBackend: LegacyLocalWhisperServerBackend
    private let legacyCloudAudioInputBackend: LegacyCloudAudioInputBackend
    private let textRefinementBackend: TextRefinementBackend
    /// Phase 8: catalog-model lane, keyed by RuntimeID (built lazily on the
    /// main actor because runtimes are MainActor singletons).
    private let makeCatalogBackend: @Sendable (RuntimeID) async -> RuntimeTranscriptionBackend

    init(
        network: LegacyTranscriptionNetworking,
        whisperKitService: WhisperKitTranscribing,
        makeCatalogBackend: @escaping @Sendable (RuntimeID) async -> RuntimeTranscriptionBackend = { runtimeID in
            await MainActor.run {
                switch runtimeID {
                case .fluidAudio:
                    return RuntimeTranscriptionBackend.runtime(FluidAudioRuntime.shared, providerLabel: "fluidAudio")
                case .whisperKit:
                    return RuntimeTranscriptionBackend.runtime(WhisperKitRuntime.shared, providerLabel: "whisperKitRuntime")
                }
            }
        }
    ) {
        whisperKitBackend = RuntimeTranscriptionBackend.whisperKit(whisperKitService)
        legacyCloudMultipartBackend = LegacyCloudMultipartTranscriptionBackend(network: network)
        legacyLocalWhisperServerBackend = LegacyLocalWhisperServerBackend(network: network)
        legacyCloudAudioInputBackend = LegacyCloudAudioInputBackend(network: network)
        textRefinementBackend = TextRefinementBackend(network: network)
        self.makeCatalogBackend = makeCatalogBackend
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
        // Phase 8: a selected catalog model takes precedence over the legacy
        // provider enum (which remains authoritative for cloud/server).
        if !request.settings.selectedCatalogModelID.isEmpty,
           let entry = ModelCatalog.entry(for: TranscriptionModelID(rawValue: request.settings.selectedCatalogModelID)) {
            return try await executeCatalogTranscription(request: request, entry: entry)
        }

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
            refinementEnabled: !request.settings.skipRefinement,
            runtimeID: execution.runtimeID,
            quantization: execution.quantization
        )

        return TranscriptionExecutionResult(
            text: execution.text,
            runContext: runContext,
            backendLoadTiming: execution.backendLoadTiming,
            transcriptionTiming: execution.transcriptionTiming
        )
    }

    /// Phase 8 catalog lane: local-native models run transcribe-only or
    /// two-call refinement (no catalog model does one-call refinement).
    private func executeCatalogTranscription(
        request: TranscriptionRequest,
        entry: CatalogEntry
    ) async throws -> TranscriptionExecutionResult {
        let mode: TranscriptionPipelineMode = request.settings.skipRefinement ? .transcribeOnly : .twoCallRefinement
        let backend = await makeCatalogBackend(entry.runtime)
        let execution = try await backend.transcribe(request: request)

        let resolvedLanguage = AppSettings.resolvedLanguageCode(
            preferred: request.settings.preferredLanguage, for: entry.id)
        let languageMode: TranscriptionLanguageMode = switch entry.languageMode {
        case .hintRequired: .explicit
        case .autoDetect: resolvedLanguage == nil ? .autoDetect : .explicit
        }

        let (refinementProvider, refinementModel, refinementConfigFingerprint) = refinementContext(for: request.settings, mode: mode)
        let fingerprint = "provider=\(entry.runtime.rawValue)|model=\(entry.id.rawValue)|language_mode=\(languageMode.rawValue)|language_code=\(resolvedLanguage ?? "auto")|pipeline_mode=\(mode.rawValue)"

        let runContext = TranscriptionRunContext(
            provider: entry.runtime.rawValue,
            backendKind: .localNative,
            supportTier: .firstClass,
            pipelineMode: mode,
            model: entry.id.rawValue,
            backendConfigFingerprint: fingerprint,
            refinementProvider: refinementProvider,
            refinementModel: refinementModel,
            refinementConfigFingerprint: refinementConfigFingerprint,
            languageMode: languageMode,
            languageCode: resolvedLanguage,
            audioDurationMs: request.audioDurationMs,
            warmState: execution.warmState,
            refinementEnabled: !request.settings.skipRefinement,
            runtimeID: execution.runtimeID,
            quantization: execution.quantization
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
        switch settings.transcriptionProvider {
        case .whisperKit:
            if settings.whisperKitLanguages.count == 1,
               let language = settings.whisperKitLanguages.first {
                return (.explicit, language.code)
            }
            return (.autoDetect, nil)
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
