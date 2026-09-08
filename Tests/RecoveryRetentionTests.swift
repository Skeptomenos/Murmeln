import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("Recovery retention", .serialized)
struct RecoveryRetentionTests {
    @Test("Disk failure cannot silently evict an unsaved History result")
    func failedSavesDoNotEvict() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let persistence = HistoryPersistence(fileURL: url, writer: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let store = HistoryStore(fileURL: url, legacyDefaults: defaults, persistence: persistence)
        for number in 0..<50 {
            store.add(original: "result \(number)", refined: "result \(number)", presetName: "Raw", systemPrompt: "")
        }
        await store.flush()
        let ids = Set(store.entries.map(\.id))
        store.add(original: "overflow", refined: "overflow", presetName: "Raw", systemPrompt: "")
        await store.flush()
        #expect(store.entries.count == 50)
        #expect(Set(store.entries.map(\.id)) == ids)
        let recorder = MockAudioRecorder()
        let app = AppState(audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "unused", refinementShouldThrow: false),
            overlay: MockOverlay(), pasteService: MockPasteService(), historyStore: store,
            permissionService: MockPermissionService(), accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(app.recordingPhase == .idle && recorder.startRecordingCalls == 0)
        #expect(app.captureAdmissionMessage != nil)
        store.remove(entry: try #require(store.entries.first))
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        _ = await app.quiesceForTermination()
    }

    @Test("Secure Input offers repeated Copy of the exact retained result")
    func secureInputCopySurvivesSuccessAndNewWarmup() async throws {
        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = MockPasteService(pasteTiming: PasteTiming(
            commandOutcome: .blocked(.secureInputActive), clipboardDisposition: .unchanged,
            commandSentElapsedMs: nil, totalElapsedMs: 0
        ), recoveryCopyResults: [true, true])
        let history = MockHistoryStore()
        let app = AppState(audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "retain this", refinementShouldThrow: true),
            overlay: MockOverlay(), pasteService: paste, historyStore: history,
            permissionService: MockPermissionService(), accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && history.entries.count == 1 })
        let expected = try #require(history.entries.first?.refined)
        app.copyFailedPasteAgain()
        app.copyFailedPasteAgain()
        #expect(paste.recoveryCopyTexts == [expected, expected])
        #expect(app.pasteFailurePresentation != nil)
        app.warmUpEngine()
        app.cancelWarmUp()
        #expect(await waitUntil { app.recordingPhase == .idle })
        #expect(app.pasteFailurePresentation != nil)
    }
}
