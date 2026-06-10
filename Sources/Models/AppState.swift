import Foundation
import SwiftUI
import AppKit
import AVFoundation
import os.log

actor CaptureDiagnostics {
    struct PersistedCaptureState: Codable, Equatable {
        let schemaVersion: Int
        let sessionID: String
        let captureID: String
        let lastKnownPhase: String
        let lastEvent: String
        let updatedAt: String
        let metadata: [String: String]
    }

    static let shared = CaptureDiagnostics()

    private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "CaptureDiagnostics")
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL
    private let persistedCaptureStateURL: URL
    private let sessionID: String
    private let isEnabled: Bool

    init(
        fileURL: URL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("capture-diagnostics.jsonl"),
        persistedCaptureStateURL: URL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("unfinished-capture.json"),
        sessionID: String = UUID().uuidString,
        isEnabled: Bool = AppIdentity.isDevelopmentBuild || ProcessInfo.processInfo.environment["MURMELN_CAPTURE_DIAGNOSTICS"] == "1"
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
        self.fileURL = fileURL
        self.persistedCaptureStateURL = persistedCaptureStateURL
        self.sessionID = sessionID
        self.isEnabled = isEnabled
    }

    func startSession() {
        guard isEnabled else { return }

        let recoveredState = recoverPersistedCaptureStateIfPresent()
        if let recoveredState {
            record(
                "app.session.recovered_previous_state",
                captureID: recoveredState.captureID,
                metadata: recoveryMetadata(from: recoveredState),
                updatePersistedCaptureState: false
            )
        }

        record(
            "app.session.started",
            metadata: [
                "app_name": AppIdentity.displayName,
                "bundle_identifier": AppIdentity.bundleIdentifier,
                "development_build": String(AppIdentity.isDevelopmentBuild),
                "recovered_previous_state": String(recoveredState != nil)
            ],
            updatePersistedCaptureState: false
        )
    }

    func endSession(reason: String, recordingPhase: String, activeCaptureID: String?) {
        guard isEnabled else { return }

        var metadata: [String: String] = [
            "reason": reason,
            "recording_phase": recordingPhase,
            "has_unfinished_capture_state": String(FileManager.default.fileExists(atPath: persistedCaptureStateURL.path))
        ]

        if let activeCaptureID {
            metadata["active_capture_id"] = activeCaptureID
        }

        record(
            "app.session.ending",
            captureID: activeCaptureID,
            metadata: metadata,
            updatePersistedCaptureState: false
        )
    }

    func mark(_ event: String, captureID: String? = nil, metadata: [String: String] = [:]) {
        guard isEnabled else {
            return
        }

        record(event, captureID: captureID, metadata: metadata)
    }

    private func record(
        _ event: String,
        captureID: String? = nil,
        metadata: [String: String] = [:],
        updatePersistedCaptureState: Bool = true
    ) {
        guard isEnabled else { return }

        var payload: [String: Any] = [
            "event": event,
            "session_id": sessionID,
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

        if updatePersistedCaptureState {
            updatePersistedCaptureStateIfNeeded(for: event, captureID: captureID, metadata: metadata)
        }
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

    private func updatePersistedCaptureStateIfNeeded(
        for event: String,
        captureID: String?,
        metadata: [String: String]
    ) {
        guard let captureID else { return }

        if event == "app.capture.complete" {
            clearPersistedCaptureState(for: captureID)
            return
        }

        guard let phase = persistedCapturePhase(for: event) else {
            return
        }

        let state = PersistedCaptureState(
            schemaVersion: 1,
            sessionID: sessionID,
            captureID: captureID,
            lastKnownPhase: phase,
            lastEvent: event,
            updatedAt: formatter.string(from: Date()),
            metadata: metadata
        )

        writePersistedCaptureState(state)
    }

    private func persistedCapturePhase(for event: String) -> String? {
        switch event {
        case "app.processing.started":
            return "processing_started"
        case "app.backend_load.started":
            return "backend_load_started"
        case "app.backend_load.completed":
            return "backend_load_completed"
        case "app.backend_load.skipped":
            return "backend_load_skipped"
        case "app.backend_transcription.started":
            return "backend_transcription_started"
        case "app.backend_transcription.completed":
            return "backend_transcription_completed"
        case "app.backend_transcription.failed":
            return "backend_transcription_failed"
        case "paste.requested":
            return "paste_requested"
        case "paste.skipped_empty":
            return "paste_skipped_empty"
        case "paste.complete":
            return "paste_completed"
        case "app.processing.failed":
            return "processing_failed"
        default:
            return nil
        }
    }

    private func writePersistedCaptureState(_ state: PersistedCaptureState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: persistedCaptureStateURL, options: [.atomic])
        } catch {
            logger.error("capture diagnostics state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoverPersistedCaptureStateIfPresent() -> PersistedCaptureState? {
        guard FileManager.default.fileExists(atPath: persistedCaptureStateURL.path) else {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: persistedCaptureStateURL)
        }

        do {
            let data = try Data(contentsOf: persistedCaptureStateURL)
            return try JSONDecoder().decode(PersistedCaptureState.self, from: data)
        } catch {
            logger.error("capture diagnostics state recovery failed: \(error.localizedDescription, privacy: .public)")
            return PersistedCaptureState(
                schemaVersion: 1,
                sessionID: "unknown",
                captureID: "unknown",
                lastKnownPhase: "unreadable_state",
                lastEvent: "unreadable_state",
                updatedAt: formatter.string(from: Date()),
                metadata: ["recovery_error": error.localizedDescription]
            )
        }
    }

    private func clearPersistedCaptureState(for captureID: String) {
        guard FileManager.default.fileExists(atPath: persistedCaptureStateURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: persistedCaptureStateURL)
            let state = try JSONDecoder().decode(PersistedCaptureState.self, from: data)
            guard state.captureID == captureID else { return }
            try FileManager.default.removeItem(at: persistedCaptureStateURL)
        } catch {
            logger.error("capture diagnostics state clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoveryMetadata(from state: PersistedCaptureState) -> [String: String] {
        var metadata: [String: String] = [
            "previous_session_id": state.sessionID,
            "previous_capture_id": state.captureID,
            "last_known_phase": state.lastKnownPhase,
            "last_event": state.lastEvent,
            "stale_updated_at": state.updatedAt
        ]

        if let updatedAt = formatter.date(from: state.updatedAt) {
            let staleAgeMs = max(0, Int(Date().timeIntervalSince(updatedAt) * 1000))
            metadata["stale_age_ms"] = String(staleAgeMs)
        }

        for (key, value) in state.metadata {
            metadata["previous_\(key)"] = value
        }

        return metadata
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
    private var warmUpReady = false
    private var pendingBeginRecording = false
    private var pendingBeginRequestedAtNs: UInt64?
    
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

    var diagnosticsActiveCaptureID: String? {
        activeCaptureID
    }

    var diagnosticsRecordingPhaseName: String {
        phaseName(recordingPhase)
    }

    func prepareCaptureIDForHotkeyPressIfPossible() -> String? {
        if let activeCaptureID {
            return activeCaptureID
        }

        guard recordingPhase == .idle else {
            return nil
        }

        return ensureCaptureID()
    }

    private func logCaptureSummary(
        captureID: String,
        context: TranscriptionRunContext,
        timeline: CaptureStageTimeline,
        processing: CaptureProcessingObservations
    ) {
        let summary = CaptureTelemetrySummary(
            captureID: captureID,
            context: context,
            timeline: timeline,
            processing: processing
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

    private func resetWarmUpCoordinationState() {
        warmUpReady = false
        pendingBeginRecording = false
        pendingBeginRequestedAtNs = nil
    }

    private func capturePromptSnapshot() {
        let settings = AppSettings.shared
        capturedPresetID = settings.selectedPreset?.id ?? PromptPreset.builtInPresets[0].id
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt

        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (id: preset.id, name: preset.name, prompt: settings.promptForPreset(preset))
        }
    }

    private func startWarmRecording(captureID: String, warmUpWaitMs: Int? = nil) {
        recordingPhase = .recording
        lastError = nil
        announceForAccessibility("Recording started")

        if let warmUpWaitMs {
            logDiagnostics("app.recording.begin_after_warmup_wait", captureID: captureID, metadata: [
                "warmup_wait_ms": String(warmUpWaitMs)
            ])
        }

        recordingTask = Task {
            do {
                try await audioRecorder.beginCapture(captureID: captureID)
                #if DEBUG
                print("🎙️ Recording started (zero latency)")
                #endif
                logDiagnostics("app.recording.begin_complete", captureID: captureID)
            } catch {
                if let audioError = error as? AudioRecorder.AudioError {
                    switch audioError {
                    case .notWarmedUp where warmUpTask != nil:
                        recordingPhase = .warmingUp
                        pendingBeginRecording = true
                        pendingBeginRequestedAtNs = DispatchTime.now().uptimeNanoseconds
                        logDiagnostics("app.recording.begin_requeued_warmup", captureID: captureID)
                        return
                    default:
                        break
                    }
                }

                #if DEBUG
                print("❌ Begin capture failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
                resetWarmUpCoordinationState()
                logDiagnostics("app.recording.begin_failed", captureID: captureID, metadata: ["error": error.localizedDescription])
                clearCaptureID(captureID)
            }
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

        resetWarmUpCoordinationState()

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
                resetWarmUpCoordinationState()
                logDiagnostics("app.warmup.permission_denied", captureID: captureID)
                clearCaptureID(captureID)
                return
            }
            
            do {
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.prepareEngine(highQuality: highQuality, captureID: captureID)
                warmUpReady = true
                #if DEBUG
                print("🔥 Engine warm-up complete")
                #endif
                logDiagnostics("app.warmup.ready", captureID: captureID)

                if pendingBeginRecording && recordingPhase == .warmingUp {
                    let warmUpWaitMs: Int
                    if let pendingBeginRequestedAtNs {
                        warmUpWaitMs = Int((DispatchTime.now().uptimeNanoseconds - pendingBeginRequestedAtNs) / 1_000_000)
                    } else {
                        warmUpWaitMs = 0
                    }

                    pendingBeginRecording = false
                    pendingBeginRequestedAtNs = nil
                    startWarmRecording(captureID: captureID, warmUpWaitMs: warmUpWaitMs)
                }
                
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
                resetWarmUpCoordinationState()
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
        resetWarmUpCoordinationState()
        
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

        capturePromptSnapshot()

        if !warmUpReady {
            pendingBeginRecording = true
            if pendingBeginRequestedAtNs == nil {
                pendingBeginRequestedAtNs = DispatchTime.now().uptimeNanoseconds
            }
            logDiagnostics("app.recording.begin_waiting_warmup", captureID: captureID)
            return
        }

        startWarmRecording(captureID: captureID)
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

            var completionOutcome = "failed"
            var completionReason = "unknown"
            var rawAudioDurationMs: UInt64 = 0
            var rawFileSize = 0
            var processedAudioDurationMs: UInt64 = 0
            var processedAudioFileSize = 0
            var trimResult: CaptureTrimResult = .notApplicable
            var speechDetected = false

            let stopRecordingElapsedMs = (DispatchTime.now().uptimeNanoseconds - stopRequestedNs) / 1_000_000
            logDiagnostics("app.stop.recording_stopped", captureID: captureID, metadata: [
                "elapsed_ms": String(stopRecordingElapsedMs)
            ])
            
            guard let url = audioURL else {
                #if DEBUG
                print("❌ No audio file URL returned")
                #endif
                logDiagnostics("app.stop.no_audio_url", captureID: captureID, metadata: [
                    "reason": "no_audio_url"
                ])
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.capture.complete", captureID: captureID, metadata: [
                    "outcome": "failed",
                    "reason": "no_audio_url"
                ])
                clearCaptureID(captureID)
                return
            }
            
            rawFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            rawAudioDurationMs = audioDurationMs(for: url)
            #if DEBUG
            print("📁 Audio file size: \(rawFileSize) bytes")
            #endif
            logDiagnostics("app.stop.audio_file", captureID: captureID, metadata: [
                "file": url.lastPathComponent,
                "file_size_bytes": String(rawFileSize),
                "audio_duration_ms": String(rawAudioDurationMs)
            ])
            if rawFileSize == 0 {
                lastError = "No audio recorded"
                recordingPhase = .idle
                overlay.hide()
                logDiagnostics("app.stop.empty_audio", captureID: captureID, metadata: [
                    "reason": "empty_audio_file",
                    "audio_duration_ms": String(rawAudioDurationMs)
                ])
                logDiagnostics("app.capture.complete", captureID: captureID, metadata: [
                    "outcome": "failed",
                    "reason": "empty_audio_file"
                ])
                clearCaptureID(captureID)
                return
            }
            
            let hasSpeech = await AudioRecorder.hasAudibleSpeech(audioURL: url)
            speechDetected = hasSpeech
            logDiagnostics("app.stop.speech_check", captureID: captureID, metadata: [
                "has_speech": String(hasSpeech),
                "audio_duration_ms": String(rawAudioDurationMs),
                "file_size_bytes": String(rawFileSize)
            ])
            if !hasSpeech {
                #if DEBUG
                print("🔇 No speech detected, skipping transcription")
                #endif
                lastError = nil
                recordingPhase = .idle
                overlay.hide()
                try? FileManager.default.removeItem(at: url)
                logDiagnostics("app.stop.no_speech", captureID: captureID, metadata: [
                    "reason": "no_audible_speech",
                    "audio_duration_ms": String(rawAudioDurationMs)
                ])
                logDiagnostics("app.capture.complete", captureID: captureID, metadata: [
                    "outcome": "skipped",
                    "reason": "no_audible_speech"
                ])
                clearCaptureID(captureID)
                return
            }
            
            let audioToProcess: URL
            let settings = AppSettings.shared
            if settings.disableSilenceTrimming {
                audioToProcess = url
                trimResult = .disabled
                processedAudioDurationMs = rawAudioDurationMs
                processedAudioFileSize = rawFileSize
                #if DEBUG
                print("🔪 Trim: disabled by user setting")
                #endif
                logDiagnostics("app.trim.disabled", captureID: captureID, metadata: [
                    "reason": "disabled_by_setting",
                    "raw_audio_duration_ms": String(rawAudioDurationMs),
                    "processed_audio_duration_ms": String(processedAudioDurationMs),
                    "raw_file_size_bytes": String(rawFileSize),
                    "processed_file_size_bytes": String(processedAudioFileSize)
                ])
            } else if let trimmedURL = await AudioRecorder.trimSilence(audioURL: url) {
                audioToProcess = trimmedURL
                trimResult = trimmedURL == url ? .skipped : .completed
                let trimmedSize = (try? FileManager.default.attributesOfItem(atPath: trimmedURL.path)[.size] as? Int) ?? 0
                processedAudioDurationMs = audioDurationMs(for: trimmedURL)
                processedAudioFileSize = trimmedSize
                #if DEBUG
                print("🔪 Trim: \(rawFileSize) bytes → \(trimmedSize) bytes")
                #endif
                logDiagnostics(trimResult == .completed ? "app.trim.completed" : "app.trim.skipped", captureID: captureID, metadata: [
                    "reason": trimResult == .completed ? "trimmed" : "no_material_trim",
                    "original_bytes": String(rawFileSize),
                    "trimmed_bytes": String(trimmedSize),
                    "raw_audio_duration_ms": String(rawAudioDurationMs),
                    "trimmed_audio_duration_ms": String(processedAudioDurationMs),
                    "trimmed_file": trimmedURL.lastPathComponent
                ])
            } else {
                audioToProcess = url
                trimResult = .skipped
                processedAudioDurationMs = rawAudioDurationMs
                processedAudioFileSize = rawFileSize
                #if DEBUG
                print("🔪 Trim: skipped (returned nil)")
                #endif
                logDiagnostics("app.trim.skipped", captureID: captureID, metadata: [
                    "reason": "trim_silence_returned_nil",
                    "raw_audio_duration_ms": String(rawAudioDurationMs),
                    "trimmed_audio_duration_ms": String(processedAudioDurationMs),
                    "raw_file_size_bytes": String(rawFileSize),
                    "trimmed_file_size_bytes": String(processedAudioFileSize)
                ])
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
                "audio_duration_ms": String(audioDurationMs),
                "raw_audio_duration_ms": String(rawAudioDurationMs),
                "processed_audio_duration_ms": String(processedAudioDurationMs == 0 ? audioDurationMs : processedAudioDurationMs),
                "trim_result": trimResult.rawValue,
                "speech_detected": String(speechDetected)
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
                if pasteTiming.succeeded {
                    announceForAccessibility("Text pasted")
                }

                let observedProcessedAudioDurationMs = processedAudioDurationMs == 0 ? audioDurationMs : processedAudioDurationMs
                let completion = CaptureCompletionOutcome.classify(
                    transcriptionText: originalText,
                    pasteSucceeded: pasteTiming.succeeded,
                    processedAudioDurationMs: observedProcessedAudioDurationMs,
                    speechDetected: speechDetected
                )
                completionOutcome = completion.completionOutcome
                completionReason = completion.completionReason
                lastError = completion.userFacingMessage
                if let message = completion.userFacingMessage {
                    announceForAccessibility(message)
                }

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
                    ),
                    processing: CaptureProcessingObservations(
                        rawAudioDurationMs: rawAudioDurationMs,
                        rawAudioFileSizeBytes: rawFileSize,
                        processedAudioDurationMs: observedProcessedAudioDurationMs,
                        processedAudioFileSizeBytes: processedAudioFileSize == 0 ? rawFileSize : processedAudioFileSize,
                        speechDetected: speechDetected,
                        trimResult: trimResult,
                        transcriptionCharacterCount: originalText.count,
                        completionReason: completionReason
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
                
                if completion.userFacingMessage == nil {
                    lastError = nil
                }
            } catch {
                #if DEBUG
                print("❌ Multi-refinement failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                completionOutcome = "failed"
                completionReason = "processing_error"
                logDiagnostics("app.processing.failed", captureID: captureID, metadata: [
                    "reason": "processing_error",
                    "error": error.localizedDescription
                ])
            }
            
            recordingPhase = .idle
            resetWarmUpCoordinationState()
            overlay.hide()
            await cleanupTempFile(at: url)
            if audioToProcess != url {
                await cleanupTempFile(at: audioToProcess)
            }
            logDiagnostics("app.capture.complete", captureID: captureID, metadata: [
                "outcome": completionOutcome,
                "reason": completionReason
            ])
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
