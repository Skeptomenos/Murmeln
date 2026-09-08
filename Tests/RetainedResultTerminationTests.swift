import Foundation
import Testing
@testable import mrml

@MainActor
private final class SuspendedRecoveryPaste: PasteServicing {
    var waiting = false
    var copied: [String] = []
    var continuation: CheckedContinuation<Void, Never>?
    func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        return PasteTiming(commandOutcome: .posted, clipboardDisposition: .restored, commandSentElapsedMs: 0, totalElapsedMs: 0)
    }
    func copyToClipboardForRecovery(text: String) -> Bool { copied.append(text); return true }
}

@MainActor
@Suite("Retained result termination")
struct RetainedResultTerminationTests {
    @Test("Failed Quit joins delivery, retains exact text, restores admission and permits later Quit")
    func quitWithSuspendedDelivery() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecoveryDiskWriter([false])
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            persistence: HistoryPersistence(fileURL: url, writer: { try await writer.write($0, to: $1) }))
        let recorder = MockAudioRecorder()
        recorder.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let paste = SuspendedRecoveryPaste()
        let app = AppState(audioRecorder: recorder,
            pipelineService: MockPipelineService(transcriptionText: "exact final", refinementShouldThrow: true),
            overlay: MockOverlay(), pasteService: paste, historyStore: history,
            permissionService: MockPermissionService(), accessibilityAnnouncement: { _ in })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { paste.waiting })
        let entry = try #require(history.entries.first)
        #expect(entry.captureID != nil)
        #expect(entry.refined == "exact final")
        var replies: [Bool] = []
        var suspends = 0
        var restores = 0
        let quit = TerminationCoordinator(suspend: { suspends += 1 },
            quiesce: { await app.quiesceForTermination() }, restore: { restores += 1; app.resumeAfterCancelledTermination() })
        #expect(quit.begin { replies.append($0) })
        #expect(!quit.begin { replies.append($0) })
        #expect(await waitUntil { app.isTerminating })
        history.clear()
        #expect(history.entries == [entry])
        #expect(replies.isEmpty)
        paste.continuation?.resume()
        paste.continuation = nil
        #expect(await waitUntil { replies == [false] })
        #expect(suspends == 1 && restores == 1)
        #expect(!app.isTerminating && !history.mutationsSuspended && !quit.isInFlight)
        #expect(app.recoveryEntryID == entry.id)
        app.copyFailedPasteAgain()
        #expect(paste.copied == [entry.refined])
        #expect(!history.isSaved(entry.id))
        history.retrySave()
        #expect(await history.flush())
        #expect(quit.begin { replies.append($0) })
        #expect(await waitUntil { replies == [false, true] })
        #expect(suspends == 2 && restores == 1)
    }
}
