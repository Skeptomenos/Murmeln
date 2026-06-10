import Testing
import Foundation
import AVFoundation
@testable import mrml

// Real AppState tests, made possible by the constructor-injection seams in
// AppStateDependencies.swift. These drive the actual capture flow
// (startRecording → stopAndProcess) against mocks and a generated WAV fixture.

// MARK: - Mocks

final class MockAudioRecorder: AudioCapturing, @unchecked Sendable {
    private let lock = NSLock()
    private var _startRecordingCalls = 0
    private var _beginCaptureCalls = 0
    var recordingURL: URL?

    var startRecordingCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _startRecordingCalls
    }

    var beginCaptureCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return _beginCaptureCalls
    }

    /// Simulated engine warm-up latency, so tests can cancel mid-prepare.
    var prepareEngineDelayMs: UInt64 = 0

    private func finishedStream() -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }

    func prepareEngine(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float> {
        if prepareEngineDelayMs > 0 {
            try? await Task.sleep(for: .milliseconds(prepareEngineDelayMs))
        }
        return finishedStream()
    }

    private func increment(_ keyPath: ReferenceWritableKeyPath<MockAudioRecorder, Int>) {
        lock.lock(); self[keyPath: keyPath] += 1; lock.unlock()
    }

    func beginCapture(captureID: String?) async throws {
        increment(\._beginCaptureCalls)
    }

    func cancelWarmUp() async {}

    func startRecording(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float> {
        increment(\._startRecordingCalls)
        return finishedStream()
    }

    func stopRecording(captureID: String?) async -> URL? {
        recordingURL
    }
}

final class MockPermissionService: MicrophonePermissionChecking, @unchecked Sendable {
    let result: Bool
    let delayMs: UInt64

    init(result: Bool = true, delayMs: UInt64 = 0) {
        self.result = result
        self.delayMs = delayMs
    }

    func checkMicrophonePermission() async -> Bool {
        if delayMs > 0 {
            try? await Task.sleep(for: .milliseconds(delayMs))
        }
        return result
    }
}

struct MockRefinementError: Error, LocalizedError {
    var errorDescription: String? { "mock refinement provider down" }
}

final class MockPipelineService: TranscriptionPipelineProviding, @unchecked Sendable {
    let transcriptionText: String
    let refinementShouldThrow: Bool

    init(transcriptionText: String, refinementShouldThrow: Bool) {
        self.transcriptionText = transcriptionText
        self.refinementShouldThrow = refinementShouldThrow
    }

    func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode {
        .twoCallRefinement
    }

    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult {
        let now = DispatchTime.now().uptimeNanoseconds
        return TranscriptionExecutionResult(
            text: transcriptionText,
            runContext: TranscriptionRunContext(
                provider: "mock",
                backendKind: .cloud,
                supportTier: .legacyCompatibility,
                pipelineMode: .twoCallRefinement,
                model: "mock-model",
                backendConfigFingerprint: "mock",
                refinementProvider: "mock",
                refinementModel: "mock-refiner",
                refinementConfigFingerprint: "mock",
                languageMode: .notApplicable,
                languageCode: nil,
                audioDurationMs: request.audioDurationMs,
                warmState: .notApplicable,
                refinementEnabled: true
            ),
            backendLoadTiming: nil,
            transcriptionTiming: StageTiming(startedAt: now, finishedAt: now)
        )
    }

    func executeRefinement(request: RefinementRequest) async throws -> RefinementExecutionResult {
        if refinementShouldThrow {
            throw MockRefinementError()
        }
        let now = DispatchTime.now().uptimeNanoseconds
        return RefinementExecutionResult(
            text: "refined: \(request.text)",
            timing: StageTiming(startedAt: now, finishedAt: now)
        )
    }
}

@MainActor
final class MockOverlay: OverlayPresenting {
    private(set) var showCalls = 0
    private(set) var hideCalls = 0

    func show() { showCalls += 1 }
    func hide() { hideCalls += 1 }
    func setProcessing() {}
    func updateAudioLevel(_ level: Float) {}
}

@MainActor
final class MockPasteService: PasteServicing {
    private(set) var pastedTexts: [String] = []

    func pasteAndRestore(text: String, captureID: String?) async -> PasteTiming {
        pastedTexts.append(text)
        return PasteTiming(succeeded: true, commandSentElapsedMs: 0, totalElapsedMs: 0)
    }
}

@MainActor
final class MockHistoryStore: HistoryStoring {
    struct Entry {
        let original: String
        let refined: String
        let presetName: String
    }

    private(set) var entries: [Entry] = []

    func add(
        original: String,
        refined: String,
        presetName: String,
        systemPrompt: String,
        effectiveSystemPrompt: String?,
        variants: [String: String]?,
        variantPrompts: [String: String]?,
        effectiveVariantPrompts: [String: String]?
    ) {
        entries.append(Entry(original: original, refined: refined, presetName: presetName))
    }
}

// MARK: - Fixtures & helpers

enum AppStateTestFixtures {
    /// Writes a 0.5s 16kHz mono WAV loud enough that the real
    /// AudioRecorder.hasAudibleSpeech treats it as speech.
    static func makeAudibleWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-test-\(UUID().uuidString).wav")
        let sampleRate = 16_000.0
        let frameCount = AVAudioFrameCount(sampleRate / 2)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MockRefinementError()
        }
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            channel[frame] = sinf(2.0 * .pi * 440.0 * Float(frame) / Float(sampleRate)) * 0.5
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        return file.url
    }
}

@MainActor
func waitUntil(timeoutMs: Int = 8_000, _ condition: () -> Bool) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

// MARK: - Tests

@MainActor
@Suite("AppState Capture Flow Tests", .serialized)
struct AppStateCaptureFlowTests {

    @Test("Refinement failure degrades to the raw transcript instead of losing it")
    func refinementFailureDegradesToRaw() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService()
        let history = MockHistoryStore()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "raw transcript survives", refinementShouldThrow: true),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService()
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })

        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && !paste.pastedTexts.isEmpty })

        // The raw transcript must reach the paste boundary…
        #expect(paste.pastedTexts == ["raw transcript survives"])
        // …and history, with the refinement-failed marker.
        #expect(history.entries.count == 1)
        #expect(history.entries.first?.original == "raw transcript survives")
        #expect(history.entries.first?.refined == "raw transcript survives")
        #expect(history.entries.first?.presetName.contains("refinement failed") == true)
        // The failure stays visible in the UI.
        #expect(appState.lastError == "Refinement failed — pasted the raw transcript.")
    }

    @Test("Cancelling during the permission await leaves no zombie recording (H2/spec-002)")
    func cancelDuringPermissionAwaitLeavesNoZombie() async throws {
        let recorder = MockAudioRecorder()
        // No recording URL: the stop path takes the no-audio branch and goes idle.
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "unused", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: MockPasteService(),
            historyStore: MockHistoryStore(),
            permissionService: MockPermissionService(result: true, delayMs: 150)
        )

        appState.startRecording()
        #expect(appState.recordingPhase == .requestingPermission)

        // Quick lock-disengage while the permission check is still pending.
        appState.stopAndProcess()

        // Give the cancelled task ample time to (wrongly) resume.
        try await Task.sleep(for: .milliseconds(400))

        #expect(appState.recordingPhase == .idle)
        #expect(recorder.startRecordingCalls == 0)
    }

    @Test("Cancelled warm-up never shows an orphaned overlay (M7)")
    func cancelledWarmUpShowsNoOrphanOverlay() async throws {
        let recorder = MockAudioRecorder()
        recorder.prepareEngineDelayMs = 150
        let overlay = MockOverlay()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "unused", refinementShouldThrow: false),
            overlay: overlay,
            pasteService: MockPasteService(),
            historyStore: MockHistoryStore(),
            permissionService: MockPermissionService()
        )

        appState.warmUpEngine()
        #expect(await waitUntil { appState.recordingPhase == .warmingUp })

        // Quick Fn release before the threshold cancels the warm-up while
        // prepareEngine is still in flight.
        appState.cancelWarmUp()
        try await Task.sleep(for: .milliseconds(400))

        #expect(appState.recordingPhase == .idle)
        #expect(overlay.showCalls == 0, "cancelled warm-up must not re-show the overlay")
    }

    @Test("Successful refinement pastes the refined text")
    func successfulRefinementPastesRefinedText() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService()
        let history = MockHistoryStore()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "hello", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService()
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })

        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && !paste.pastedTexts.isEmpty })

        #expect(paste.pastedTexts == ["refined: hello"])
        #expect(history.entries.first?.refined == "refined: hello")
        #expect(appState.lastError == nil)
    }
}
