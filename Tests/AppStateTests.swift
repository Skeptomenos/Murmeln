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
    let mode: TranscriptionPipelineMode
    let transcriptionError: TranscriptionRuntimeError?

    init(
        transcriptionText: String,
        refinementShouldThrow: Bool,
        mode: TranscriptionPipelineMode = .twoCallRefinement,
        transcriptionError: TranscriptionRuntimeError? = nil
    ) {
        self.transcriptionText = transcriptionText
        self.refinementShouldThrow = refinementShouldThrow
        self.mode = mode
        self.transcriptionError = transcriptionError
    }

    func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode {
        mode
    }

    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult {
        if let transcriptionError {
            throw transcriptionError
        }
        let now = DispatchTime.now().uptimeNanoseconds
        return TranscriptionExecutionResult(
            text: transcriptionText,
            runContext: TranscriptionRunContext(
                provider: "mock",
                backendKind: .cloud,
                supportTier: .legacyCompatibility,
                pipelineMode: mode,
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
    private(set) var recoveryCopyTexts: [String] = []
    var pasteTiming: PasteTiming
    var recoveryCopyResults: [Bool]

    init(
        pasteTiming: PasteTiming = PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restored,
            commandSentElapsedMs: 0,
            totalElapsedMs: 0
        ),
        recoveryCopyResults: [Bool] = []
    ) {
        self.pasteTiming = pasteTiming
        self.recoveryCopyResults = recoveryCopyResults
    }

    func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming {
        pastedTexts.append(text)
        return pasteTiming
    }

    func copyToClipboardForRecovery(text: String) -> Bool {
        recoveryCopyTexts.append(text)
        guard !recoveryCopyResults.isEmpty else { return false }
        return recoveryCopyResults.removeFirst()
    }
}

@MainActor
final class MockHistoryStore: HistoryStoring {
    var mutationsSuspended = false
    var protectedRecoveryID: UUID?
    var onEntriesChanged: (@MainActor () -> Void)?
    private var retained: [UUID: HistoryEntry] = [:]
    func reserveCapacity() -> UUID? { UUID() }
    func releaseReservation(_ token: UUID) {}
    func entry(id: UUID) -> HistoryEntry? { retained[id] }
    func flush() async -> Bool { true }
    func retain(_ entry: HistoryEntry, reservation: UUID) -> Bool {
        retained[entry.id] = entry
        add(original: entry.original, refined: entry.refined, presetName: entry.safePresetName,
            systemPrompt: entry.safeSystemPrompt, effectiveSystemPrompt: entry.effectiveSystemPrompt,
            variants: entry.variants, variantPrompts: entry.variantPrompts,
            effectiveVariantPrompts: entry.effectiveVariantPrompts)
        onEntriesChanged?()
        return true
    }
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

@MainActor
final class MockSettingsRecoveryPresenter: SettingsRecoveryPresenting {
    private(set) var modelIDs: [TranscriptionModelID] = []

    func showRecovery(for modelID: TranscriptionModelID) {
        modelIDs.append(modelID)
    }
}

// MARK: - Fixtures & helpers

enum AppStateTestFixtures {
    /// Writes a 0.5s 16kHz mono WAV loud enough that the real
    /// AudioRecorder.hasAudibleSpeech treats it as speech.
    static func makeAudibleWAV(durationSeconds: Double = 0.5) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-test-\(UUID().uuidString).wav")
        let sampleRate = 16_000.0
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
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

    @Test("A missing model opens recovery once and stops before paste or History")
    func modelNotInstalledOpensRecoveryExactlyOnce() async throws {
        let modelID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        let recorder = MockAudioRecorder()
        let recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        recorder.recordingURL = recordingURL
        let paste = MockPasteService()
        let history = MockHistoryStore()
        let overlay = MockOverlay()
        let recovery = MockSettingsRecoveryPresenter()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(
                transcriptionText: "must not exist",
                refinementShouldThrow: false,
                transcriptionError: .modelNotInstalled(modelID)
            ),
            overlay: overlay,
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            settingsRecoveryPresenter: recovery
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil {
            appState.recordingPhase == .idle && appState.diagnosticsActiveCaptureID == nil
        })

        #expect(recovery.modelIDs == [modelID])
        #expect(paste.pastedTexts.isEmpty)
        #expect(history.entries.isEmpty)
        #expect(appState.pasteFailurePresentation == nil)
        #expect(appState.lastError?.contains("Cohere Transcribe") == true)
        #expect(appState.lastError?.contains("Download Model") == true)
        #expect(overlay.hideCalls == 1)
        #expect(!FileManager.default.fileExists(atPath: recordingURL.path))
    }

    @Test("A generic runtime failure does not open Settings")
    func genericRuntimeFailureDoesNotOpenSettings() async throws {
        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService()
        let history = MockHistoryStore()
        let recovery = MockSettingsRecoveryPresenter()
        let failure = TranscriptionRuntimeError.runtimeFailure(
            .fluidAudio,
            .load,
            "synthetic load failure"
        )
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(
                transcriptionText: "must not exist",
                refinementShouldThrow: false,
                transcriptionError: failure
            ),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            settingsRecoveryPresenter: recovery
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil {
            appState.recordingPhase == .idle && appState.diagnosticsActiveCaptureID == nil
        })

        #expect(recovery.modelIDs.isEmpty)
        #expect(paste.pastedTexts.isEmpty)
        #expect(history.entries.isEmpty)
        #expect(appState.lastError == "Processing failed. Any completed result remains in History.")
    }

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
        #expect(appState.lastError == "Refinement failed — raw transcript paste command sent.")
    }

    @Test("Empty raw transcript after refinement failure does not claim a paste command")
    func emptyRawTranscriptAfterRefinementFailureDoesNotClaimPasteCommand() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV(durationSeconds: 1.5)
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .notAttempted,
            clipboardDisposition: .unchanged,
            commandSentElapsedMs: nil,
            totalElapsedMs: 0
        ))
        let history = MockHistoryStore()
        var announcements: [String] = []
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "", refinementShouldThrow: true),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { announcements.append($0) }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && paste.pastedTexts.count == 1 })

        #expect(paste.pastedTexts == [""])
        #expect(appState.lastError == "Refinement failed — the raw transcript was empty, so no paste command was sent.")
        #expect(appState.pasteFailurePresentation == nil)
        #expect(!announcements.contains("Paste command sent"))
        #expect(!announcements.contains("Text pasted"))
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
        var announcements: [String] = []
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "hello", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { announcements.append($0) }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })

        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && !paste.pastedTexts.isEmpty })

        #expect(paste.pastedTexts == ["refined: hello"])
        #expect(history.entries.first?.refined == "refined: hello")
        #expect(appState.lastError == nil)
        #expect(announcements.last == "Paste command sent")
        #expect(!announcements.contains("Text pasted"))
    }

    @Test("Every paste blocker reaches AppState with its exact recovery message")
    func pasteBlockersReachAppStateWithExactRecovery() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let blockers: [PasteBlocker] = [
            .postEventAccessDenied,
            .secureInputActive,
            .keyEventCreationFailed,
            .clipboardWriteFailed,
            .clipboardChanged,
            .clipboardSnapshotUnavailable,
            .cancelled,
        ]

        for blocker in blockers {
            let pasteAttemptID = "ABCDEF12-\(blocker.rawValue)"
            let recorder = MockAudioRecorder()
            recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
            let paste = MockPasteService(pasteTiming: PasteTiming(
                commandOutcome: .blocked(blocker),
                clipboardDisposition: .transcriptPreserved,
                commandSentElapsedMs: nil,
                totalElapsedMs: 0,
                pasteAttemptID: pasteAttemptID
            ))
            let history = MockHistoryStore()
            var announcements: [String] = []
            let appState = AppState(
                audioRecorder: recorder,
                pipelineService: MockPipelineService(transcriptionText: "hello", refinementShouldThrow: false),
                overlay: MockOverlay(),
                pasteService: paste,
                historyStore: history,
                permissionService: MockPermissionService(),
                accessibilityAnnouncement: { announcements.append($0) }
            )

            appState.startRecording()
            #expect(await waitUntil { appState.recordingPhase == .recording })
            appState.stopAndProcess()
            #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })

            let expected = PasteFailurePresentation(
                blocker: blocker,
                clipboardDisposition: .transcriptPreserved,
                pasteAttemptID: pasteAttemptID
            )
            #expect(appState.lastError == expected.message)
            #expect(appState.pasteFailurePresentation == expected)
            #expect(announcements.last == expected.message)
            #expect(history.entries.first?.original == "hello")
            #expect(history.entries.first?.refined == "refined: hello")
        }
    }

    @Test("Posted command keeps its outcome when clipboard restoration fails")
    func postedCommandWithRestoreFailureWarnsWithoutInventingDelivery() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restoreFailed,
            commandSentElapsedMs: 1,
            totalElapsedMs: 2
        ))
        let history = MockHistoryStore()
        var announcements: [String] = []
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "hello", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { announcements.append($0) }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })

        let warning = "Paste command sent, but Murmeln could not restore your previous clipboard contents."
        #expect(appState.lastError == warning)
        #expect(appState.pasteFailurePresentation == nil)
        #expect(Array(announcements.suffix(2)) == ["Paste command sent", warning])
        #expect(!announcements.contains("Text pasted"))
    }

    @Test("Blocked command with a newer clipboard write offers truthful History recovery")
    func blockedCommandWithExternalWriteOffersHistoryRecovery() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .blocked(.postEventAccessDenied),
            clipboardDisposition: .externalWritePreserved,
            commandSentElapsedMs: nil,
            totalElapsedMs: 1
        ))
        let history = MockHistoryStore()
        var announcements: [String] = []
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "hello", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { announcements.append($0) }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })

        let expected = PasteFailurePresentation(
            blocker: .postEventAccessDenied,
            clipboardDisposition: .externalWritePreserved
        )
        #expect(appState.lastError == expected.message)
        #expect(appState.pasteFailurePresentation == expected)
        #expect(expected.recoveryActions.contains(.openHistory))
        #expect(!expected.message.contains("Your transcript is on the clipboard"))
        #expect(announcements.last == expected.message)
    }

    @Test("Clipboard write failure keeps History recovery and Copy Again retries the exact final text")
    func clipboardWriteFailureOffersCheckedCopyAgain() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(
            pasteTiming: PasteTiming(
                commandOutcome: .blocked(.clipboardWriteFailed),
                clipboardDisposition: .restored,
                commandSentElapsedMs: nil,
                totalElapsedMs: 0,
            ),
            recoveryCopyResults: [false, true]
        )
        let history = MockHistoryStore()
        var announcements: [String] = []
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "recoverable", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { announcements.append($0) }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })

        let expected = PasteFailurePresentation(
            blocker: .clipboardWriteFailed,
            clipboardDisposition: .restored
        )
        #expect(appState.pasteFailurePresentation == expected)
        #expect(expected.recoveryActions.contains(.openHistory))
        #expect(expected.recoveryActions.contains(.copyAgain))
        #expect(history.entries.first?.refined == "refined: recoverable")

        appState.copyFailedPasteAgain()
        #expect(paste.recoveryCopyTexts == ["refined: recoverable"])
        #expect(appState.pasteFailurePresentation == expected)
        #expect(appState.lastError == expected.message)

        appState.copyFailedPasteAgain()
        #expect(paste.recoveryCopyTexts == ["refined: recoverable", "refined: recoverable"])
        #expect(appState.pasteFailurePresentation == expected)
        #expect(appState.hasPasteRecovery)
        #expect(announcements.last == ClipboardCopyOutcome.copied.message)
    }

    @Test("Cancelled warm-up preserves a prior clipboard recovery action")
    func cancelledWarmUpPreservesPasteRecovery() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .blocked(.clipboardWriteFailed),
            clipboardDisposition: .restored,
            commandSentElapsedMs: nil,
            totalElapsedMs: 0,
        ))
        let history = MockHistoryStore()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "recover me", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { _ in }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })

        let expected = PasteFailurePresentation(
            blocker: .clipboardWriteFailed,
            clipboardDisposition: .restored
        )
        #expect(appState.pasteFailurePresentation == expected)

        recorder.prepareEngineDelayMs = 150
        appState.warmUpEngine()
        #expect(await waitUntil { appState.recordingPhase == .warmingUp })
        appState.cancelWarmUp()
        try await Task.sleep(for: .milliseconds(250))

        #expect(appState.recordingPhase == .idle)
        #expect(appState.pasteFailurePresentation == expected)
        #expect(appState.lastError == expected.message)
    }

    @Test("Starting a new recording preserves the prior recovery result")
    func newRecordingPreservesPasteRecovery() async throws {
        let previousParallel = AppSettings.shared.parallelRefinementEnabled
        AppSettings.shared.parallelRefinementEnabled = false
        defer { AppSettings.shared.parallelRefinementEnabled = previousParallel }

        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .blocked(.clipboardWriteFailed),
            clipboardDisposition: .restored,
            commandSentElapsedMs: nil,
            totalElapsedMs: 0,
        ))
        let history = MockHistoryStore()
        let appState = AppState(
            audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "first", refinementShouldThrow: false),
            overlay: MockOverlay(),
            pasteService: paste,
            historyStore: history,
            permissionService: MockPermissionService(),
            accessibilityAnnouncement: { _ in }
        )

        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })
        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 1 })
        #expect(appState.pasteFailurePresentation != nil)

        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        paste.pasteTiming = PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restored,
            commandSentElapsedMs: 0,
            totalElapsedMs: 0
        )
        appState.startRecording()
        #expect(await waitUntil { appState.recordingPhase == .recording })

        #expect(appState.pasteFailurePresentation != nil)

        appState.stopAndProcess()
        #expect(await waitUntil { appState.recordingPhase == .idle && history.entries.count == 2 })
    }
}
