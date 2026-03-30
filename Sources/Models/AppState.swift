import Foundation
import SwiftUI
import AppKit
import AVFoundation
import os.log

actor CaptureDiagnostics {
    static let shared = CaptureDiagnostics()

    private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "CaptureDiagnostics")
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL

    private init() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
        self.fileURL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("capture-diagnostics.jsonl")
    }

    func mark(_ event: String, captureID: String? = nil, metadata: [String: String] = [:]) {
        guard AppIdentity.isDevelopmentBuild || ProcessInfo.processInfo.environment["MURMELN_CAPTURE_DIAGNOSTICS"] == "1" else {
            return
        }

        var payload: [String: Any] = [
            "event": event,
            "timestamp": formatter.string(from: Date()),
            "uptime_ns": DispatchTime.now().uptimeNanoseconds
        ]

        if let captureID {
            payload["capture_id"] = captureID
        }

        for (key, value) in metadata {
            payload[key] = value
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            logger.error("capture diagnostics serialization failed for event \(event, privacy: .public)")
            return
        }

        logger.info("\(line, privacy: .public)")
        appendLine(line)
    }

    private func appendLine(_ line: String) {
        let content = line + "\n"
        guard let data = content.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.error("capture diagnostics append failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    /// Internal state machine to prevent race conditions during async operations
    enum RecordingPhase {
        case idle
        case warmingUp             // Engine running, waiting for hold threshold
        case requestingPermission  // Set synchronously before permission check
        case recording             // Actively recording audio
        case processing            // Transcribing and refining
    }
    
    @Published private(set) var recordingPhase: RecordingPhase = .idle
    @Published private(set) var audioLevel: Float = 0
    @Published var lastError: String?
    
    /// Backward-compatible computed property for UI bindings
    var isRecording: Bool {
        recordingPhase == .recording || recordingPhase == .requestingPermission
    }
    
    /// Backward-compatible computed property for UI bindings
    var isProcessing: Bool {
        recordingPhase == .processing
    }
    
    private let audioRecorder = AudioRecorder()
    private let pipelineService = TranscriptionPipelineService.shared
    private let overlay = OverlayWindowController.shared
    private var recordingTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    
    private var capturedPresetID: UUID = PromptPreset.builtInPresets[0].id
    private var capturedPresetName: String = ""
    private var capturedSystemPrompt: String = ""
    private var capturedPresetsWithPrompts: [(id: UUID, name: String, prompt: String)] = []
    private var activeCaptureID: String?
    
    private init() {}

    private func ensureCaptureID() -> String {
        if let activeCaptureID {
            return activeCaptureID
        }

        let newCaptureID = UUID().uuidString
        activeCaptureID = newCaptureID
        return newCaptureID
    }

    private func clearCaptureID(_ captureID: String) {
        if activeCaptureID == captureID {
            activeCaptureID = nil
        }
    }

    private func logDiagnostics(_ event: String, captureID: String? = nil, metadata: [String: String] = [:]) {
        let resolvedCaptureID = captureID ?? activeCaptureID
        Task {
            await CaptureDiagnostics.shared.mark(event, captureID: resolvedCaptureID, metadata: metadata)
        }
    }

    private func phaseName(_ phase: RecordingPhase) -> String {
        switch phase {
        case .idle: return "idle"
        case .warmingUp: return "warming_up"
        case .requestingPermission: return "requesting_permission"
        case .recording: return "recording"
        case .processing: return "processing"
        }
    }

    private func logCaptureSummary(captureID: String, context: TranscriptionRunContext, timeline: CaptureStageTimeline) {
        let summary = CaptureTelemetrySummary(
            captureID: captureID,
            context: context,
            timeline: timeline
        )
        logDiagnostics("capture.summary", captureID: captureID, metadata: summary.metadata)
    }

    private func audioDurationMs(for audioURL: URL) -> UInt64 {
        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            let sampleRate = audioFile.fileFormat.sampleRate
            guard sampleRate > 0 else { return 0 }
            let durationSeconds = Double(audioFile.length) / sampleRate
            return UInt64((durationSeconds * 1000).rounded())
        } catch {
            return 0
        }
    }
    
    private func announceForAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
        )
    }
    
    private func promptWithDictionary(_ basePrompt: String) -> String {
        let settings = AppSettings.shared
        guard settings.personalDictionaryEnabled, !settings.personalDictionary.isEmpty else {
            return basePrompt
        }
        let words = settings.personalDictionary.joined(separator: ", ")
        let dictionaryInstruction = " If the speaker says words similar to these names/terms, use this exact spelling: \(words)."
        return basePrompt + dictionaryInstruction
    }
    
    // MARK: - Warm-up Flow (called on Fn press, before 400ms threshold)
    
    /// Starts engine warm-up immediately on Fn press.
    /// This eliminates audio startup latency by the time recording actually begins.
    func warmUpEngine() {
        guard recordingPhase == .idle else {
            logDiagnostics("app.warmup.ignored", metadata: ["phase": phaseName(recordingPhase)])
            return
        }

        let captureID = ensureCaptureID()
        logDiagnostics("app.warmup.start", captureID: captureID, metadata: [
            "high_quality": String(AppSettings.shared.highQualityAudio)
        ])
        
        recordingPhase = .warmingUp
        
        warmUpTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone access denied. Open System Settings → Privacy & Security → Microphone to grant access."
                recordingPhase = .idle
                logDiagnostics("app.warmup.permission_denied", captureID: captureID)
                clearCaptureID(captureID)
                return
            }
            
            do {
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.prepareEngine(highQuality: highQuality, captureID: captureID)
                #if DEBUG
                print("🔥 Engine warm-up complete")
                #endif
                logDiagnostics("app.warmup.ready", captureID: captureID)
                
                // Show overlay during warm-up for visual feedback
                overlay.show()
                
                // Stream levels during warm-up (visual feedback only, not recording)
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
                #if DEBUG
                print("❌ Warm-up failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.warmup.failed", captureID: captureID, metadata: ["error": error.localizedDescription])
                clearCaptureID(captureID)
            }
        }
    }
    
    /// Cancels warm-up if user releases Fn before 400ms threshold.
    func cancelWarmUp() {
        guard recordingPhase == .warmingUp else { return }
        let captureID = activeCaptureID
        logDiagnostics("app.warmup.cancel", captureID: captureID)
        
        warmUpTask?.cancel()
        warmUpTask = nil
        
        Task {
            await audioRecorder.cancelWarmUp()
            audioLevel = 0
            recordingPhase = .idle
            overlay.hide()
            if let captureID {
                clearCaptureID(captureID)
            }
        }
    }
    
    /// Begins actual recording after 400ms threshold is met.
    /// Engine is already warm, so this is near-instant.
    func beginRecording() {
        guard recordingPhase == .warmingUp else {
            logDiagnostics("app.recording.begin_fallback", metadata: ["phase": phaseName(recordingPhase)])
            // Fallback: if not warmed up, use legacy flow
            startRecording()
            return
        }

        let captureID = ensureCaptureID()
        logDiagnostics("app.recording.begin", captureID: captureID)
        
        let settings = AppSettings.shared
        capturedPresetID = settings.selectedPreset?.id ?? PromptPreset.builtInPresets[0].id
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt
        
        // Capture all presets and their CURRENT prompts at the moment recording starts
        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (id: preset.id, name: preset.name, prompt: settings.promptForPreset(preset))
        }
        
        recordingPhase = .recording
        lastError = nil
        announceForAccessibility("Recording started")
        
        recordingTask = Task {
            do {
                try await audioRecorder.beginCapture(captureID: captureID)
                #if DEBUG
                print("🎙️ Recording started (zero latency)")
                #endif
                logDiagnostics("app.recording.begin_complete", captureID: captureID)
            } catch {
                #if DEBUG
                print("❌ Begin capture failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.recording.begin_failed", captureID: captureID, metadata: ["error": error.localizedDescription])
                clearCaptureID(captureID)
            }
        }
    }
    
    // MARK: - Legacy Flow (for backward compatibility and lock mode)
    
    func startRecording() {
        guard recordingPhase == .idle else {
            logDiagnostics("app.recording.legacy_ignored", metadata: ["phase": phaseName(recordingPhase)])
            return
        }

        let captureID = ensureCaptureID()
        logDiagnostics("app.recording.legacy_start", captureID: captureID)
        
        let settings = AppSettings.shared
        capturedPresetID = settings.selectedPreset?.id ?? PromptPreset.builtInPresets[0].id
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt
        
        // Capture all presets and their CURRENT prompts at the moment recording starts
        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (id: preset.id, name: preset.name, prompt: settings.promptForPreset(preset))
        }
        
        // Set state SYNCHRONOUSLY before any async work to prevent race conditions
        // This ensures stopAndProcess() knows we're in the recording flow
        recordingPhase = .requestingPermission
        
        recordingTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone access denied. Open System Settings → Privacy & Security → Microphone to grant access."
                recordingPhase = .idle
                logDiagnostics("app.recording.legacy_permission_denied", captureID: captureID)
                clearCaptureID(captureID)
                return
            }
            
            do {
                #if DEBUG
                print("📝 Starting recording with preset: \(capturedPresetName)")
                #endif
                recordingPhase = .recording
                lastError = nil
                overlay.show()
                announceForAccessibility("Recording started")
                
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.startRecording(highQuality: highQuality, captureID: captureID)
                #if DEBUG
                print("✅ Recording started")
                #endif
                logDiagnostics("app.recording.legacy_started", captureID: captureID)
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
                #if DEBUG
                print("❌ Recording failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.recording.legacy_failed", captureID: captureID, metadata: ["error": error.localizedDescription])
                clearCaptureID(captureID)
            }
        }
    }
    
    func stopAndProcess() {
        // Handle .recording, .requestingPermission, and .warmingUp states
        // This fixes race conditions during various phases
        guard recordingPhase == .recording || recordingPhase == .requestingPermission || recordingPhase == .warmingUp else {
            logDiagnostics("app.stop.ignored", metadata: ["phase": phaseName(recordingPhase)])
            return
        }

        let captureID = ensureCaptureID()
        let stopRequestedNs = DispatchTime.now().uptimeNanoseconds
        logDiagnostics("app.stop.requested", captureID: captureID, metadata: ["phase": phaseName(recordingPhase)])
        
        // If still warming up, just cancel (no audio to process)
        if recordingPhase == .warmingUp {
            logDiagnostics("app.stop.cancelled_warmup", captureID: captureID)
            cancelWarmUp()
            return
        }
        
        recordingTask?.cancel()
        recordingTask = nil
        warmUpTask?.cancel()
        warmUpTask = nil
        
        Task {
            #if DEBUG
            print("⏹️ Stopping recording...")
            #endif
            let audioURL = await audioRecorder.stopRecording(captureID: captureID)
            // Stay in .recording state during VAD/trim to prevent race conditions
            // Only transition to .idle on early returns, or to .processing on success
            audioLevel = 0

            let stopRecordingElapsedMs = (DispatchTime.now().uptimeNanoseconds - stopRequestedNs) / 1_000_000
            logDiagnostics("app.stop.recording_stopped", captureID: captureID, metadata: [
                "elapsed_ms": String(stopRecordingElapsedMs)
            ])
            
            guard let url = audioURL else {
                #if DEBUG
                print("❌ No audio file URL returned")
                #endif
                logDiagnostics("app.stop.no_audio_url", captureID: captureID)
                recordingPhase = .idle
                overlay.hide()
                clearCaptureID(captureID)
                return
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            #if DEBUG
            print("📁 Audio file size: \(fileSize) bytes")
            #endif
            logDiagnostics("app.stop.audio_file", captureID: captureID, metadata: [
                "file": url.lastPathComponent,
                "file_size_bytes": String(fileSize)
            ])
            if fileSize == 0 {
                lastError = "No audio recorded"
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.stop.empty_audio", captureID: captureID)
                clearCaptureID(captureID)
                return
            }
            
            let hasSpeech = await AudioRecorder.hasAudibleSpeech(audioURL: url)
            logDiagnostics("app.stop.speech_check", captureID: captureID, metadata: [
                "has_speech": String(hasSpeech)
            ])
            if !hasSpeech {
                #if DEBUG
                print("🔇 No speech detected, skipping transcription")
                #endif
                lastError = nil
                recordingPhase = .idle
                overlay.hide()
                try? FileManager.default.removeItem(at: url)
                logDiagnostics("app.stop.no_speech", captureID: captureID)
                clearCaptureID(captureID)
                return
            }
            
            let audioToProcess: URL
            let settings = AppSettings.shared
            if settings.disableSilenceTrimming {
                audioToProcess = url
                #if DEBUG
                print("🔪 Trim: disabled by user setting")
                #endif
                logDiagnostics("app.trim.disabled", captureID: captureID)
            } else if let trimmedURL = await AudioRecorder.trimSilence(audioURL: url) {
                audioToProcess = trimmedURL
                let originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let trimmedSize = (try? FileManager.default.attributesOfItem(atPath: trimmedURL.path)[.size] as? Int) ?? 0
                #if DEBUG
                print("🔪 Trim: \(originalSize) bytes → \(trimmedSize) bytes")
                #endif
                logDiagnostics("app.trim.completed", captureID: captureID, metadata: [
                    "original_bytes": String(originalSize),
                    "trimmed_bytes": String(trimmedSize),
                    "trimmed_file": trimmedURL.lastPathComponent
                ])
            } else {
                audioToProcess = url
                #if DEBUG
                print("🔪 Trim: skipped (returned nil)")
                #endif
                logDiagnostics("app.trim.skipped", captureID: captureID)
            }
            
            let pipelineSettings = settings.pipelineSettingsSnapshot()
            let selectedPipelineMode = pipelineService.pipelineMode(for: pipelineSettings)
            let audioDurationMs = audioDurationMs(for: audioToProcess)
            let audioReadyNs = DispatchTime.now().uptimeNanoseconds

            recordingPhase = .processing
            overlay.setProcessing()
            announceForAccessibility("Processing speech")
            logDiagnostics("app.processing.started", captureID: captureID, metadata: [
                "pipeline_mode": selectedPipelineMode.rawValue,
                "audio_duration_ms": String(audioDurationMs)
            ])
            
            do {
                #if DEBUG
                print("🚀 Starting transcription phase...")
                #endif
                let baselinePrompt = selectedPipelineMode == .oneCallTranscriptionAndRefinement
                    ? promptWithDictionary(capturedSystemPrompt)
                    : ""

                let transcriptionResult = try await pipelineService.executeTranscription(
                    request: TranscriptionRequest(
                        captureID: captureID,
                        audioURL: audioToProcess,
                        audioDurationMs: audioDurationMs,
                        baselinePrompt: baselinePrompt,
                        settings: pipelineSettings
                    )
                )
                let originalText = transcriptionResult.text
                
                #if DEBUG
                print("✅ Baseline obtained: '\(originalText)'")
                #endif
                let transcriptionElapsedMs = transcriptionResult.transcriptionTiming.elapsedMs
                logDiagnostics("app.transcription.completed", captureID: captureID, metadata: [
                    "elapsed_ms": String(transcriptionElapsedMs),
                    "characters": String(originalText.count),
                    "provider": transcriptionResult.runContext.provider,
                    "backend_kind": transcriptionResult.runContext.backendKind.rawValue,
                    "support_tier": transcriptionResult.runContext.supportTier.rawValue,
                    "pipeline_mode": transcriptionResult.runContext.pipelineMode.rawValue,
                    "model": transcriptionResult.runContext.model,
                    "warm_state": transcriptionResult.runContext.warmState.rawValue
                ])

                var variants: [String: String] = [:]
                var variantPrompts: [String: String] = [:]
                var effectiveVariantPrompts: [String: String] = [:]
                var aggregateRefinementTiming: StageTiming?
                var selectedResultReadyAtNs: UInt64?
                var auditFanoutFinishedAtNs: UInt64?
                var auditVariantSuccessCount = 0
                var auditVariantFailureCount = 0
                var finalResult = originalText
                var finalPresetName = capturedPresetName
                var finalSystemPrompt = capturedSystemPrompt
                var effectiveSystemPrompt = capturedSystemPrompt

                switch transcriptionResult.runContext.pipelineMode {
                case .transcribeOnly:
                    finalPresetName = "Raw (No Refinement)"
                    finalSystemPrompt = ""
                    effectiveSystemPrompt = ""

                case .oneCallTranscriptionAndRefinement:
                    // Final text already returned by the transcription backend.
                    effectiveSystemPrompt = baselinePrompt
                    break

                case .twoCallRefinement:
                    let presets = capturedPresetsWithPrompts

                    if pipelineSettings.parallelRefinementEnabled {
                        let refinementPlans = presets.map {
                            RefinementVariantPlan(
                                presetID: $0.id,
                                name: $0.name,
                                basePrompt: $0.prompt,
                                effectivePrompt: promptWithDictionary($0.prompt)
                            )
                        }
                        let pipelineService = self.pipelineService
                        do {
                            let auditResult = try await ParallelRefinementAuditRunner(
                                selectedPresetID: capturedPresetID,
                                selectedPresetName: capturedPresetName,
                                presets: refinementPlans
                            ).run { plan in
                                try await pipelineService.executeRefinement(
                                    request: RefinementRequest(
                                        captureID: captureID,
                                        text: originalText,
                                        systemPrompt: plan.effectivePrompt,
                                        settings: pipelineSettings
                                    )
                                )
                            }

                            let variantResults = auditResult.variantsByPresetID.values.sorted { lhs, rhs in
                                if lhs.name == rhs.name {
                                    return lhs.presetID.uuidString < rhs.presetID.uuidString
                                }
                                return lhs.name < rhs.name
                            }
                            variants = Dictionary(uniqueKeysWithValues: variantResults.map { ($0.name, $0.text) })
                            variantPrompts = Dictionary(uniqueKeysWithValues: variantResults.map { ($0.name, $0.basePrompt) })
                            effectiveVariantPrompts = Dictionary(uniqueKeysWithValues: variantResults.map { ($0.name, $0.effectivePrompt) })
                            aggregateRefinementTiming = auditResult.refinementTiming
                            selectedResultReadyAtNs = auditResult.selectedResultReadyAt
                            auditFanoutFinishedAtNs = auditResult.auditFanoutFinishedAt
                            auditVariantSuccessCount = auditResult.successCount
                            auditVariantFailureCount = auditResult.failureCount
                            finalResult = auditResult.selectedVariant.text
                            finalSystemPrompt = auditResult.selectedVariant.basePrompt
                            effectiveSystemPrompt = auditResult.selectedVariant.effectivePrompt

                            if auditResult.selectedRecoveredByRetry {
                                logDiagnostics("app.refinement.selected_retry_succeeded", captureID: captureID, metadata: [
                                    "preset": capturedPresetName,
                                    "preset_id": capturedPresetID.uuidString
                                ])
                            }

                            for failure in auditResult.failures {
                                #if DEBUG
                                print("⚠️ Variant \(failure.presetName) failed: \(failure.message)")
                                #endif
                                logDiagnostics("app.refinement.variant_failed", captureID: captureID, metadata: [
                                    "preset": failure.presetName,
                                    "preset_id": failure.presetID.uuidString,
                                    "error": failure.message
                                ])
                            }
                        } catch let error as ParallelRefinementError {
                            logDiagnostics("app.refinement.selected_failed", captureID: captureID, metadata: [
                                "preset": capturedPresetName,
                                "preset_id": capturedPresetID.uuidString,
                                "error": error.localizedDescription
                            ])
                            throw error
                        }
                    } else {
                        let enhancedPrompt = promptWithDictionary(capturedSystemPrompt)
                        let refinementResult = try await pipelineService.executeRefinement(
                            request: RefinementRequest(
                                captureID: captureID,
                                text: originalText,
                                systemPrompt: enhancedPrompt,
                                settings: pipelineSettings
                            )
                        )
                        aggregateRefinementTiming = refinementResult.timing
                        selectedResultReadyAtNs = refinementResult.timing.finishedAt
                        auditFanoutFinishedAtNs = refinementResult.timing.finishedAt
                        auditVariantSuccessCount = 1
                        auditVariantFailureCount = 0
                        finalResult = refinementResult.text
                        finalSystemPrompt = capturedSystemPrompt
                        effectiveSystemPrompt = enhancedPrompt
                    }

                    let refinementElapsedMs = aggregateRefinementTiming?.elapsedMs ?? 0
                    logDiagnostics("app.refinement.completed", captureID: captureID, metadata: [
                        "elapsed_ms": String(refinementElapsedMs),
                        "parallel_enabled": String(pipelineSettings.parallelRefinementEnabled),
                        "variant_count": String(variants.count),
                        "variant_success_count": String(auditVariantSuccessCount),
                        "variant_failure_count": String(auditVariantFailureCount)
                    ])
                }

                #if DEBUG
                print("📋 Pasting result for \(finalPresetName)...")
                #endif

                let finalResultReadyAtNs: UInt64
                switch transcriptionResult.runContext.pipelineMode {
                case .transcribeOnly, .oneCallTranscriptionAndRefinement:
                    finalResultReadyAtNs = transcriptionResult.transcriptionTiming.finishedAt
                case .twoCallRefinement:
                    finalResultReadyAtNs = auditFanoutFinishedAtNs
                        ?? aggregateRefinementTiming?.finishedAt
                        ?? selectedResultReadyAtNs
                        ?? transcriptionResult.transcriptionTiming.finishedAt
                }

                let pasteStartNs = DispatchTime.now().uptimeNanoseconds
                let pasteTiming = await PasteService.shared.pasteAndRestore(text: finalResult, captureID: captureID)
                announceForAccessibility("Text pasted")

                let pasteCommandSentAtNs = pasteStartNs + (pasteTiming.commandSentElapsedMs * 1_000_000)
                let pasteCompletedAtNs = pasteStartNs + (pasteTiming.totalElapsedMs * 1_000_000)

                let stopToPasteCommandMs = pasteCommandSentAtNs >= stopRequestedNs
                    ? (pasteCommandSentAtNs - stopRequestedNs) / 1_000_000
                    : 0
                let stopToPasteCompleteMs = pasteCompletedAtNs >= stopRequestedNs
                    ? (pasteCompletedAtNs - stopRequestedNs) / 1_000_000
                    : 0

                let pathLabel: String
                switch transcriptionResult.runContext.pipelineMode {
                case .transcribeOnly:
                    pathLabel = "raw"
                case .oneCallTranscriptionAndRefinement:
                    pathLabel = "one_call"
                case .twoCallRefinement:
                    pathLabel = "refined"
                }

                logDiagnostics("app.stop_to_paste", captureID: captureID, metadata: [
                    "command_elapsed_ms": String(stopToPasteCommandMs),
                    "complete_elapsed_ms": String(stopToPasteCompleteMs),
                    "path": pathLabel,
                    "paste_succeeded": String(pasteTiming.succeeded)
                ])

                logDiagnostics("app.latency.summary", captureID: captureID, metadata: [
                    "transcription_elapsed_ms": String(transcriptionElapsedMs),
                    "stop_to_paste_command_ms": String(stopToPasteCommandMs),
                    "stop_to_paste_complete_ms": String(stopToPasteCompleteMs),
                    "path": pathLabel,
                    "paste_succeeded": String(pasteTiming.succeeded)
                ])

                logCaptureSummary(
                    captureID: captureID,
                    context: transcriptionResult.runContext,
                    timeline: CaptureStageTimeline(
                        stopRequestedAt: stopRequestedNs,
                        audioReadyAt: audioReadyNs,
                        backendLoadStartedAt: transcriptionResult.backendLoadTiming?.startedAt,
                        backendLoadFinishedAt: transcriptionResult.backendLoadTiming?.finishedAt,
                        transcriptionStartedAt: transcriptionResult.transcriptionTiming.startedAt,
                        transcriptionFinishedAt: transcriptionResult.transcriptionTiming.finishedAt,
                        refinementStartedAt: aggregateRefinementTiming?.startedAt,
                        refinementFinishedAt: aggregateRefinementTiming?.finishedAt,
                        selectedResultReadyAt: selectedResultReadyAtNs,
                        auditFanoutFinishedAt: auditFanoutFinishedAtNs,
                        auditVariantSuccessCount: auditVariantSuccessCount,
                        auditVariantFailureCount: auditVariantFailureCount,
                        finalResultReadyAt: finalResultReadyAtNs,
                        pasteCommandSentAt: pasteCommandSentAtNs,
                        pasteCompletedAt: pasteCompletedAtNs,
                        pasteSucceeded: pasteTiming.succeeded
                    )
                )

                HistoryStore.shared.add(
                    original: originalText,
                    refined: finalResult,
                    presetName: finalPresetName,
                    systemPrompt: finalSystemPrompt,
                    effectiveSystemPrompt: effectiveSystemPrompt,
                    variants: variants.isEmpty ? nil : variants,
                    variantPrompts: variantPrompts.isEmpty ? nil : variantPrompts,
                    effectiveVariantPrompts: effectiveVariantPrompts.isEmpty ? nil : effectiveVariantPrompts
                )
                
                lastError = nil
            } catch {
                #if DEBUG
                print("❌ Multi-refinement failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                logDiagnostics("app.processing.failed", captureID: captureID, metadata: ["error": error.localizedDescription])
            }
            
            recordingPhase = .idle
            overlay.hide()
            await cleanupTempFile(at: url)
            if audioToProcess != url {
                await cleanupTempFile(at: audioToProcess)
            }
            logDiagnostics("app.capture.complete", captureID: captureID)
            clearCaptureID(captureID)
        }
    }
    
    private func cleanupTempFile(at url: URL, maxRetries: Int = 3) async {
        for attempt in 1...maxRetries {
            do {
                try FileManager.default.removeItem(at: url)
                return
            } catch {
                if attempt == maxRetries {
                    #if DEBUG
                    print("⚠️ Failed to cleanup temp file after \(maxRetries) attempts: \(url.lastPathComponent) - \(error.localizedDescription)")
                    #endif
                } else {
                    try? await Task.sleep(for: .milliseconds(100 * attempt))
                }
            }
        }
    }
    
}
