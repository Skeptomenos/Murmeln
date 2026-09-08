import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("Recovery final result modes", .serialized)
struct RecoveryResultModeTests {
    @Test("Quit preserves selected parallel success while joining cancelled sibling work")
    func quitDuringParallelAudit() async throws {
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let selectedPrompt = AppSettings.shared.systemPrompt
        #expect(!selectedPrompt.isEmpty)
        let pipeline = SuspendedParallelPipeline(selectedPrompt: selectedPrompt)
        let paste = MockPasteService()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let app = AppState(audioRecorder: audio, pipelineService: pipeline, overlay: MockOverlay(),
            pasteService: paste, historyStore: history, permissionService: MockPermissionService(),
            pipelineSettingsSnapshot: { settings(parallel: true) }, accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        for _ in 0..<200 {
            if await pipeline.ready { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await pipeline.ready)
        let quit = Task { await app.quiesceForTermination() }
        #expect(await waitUntil { app.isTerminating })
        await pipeline.release()
        #expect(await quit.value)
        #expect(history.entries.first?.refined == "selected final result")
        #expect(app.recoveryEntryID == history.entries.first?.id)
        #expect(paste.pastedTexts.isEmpty)
    }

    private func settings(parallel: Bool) -> PipelineSettingsSnapshot {
        PipelineSettingsSnapshot(transcriptionProvider: .openAIWhisper, transcriptionAPIKey: "",
            transcriptionBaseURL: "https://example.test", transcriptionModel: "fixture",
            refinementProvider: .openAI, refinementAPIKey: "", refinementBaseURL: "https://example.test",
            refinementModel: "fixture", skipRefinement: false, parallelRefinementEnabled: parallel,
            whisperKitProfile: .balanced, whisperKitTemperature: 0, whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false, whisperKitUseVAD: true, whisperKitLanguages: [.english])
    }

    @Test("Every final-result path retains exact text and identity before recovery", arguments: [0, 1, 2, 3, 4])
    func resultModes(kind: Int) async throws {
        let mode: TranscriptionPipelineMode = kind == 0 ? .transcribeOnly : (kind == 1 ? .oneCallTranscriptionAndRefinement : .twoCallRefinement)
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(commandOutcome: .blocked(.secureInputActive),
            clipboardDisposition: .unchanged, commandSentElapsedMs: nil, totalElapsedMs: 0), recoveryCopyResults: [true, true])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let app = AppState(audioRecorder: audio,
            pipelineService: MockPipelineService(transcriptionText: "  Exact result.\n", refinementShouldThrow: kind == 3, mode: mode),
            overlay: MockOverlay(), pasteService: paste, historyStore: history, permissionService: MockPermissionService(),
            pipelineSettingsSnapshot: { settings(parallel: kind == 4) }, accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && app.hasPasteRecovery })
        let entry = try #require(history.entries.first)
        let expected = kind == 2 || kind == 4 ? "refined:   Exact result.\n" : "  Exact result.\n"
        #expect(entry.refined == expected)
        #expect(app.recoveryEntryID == entry.id && entry.captureID != nil)
        if kind == 4 { #expect(entry.hasParallelAuditTrail) }
        app.copyFailedPasteAgain()
        app.dismissPasteRecovery()
        #expect(await history.flush())
        #expect(app.recoveryDismissed) // Receipt cannot resurrect the notice.
        app.copyFailedPasteAgain()
        #expect(app.recoveryDismissed)
        #expect(paste.recoveryCopyTexts == [expected, expected])
        history.clear()
        #expect(!app.hasPasteRecovery)
        app.copyFailedPasteAgain()
        #expect(paste.recoveryCopyTexts.count == 2)
        #expect(await history.flush())
    }

    @Test("Whitespace completion preserves the prior card and releases capacity")
    func emptyResultKeepsPriorCard() async throws {
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let history = MockHistoryStore()
        let paste = MockPasteService(pasteTiming: PasteTiming(commandOutcome: .blocked(.secureInputActive),
            clipboardDisposition: .unchanged, commandSentElapsedMs: nil, totalElapsedMs: 0))
        let pipeline = MutableResultPipeline()
        let app = AppState(audioRecorder: audio, pipelineService: pipeline, overlay: MockOverlay(), pasteService: paste,
            historyStore: history, permissionService: MockPermissionService(), accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && app.hasPasteRecovery })
        let oldID = app.recoveryEntryID
        await pipeline.setEmpty()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle })
        #expect(app.recoveryEntryID == oldID)
        #expect(history.entries.count == 1)
    }
}

private actor MutableResultPipeline: TranscriptionPipelineProviding {
    var text = "original result"
    func setEmpty() { text = " \n\t" }
    nonisolated func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode { .transcribeOnly }
    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult {
        try await MockPipelineService(transcriptionText: text, refinementShouldThrow: false, mode: .transcribeOnly)
            .executeTranscription(request: request)
    }
    func executeRefinement(request: RefinementRequest) async throws -> RefinementExecutionResult { throw MockRefinementError() }
}

private actor SuspendedParallelPipeline: TranscriptionPipelineProviding {
    let selectedPrompt: String
    var selectedFinished = false
    var siblings: [CheckedContinuation<Void, Never>] = []
    var ready: Bool { selectedFinished && !siblings.isEmpty }
    init(selectedPrompt: String) { self.selectedPrompt = selectedPrompt }
    nonisolated func pipelineMode(for settings: PipelineSettingsSnapshot) -> TranscriptionPipelineMode { .twoCallRefinement }
    func executeTranscription(request: TranscriptionRequest) async throws -> TranscriptionExecutionResult {
        try await MockPipelineService(transcriptionText: "baseline", refinementShouldThrow: false).executeTranscription(request: request)
    }
    func executeRefinement(request: RefinementRequest) async throws -> RefinementExecutionResult {
        if request.systemPrompt.hasPrefix(selectedPrompt) {
            selectedFinished = true
            return RefinementExecutionResult(text: "selected final result", timing: StageTiming(startedAt: 1, finishedAt: 2))
        }
        await withCheckedContinuation { siblings.append($0) }
        throw CancellationError()
    }
    func release() { for sibling in siblings { sibling.resume() }; siblings.removeAll() }
}
