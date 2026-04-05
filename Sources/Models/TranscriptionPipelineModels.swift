import Foundation

enum TranscriptionBackendKind: String, Codable, CaseIterable, Sendable {
    case localNative = "local_native"
    case cloud = "cloud"
    case localServer = "local_server"
}

enum TranscriptionSupportTier: String, Codable, CaseIterable, Sendable {
    case firstClass = "first_class"
    case legacyCompatibility = "legacy_compatibility"
}

enum TranscriptionBackendFamily: String, Codable, CaseIterable, Sendable {
    case firstClassLocalNativeWhisperKit = "first_class_local_native_whisperkit"
    case legacyCloudMultipart = "legacy_cloud_multipart"
    case legacyLocalServer = "legacy_local_server"
    case legacyCloudAudioInput = "legacy_cloud_audio_input"
}

enum TranscriptionPipelineMode: String, Codable, CaseIterable, Sendable {
    case transcribeOnly = "transcribe_only"
    case oneCallTranscriptionAndRefinement = "one_call_transcription_refinement"
    case twoCallRefinement = "two_call_refinement"
}

enum TranscriptionWarmState: String, Codable, CaseIterable, Sendable {
    case warmReady = "warm_ready"
    case coldLoad = "cold_load"
    case notApplicable = "not_applicable"
    case unknownServerState = "unknown_server_state"
}

enum TranscriptionLanguageMode: String, Codable, CaseIterable, Sendable {
    case explicit = "explicit"
    case autoDetect = "auto_detect"
    case notApplicable = "not_applicable"
}

struct TranscriptionBackendCapabilities: Codable, Sendable {
    let requiresAPIKey: Bool
    let supportsOneCallRefinement: Bool
    let supportsLanguageOverride: Bool
    let supportsLocalModelLifecycle: Bool
    let isNetworked: Bool
    let requiresInstallOrDownload: Bool
}

struct TranscriptionBackendDescriptor: Codable, Sendable {
    let provider: TranscriptionProvider
    let kind: TranscriptionBackendKind
    let supportTier: TranscriptionSupportTier
    let family: TranscriptionBackendFamily
    let capabilities: TranscriptionBackendCapabilities
}

extension TranscriptionProvider {
    var backendDescriptor: TranscriptionBackendDescriptor {
        switch self {
        case .whisperKit:
            return TranscriptionBackendDescriptor(
                provider: self,
                kind: .localNative,
                supportTier: .firstClass,
                family: .firstClassLocalNativeWhisperKit,
                capabilities: TranscriptionBackendCapabilities(
                    requiresAPIKey: false,
                    supportsOneCallRefinement: false,
                    supportsLanguageOverride: true,
                    supportsLocalModelLifecycle: true,
                    isNetworked: false,
                    requiresInstallOrDownload: true
                )
            )
        case .openAIWhisper, .groqWhisper:
            return TranscriptionBackendDescriptor(
                provider: self,
                kind: .cloud,
                supportTier: .legacyCompatibility,
                family: .legacyCloudMultipart,
                capabilities: TranscriptionBackendCapabilities(
                    requiresAPIKey: true,
                    supportsOneCallRefinement: false,
                    supportsLanguageOverride: false,
                    supportsLocalModelLifecycle: false,
                    isNetworked: true,
                    requiresInstallOrDownload: false
                )
            )
        case .gpt4oAudio, .geminiAudio:
            return TranscriptionBackendDescriptor(
                provider: self,
                kind: .cloud,
                supportTier: .legacyCompatibility,
                family: .legacyCloudAudioInput,
                capabilities: TranscriptionBackendCapabilities(
                    requiresAPIKey: true,
                    supportsOneCallRefinement: true,
                    supportsLanguageOverride: false,
                    supportsLocalModelLifecycle: false,
                    isNetworked: true,
                    requiresInstallOrDownload: false
                )
            )
        case .localWhisper:
            return TranscriptionBackendDescriptor(
                provider: self,
                kind: .localServer,
                supportTier: .legacyCompatibility,
                family: .legacyLocalServer,
                capabilities: TranscriptionBackendCapabilities(
                    requiresAPIKey: false,
                    supportsOneCallRefinement: false,
                    supportsLanguageOverride: false,
                    supportsLocalModelLifecycle: false,
                    isNetworked: true,
                    requiresInstallOrDownload: false
                )
            )
        }
    }
}

struct PipelineSettingsSnapshot {
    let transcriptionProvider: TranscriptionProvider
    let transcriptionAPIKey: String
    let transcriptionBaseURL: String
    let transcriptionModel: String
    let refinementProvider: Provider
    let refinementAPIKey: String
    let refinementBaseURL: String
    let refinementModel: String
    let skipRefinement: Bool
    let parallelRefinementEnabled: Bool
    let whisperKitProfile: WhisperKitProfile
    let whisperKitTemperature: Double
    let whisperKitPromptPrefill: Bool
    let whisperKitEnableTimestamps: Bool
    let whisperKitUseVAD: Bool
    let whisperKitLanguages: [WhisperKitLanguage]

    var usesWhisperKit: Bool {
        transcriptionProvider == .whisperKit
    }
}

@MainActor
extension AppSettings {
    func pipelineSettingsSnapshot() -> PipelineSettingsSnapshot {
        PipelineSettingsSnapshot(
            transcriptionProvider: transcriptionProvider,
            transcriptionAPIKey: transcriptionAPIKey,
            transcriptionBaseURL: transcriptionBaseURL,
            transcriptionModel: transcriptionProvider == .whisperKit ? whisperKitModel : transcriptionModel,
            refinementProvider: refinementProvider,
            refinementAPIKey: refinementAPIKey,
            refinementBaseURL: refinementBaseURL,
            refinementModel: refinementModel,
            skipRefinement: skipRefinement,
            parallelRefinementEnabled: parallelRefinementEnabled,
            whisperKitProfile: whisperKitProfile,
            whisperKitTemperature: whisperKitTemperature,
            whisperKitPromptPrefill: whisperKitPromptPrefill,
            whisperKitEnableTimestamps: whisperKitEnableTimestamps,
            whisperKitUseVAD: whisperKitUseVAD,
            whisperKitLanguages: whisperKitLanguages
        )
    }
}

struct StageTiming {
    let startedAt: UInt64
    let finishedAt: UInt64

    var elapsedMs: UInt64 {
        guard finishedAt >= startedAt else { return 0 }
        return (finishedAt - startedAt) / 1_000_000
    }
}

struct TranscriptionRunContext {
    let provider: String
    let backendKind: TranscriptionBackendKind
    let supportTier: TranscriptionSupportTier
    let pipelineMode: TranscriptionPipelineMode
    let model: String
    let backendConfigFingerprint: String
    let refinementProvider: String?
    let refinementModel: String?
    let refinementConfigFingerprint: String?
    let languageMode: TranscriptionLanguageMode
    let languageCode: String?
    let audioDurationMs: UInt64
    let warmState: TranscriptionWarmState
    let refinementEnabled: Bool
}

struct TranscriptionRequest {
    let captureID: String
    let audioURL: URL
    let audioDurationMs: UInt64
    let baselinePrompt: String
    let settings: PipelineSettingsSnapshot
}

struct WhisperKitDecodeRequestShape: Sendable, Equatable {
    let profile: String
    let languageMode: TranscriptionLanguageMode
    let languageCode: String?
    let declaredLanguages: [String]
    let detectLanguage: Bool
    let usePrefillPrompt: Bool
    let usePrefillCache: Bool
    let withoutTimestamps: Bool
    let suppressBlank: Bool
    let suppressTokens: [Int]
    let droppedSuppressTokens: [Int]
    let temperature: Double
    let temperatureFallbackCount: Int
    let noSpeechThreshold: Double?
    let concurrentWorkerCount: Int
    let chunkingStrategy: String

    var diagnosticsMetadata: [String: String] {
        let suppressTokensValue = suppressTokens.map { String($0) }.joined(separator: ",")
        let droppedSuppressTokensValue = droppedSuppressTokens.map { String($0) }.joined(separator: ",")
        let noSpeechThresholdValue = noSpeechThreshold.map { String($0) } ?? "nil"

        return [
            "profile": profile,
            "language_mode": languageMode.rawValue,
            "language_code": languageCode ?? "auto",
            "declared_languages": declaredLanguages.isEmpty ? "none" : declaredLanguages.joined(separator: ","),
            "detect_language": String(detectLanguage),
            "prompt_prefill": String(usePrefillPrompt),
            "prefill_cache": String(usePrefillCache),
            "without_timestamps": String(withoutTimestamps),
            "suppress_blank": String(suppressBlank),
            "suppress_tokens": suppressTokensValue,
            "dropped_suppress_tokens": droppedSuppressTokensValue,
            "temperature": String(temperature),
            "temperature_fallback_count": String(temperatureFallbackCount),
            "no_speech_threshold": noSpeechThresholdValue,
            "concurrent_worker_count": String(concurrentWorkerCount),
            "chunking": chunkingStrategy
        ]
    }

    func backendConfigFingerprint(
        provider: TranscriptionProvider,
        model: String,
        pipelineMode: TranscriptionPipelineMode
    ) -> String {
        let suppressTokensValue = suppressTokens.map { String($0) }.joined(separator: ",")
        let droppedSuppressTokensValue = droppedSuppressTokens.map { String($0) }.joined(separator: ",")
        let noSpeechThresholdValue = noSpeechThreshold.map { String($0) } ?? "nil"

        return "provider=\(provider.rawValue)|model=\(model)|profile=\(profile)|language_mode=\(languageMode.rawValue)|language_code=\(languageCode ?? "auto")|languages=\(declaredLanguages.joined(separator: ","))|detect_language=\(detectLanguage)|prompt_prefill=\(usePrefillPrompt)|prefill_cache=\(usePrefillCache)|without_timestamps=\(withoutTimestamps)|suppress_blank=\(suppressBlank)|suppress_tokens=\(suppressTokensValue)|dropped_suppress_tokens=\(droppedSuppressTokensValue)|temperature=\(temperature)|temperature_fallback_count=\(temperatureFallbackCount)|no_speech_threshold=\(noSpeechThresholdValue)|concurrent_worker_count=\(concurrentWorkerCount)|chunking=\(chunkingStrategy)|pipeline_mode=\(pipelineMode.rawValue)"
    }
}

struct TranscriptionExecutionResult {
    let text: String
    let runContext: TranscriptionRunContext
    let backendLoadTiming: StageTiming?
    let transcriptionTiming: StageTiming
}

struct RefinementRequest {
    let captureID: String
    let text: String
    let systemPrompt: String
    let settings: PipelineSettingsSnapshot
}

struct RefinementExecutionResult {
    let text: String
    let timing: StageTiming
}

struct CaptureStageTimeline {
    let stopRequestedAt: UInt64
    let audioReadyAt: UInt64
    let backendLoadStartedAt: UInt64?
    let backendLoadFinishedAt: UInt64?
    let transcriptionStartedAt: UInt64
    let transcriptionFinishedAt: UInt64
    let refinementStartedAt: UInt64?
    let refinementFinishedAt: UInt64?
    // Selected-result readiness can precede full audit completion when Parallel Audit fanout is enabled.
    let selectedResultReadyAt: UInt64?
    // Full backend fanout completion for Parallel Audit, including any selected-preset retry work.
    let auditFanoutFinishedAt: UInt64?
    let auditVariantSuccessCount: Int
    let auditVariantFailureCount: Int
    // Final-result readiness is the timestamp that actually gates paste for the current path.
    let finalResultReadyAt: UInt64
    let pasteCommandSentAt: UInt64
    let pasteCompletedAt: UInt64
    let pasteSucceeded: Bool

    init(
        stopRequestedAt: UInt64,
        audioReadyAt: UInt64,
        backendLoadStartedAt: UInt64?,
        backendLoadFinishedAt: UInt64?,
        transcriptionStartedAt: UInt64,
        transcriptionFinishedAt: UInt64,
        refinementStartedAt: UInt64?,
        refinementFinishedAt: UInt64?,
        selectedResultReadyAt: UInt64? = nil,
        auditFanoutFinishedAt: UInt64? = nil,
        auditVariantSuccessCount: Int = 0,
        auditVariantFailureCount: Int = 0,
        finalResultReadyAt: UInt64,
        pasteCommandSentAt: UInt64,
        pasteCompletedAt: UInt64,
        pasteSucceeded: Bool
    ) {
        self.stopRequestedAt = stopRequestedAt
        self.audioReadyAt = audioReadyAt
        self.backendLoadStartedAt = backendLoadStartedAt
        self.backendLoadFinishedAt = backendLoadFinishedAt
        self.transcriptionStartedAt = transcriptionStartedAt
        self.transcriptionFinishedAt = transcriptionFinishedAt
        self.refinementStartedAt = refinementStartedAt
        self.refinementFinishedAt = refinementFinishedAt
        self.selectedResultReadyAt = selectedResultReadyAt
        self.auditFanoutFinishedAt = auditFanoutFinishedAt
        self.auditVariantSuccessCount = auditVariantSuccessCount
        self.auditVariantFailureCount = auditVariantFailureCount
        self.finalResultReadyAt = finalResultReadyAt
        self.pasteCommandSentAt = pasteCommandSentAt
        self.pasteCompletedAt = pasteCompletedAt
        self.pasteSucceeded = pasteSucceeded
    }
}

enum CaptureTrimResult: String, Sendable {
    case notApplicable = "not_applicable"
    case disabled = "disabled"
    case completed = "completed"
    case skipped = "skipped"
}

struct CaptureProcessingObservations: Sendable {
    let rawAudioDurationMs: UInt64
    let rawAudioFileSizeBytes: Int
    let processedAudioDurationMs: UInt64
    let processedAudioFileSizeBytes: Int
    let speechDetected: Bool
    let trimResult: CaptureTrimResult
    let transcriptionCharacterCount: Int
    let completionReason: String

    static let empty = CaptureProcessingObservations(
        rawAudioDurationMs: 0,
        rawAudioFileSizeBytes: 0,
        processedAudioDurationMs: 0,
        processedAudioFileSizeBytes: 0,
        speechDetected: false,
        trimResult: .notApplicable,
        transcriptionCharacterCount: 0,
        completionReason: "not_recorded"
    )
}

struct CaptureCompletionOutcome: Sendable, Equatable {
    static let shortAudioUpperBoundMs: UInt64 = 1_000

    let completionOutcome: String
    let completionReason: String
    let userFacingMessage: String?

    static func classify(
        transcriptionText: String,
        pasteSucceeded: Bool,
        processedAudioDurationMs: UInt64,
        speechDetected: Bool
    ) -> CaptureCompletionOutcome {
        if pasteSucceeded {
            return CaptureCompletionOutcome(
                completionOutcome: "completed",
                completionReason: "paste_completed",
                userFacingMessage: nil
            )
        }

        let trimmedText = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedText.isEmpty,
           speechDetected,
           processedAudioDurationMs > 0,
           processedAudioDurationMs <= shortAudioUpperBoundMs {
            return CaptureCompletionOutcome(
                completionOutcome: "completed_no_paste",
                completionReason: "short_audio_empty_decode",
                userFacingMessage: "Too short to transcribe reliably."
            )
        }

        return CaptureCompletionOutcome(
            completionOutcome: "completed_no_paste",
            completionReason: "empty_transcript_skipped",
            userFacingMessage: nil
        )
    }
}

struct CaptureTelemetrySummary {
    private static let missingStage = "not_applicable"

    let captureID: String
    let context: TranscriptionRunContext
    let timeline: CaptureStageTimeline
    let processing: CaptureProcessingObservations

    init(
        captureID: String,
        context: TranscriptionRunContext,
        timeline: CaptureStageTimeline,
        processing: CaptureProcessingObservations = .empty
    ) {
        self.captureID = captureID
        self.context = context
        self.timeline = timeline
        self.processing = processing
    }

    private func elapsedMs(from start: UInt64, to end: UInt64) -> UInt64 {
        guard end >= start else { return 0 }
        return (end - start) / 1_000_000
    }

    private func optionalElapsedMs(start: UInt64?, end: UInt64?) -> String {
        guard let start, let end else {
            return Self.missingStage
        }
        return String(elapsedMs(from: start, to: end))
    }

    private func optionalTimestamp(_ value: UInt64?) -> String {
        guard let value else { return Self.missingStage }
        return String(value)
    }

    private var selectedResultReadyAt: UInt64 {
        timeline.selectedResultReadyAt ?? timeline.finalResultReadyAt
    }

    var metadata: [String: String] {
        var fields: [String: String] = [
            "capture_id": captureID,
            "provider": context.provider,
            "backend_kind": context.backendKind.rawValue,
            "support_tier": context.supportTier.rawValue,
            "pipeline_mode": context.pipelineMode.rawValue,
            "model": context.model,
            "backend_config_fingerprint": context.backendConfigFingerprint,
            "refinement_provider": context.refinementProvider ?? Self.missingStage,
            "refinement_model": context.refinementModel ?? Self.missingStage,
            "refinement_config_fingerprint": context.refinementConfigFingerprint ?? Self.missingStage,
            "language_mode": context.languageMode.rawValue,
            "audio_duration_ms": String(context.audioDurationMs),
            "warm_state": context.warmState.rawValue,
            "refinement_enabled": String(context.refinementEnabled),
            "raw_audio_duration_ms": String(processing.rawAudioDurationMs),
            "raw_audio_file_size_bytes": String(processing.rawAudioFileSizeBytes),
            "processed_audio_duration_ms": String(processing.processedAudioDurationMs),
            "processed_audio_file_size_bytes": String(processing.processedAudioFileSizeBytes),
            "speech_detected": String(processing.speechDetected),
            "trim_result": processing.trimResult.rawValue,
            "transcription_character_count": String(processing.transcriptionCharacterCount),
            "completion_reason": processing.completionReason,
            "stop_requested_at": String(timeline.stopRequestedAt),
            "audio_ready_at": String(timeline.audioReadyAt),
            "backend_load_started_at": optionalTimestamp(timeline.backendLoadStartedAt),
            "backend_load_finished_at": optionalTimestamp(timeline.backendLoadFinishedAt),
            "transcription_started_at": String(timeline.transcriptionStartedAt),
            "transcription_finished_at": String(timeline.transcriptionFinishedAt),
            "refinement_started_at": optionalTimestamp(timeline.refinementStartedAt),
            "refinement_finished_at": optionalTimestamp(timeline.refinementFinishedAt),
            "selected_result_ready_at": String(selectedResultReadyAt),
            "audit_fanout_finished_at": optionalTimestamp(timeline.auditFanoutFinishedAt),
            "audit_variant_success_count": String(timeline.auditVariantSuccessCount),
            "audit_variant_failure_count": String(timeline.auditVariantFailureCount),
            "final_result_ready_at": String(timeline.finalResultReadyAt),
            "paste_command_sent_at": String(timeline.pasteCommandSentAt),
            "paste_completed_at": String(timeline.pasteCompletedAt),
            "paste_succeeded": String(timeline.pasteSucceeded),
            "app_pre_backend_elapsed_ms": String(elapsedMs(from: timeline.stopRequestedAt, to: timeline.transcriptionStartedAt)),
            "backend_load_elapsed_ms": optionalElapsedMs(start: timeline.backendLoadStartedAt, end: timeline.backendLoadFinishedAt),
            "backend_transcription_elapsed_ms": String(elapsedMs(from: timeline.transcriptionStartedAt, to: timeline.transcriptionFinishedAt)),
            "backend_refinement_elapsed_ms": optionalElapsedMs(start: timeline.refinementStartedAt, end: timeline.refinementFinishedAt),
            "audit_fanout_elapsed_ms": optionalElapsedMs(start: timeline.refinementStartedAt, end: timeline.auditFanoutFinishedAt),
            "app_post_backend_elapsed_ms": String(elapsedMs(from: timeline.finalResultReadyAt, to: timeline.pasteCommandSentAt)),
            "stop_to_paste_complete_ms": String(elapsedMs(from: timeline.stopRequestedAt, to: timeline.pasteCompletedAt))
        ]

        if let languageCode = context.languageCode {
            fields["language_code"] = languageCode
        }

        return fields
    }
}

struct RefinementVariantPlan: Sendable {
    let presetID: UUID
    let name: String
    let basePrompt: String
    let effectivePrompt: String
}

struct ParallelRefinementVariantResult: Sendable {
    let presetID: UUID
    let name: String
    let text: String
    let basePrompt: String
    let effectivePrompt: String
    let timing: StageTiming
}

struct ParallelRefinementFailure: Sendable {
    let presetID: UUID
    let presetName: String
    let message: String
}

struct ParallelRefinementAuditResult: Sendable {
    let variantsByPresetID: [UUID: ParallelRefinementVariantResult]
    let selectedVariant: ParallelRefinementVariantResult
    let selectedRecoveredByRetry: Bool
    let selectedResultReadyAt: UInt64
    let auditFanoutFinishedAt: UInt64
    let successCount: Int
    let failureCount: Int
    let failures: [ParallelRefinementFailure]
    let refinementTiming: StageTiming
}

enum ParallelRefinementError: LocalizedError {
    case missingSelectedPreset(UUID, String)
    case selectedPresetFailed(presetID: UUID, presetName: String, underlyingMessage: String)

    var errorDescription: String? {
        switch self {
        case .missingSelectedPreset(_, let presetName):
            return "Selected preset '\(presetName)' was not available for refinement."
        case .selectedPresetFailed(_, let presetName, let underlyingMessage):
            return "Selected preset '\(presetName)' failed during refinement: \(underlyingMessage)"
        }
    }
}

struct ParallelRefinementAuditRunner {
    let selectedPresetID: UUID
    let selectedPresetName: String
    let presets: [RefinementVariantPlan]
    let now: @Sendable () -> UInt64

    init(
        selectedPresetID: UUID,
        selectedPresetName: String,
        presets: [RefinementVariantPlan],
        now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
    ) {
        self.selectedPresetID = selectedPresetID
        self.selectedPresetName = selectedPresetName
        self.presets = presets
        self.now = now
    }

    func run(
        execute: @escaping @Sendable (RefinementVariantPlan) async throws -> RefinementExecutionResult
    ) async throws -> ParallelRefinementAuditResult {
        let fanoutStartedAt = now()
        var successes: [UUID: ParallelRefinementVariantResult] = [:]
        var failures: [UUID: ParallelRefinementFailure] = [:]

        await withTaskGroup(of: ParallelRefinementTaskOutcome.self) { group in
            for preset in presets {
                group.addTask {
                    do {
                        let result = try await execute(preset)
                        return .success(
                            ParallelRefinementVariantResult(
                                presetID: preset.presetID,
                                name: preset.name,
                                text: result.text,
                                basePrompt: preset.basePrompt,
                                effectivePrompt: preset.effectivePrompt,
                                timing: result.timing
                            )
                        )
                    } catch {
                        return .failure(
                            ParallelRefinementFailure(
                                presetID: preset.presetID,
                                presetName: preset.name,
                                message: error.localizedDescription
                            )
                        )
                    }
                }
            }

            for await outcome in group {
                switch outcome {
                case .success(let variant):
                    successes[variant.presetID] = variant
                case .failure(let failure):
                    failures[failure.presetID] = failure
                }
            }
        }

        var auditFanoutFinishedAt = now()
        var selectedRecoveredByRetry = false

        if successes[selectedPresetID] == nil {
            guard let selectedPreset = presets.first(where: { $0.presetID == selectedPresetID }) else {
                throw ParallelRefinementError.missingSelectedPreset(selectedPresetID, selectedPresetName)
            }

            do {
                let retryResult = try await execute(selectedPreset)
                let recoveredVariant = ParallelRefinementVariantResult(
                    presetID: selectedPreset.presetID,
                    name: selectedPreset.name,
                    text: retryResult.text,
                    basePrompt: selectedPreset.basePrompt,
                    effectivePrompt: selectedPreset.effectivePrompt,
                    timing: retryResult.timing
                )
                successes[recoveredVariant.presetID] = recoveredVariant
                failures.removeValue(forKey: recoveredVariant.presetID)
                selectedRecoveredByRetry = true
                auditFanoutFinishedAt = max(auditFanoutFinishedAt, retryResult.timing.finishedAt)
            } catch {
                throw ParallelRefinementError.selectedPresetFailed(
                    presetID: selectedPresetID,
                    presetName: selectedPresetName,
                    underlyingMessage: error.localizedDescription
                )
            }
        }

        guard let selectedVariant = successes[selectedPresetID] else {
            throw ParallelRefinementError.missingSelectedPreset(selectedPresetID, selectedPresetName)
        }

        if let latestSuccess = successes.values.map({ $0.timing.finishedAt }).max() {
            auditFanoutFinishedAt = max(auditFanoutFinishedAt, latestSuccess)
        }

        return ParallelRefinementAuditResult(
            variantsByPresetID: successes,
            selectedVariant: selectedVariant,
            selectedRecoveredByRetry: selectedRecoveredByRetry,
            selectedResultReadyAt: selectedVariant.timing.finishedAt,
            auditFanoutFinishedAt: auditFanoutFinishedAt,
            successCount: successes.count,
            failureCount: failures.count,
            failures: failures.values.sorted { lhs, rhs in
                if lhs.presetName == rhs.presetName {
                    return lhs.presetID.uuidString < rhs.presetID.uuidString
                }
                return lhs.presetName < rhs.presetName
            },
            refinementTiming: StageTiming(startedAt: fanoutStartedAt, finishedAt: auditFanoutFinishedAt)
        )
    }
}

private enum ParallelRefinementTaskOutcome: Sendable {
    case success(ParallelRefinementVariantResult)
    case failure(ParallelRefinementFailure)
}
