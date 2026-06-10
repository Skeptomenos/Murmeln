import Foundation

// MARK: - AppState dependency seams
//
// AppState orchestrates singletons (audio, pipeline, overlay, paste, history,
// permissions). These protocols are the constructor-injection seams that make
// the orchestration layer testable; production wiring is unchanged via the
// `.shared` default arguments in AppState.init.

/// Audio capture surface used by AppState (implemented by the AudioRecorder actor).
protocol AudioCapturing: Sendable {
    func prepareEngine(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float>
    func beginCapture(captureID: String?) async throws
    func cancelWarmUp() async
    func startRecording(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float>
    func stopRecording(captureID: String?) async -> URL?
}

extension AudioRecorder: AudioCapturing {}

/// Transcription/refinement pipeline surface used by AppState.
protocol TranscriptionPipelineProviding: Sendable {
    func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode
    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult
    func executeRefinement(request: RefinementRequest) async throws -> RefinementExecutionResult
}

extension TranscriptionPipelineService: TranscriptionPipelineProviding {}

/// Recording overlay surface used by AppState.
@MainActor
protocol OverlayPresenting: AnyObject {
    func show()
    func hide()
    func setProcessing()
    func updateAudioLevel(_ level: Float)
}

extension OverlayWindowController: OverlayPresenting {}

/// Paste boundary used by AppState.
protocol PasteServicing: Sendable {
    @MainActor
    func pasteAndRestore(text: String, captureID: String?) async -> PasteTiming
}

extension PasteService: PasteServicing {}

/// History persistence boundary used by AppState.
@MainActor
protocol HistoryStoring: AnyObject {
    func add(
        original: String,
        refined: String,
        presetName: String,
        systemPrompt: String,
        effectiveSystemPrompt: String?,
        variants: [String: String]?,
        variantPrompts: [String: String]?,
        effectiveVariantPrompts: [String: String]?
    )
}

extension HistoryStore: HistoryStoring {}

/// Microphone permission boundary used by AppState.
protocol MicrophonePermissionChecking: Sendable {
    func checkMicrophonePermission() async -> Bool
}

extension PermissionService: MicrophonePermissionChecking {}
