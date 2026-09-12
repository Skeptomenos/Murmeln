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

/// Settings recovery surface used for typed local-model failures.
@MainActor
protocol SettingsRecoveryPresenting: AnyObject {
    func showRecovery(for modelID: TranscriptionModelID)
}

/// Paste boundary used by AppState.
protocol PasteServicing: Sendable {
    @MainActor
    func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming

    @MainActor
    func pasteAndRestore(text: String, captureID: String?, target: (any PasteTargetChecking)?) async throws -> PasteTiming

    @MainActor
    func copyToClipboardForRecovery(text: String) -> Bool

    @MainActor func copyResult(text: String) -> ClipboardCopyOutcome
}

extension PasteServicing {
    @MainActor
    func pasteAndRestore(text: String, captureID: String?, target: (any PasteTargetChecking)?) async throws -> PasteTiming {
        try await pasteAndRestore(text: text, captureID: captureID)
    }
    @MainActor func copyResult(text: String) -> ClipboardCopyOutcome {
        copyToClipboardForRecovery(text: text) ? .copied : .failed
    }
}

extension PasteService: PasteServicing {}

/// History persistence boundary used by AppState.
@MainActor
protocol HistoryStoring: AnyObject {
    var mutationsSuspended: Bool { get set }
    var protectedRecoveryID: UUID? { get set }
    var onEntriesChanged: (@MainActor () -> Void)? { get set }
    func reserveCapacity() -> UUID?
    func releaseReservation(_ token: UUID)
    func retain(_ entry: HistoryEntry, reservation: UUID) -> Bool
    func entry(id: UUID) -> HistoryEntry?
    func flush() async -> Bool
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
