import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Recovery attention", .serialized)
struct RecoveryAttentionTests {
    @Test("Only successful Copy acknowledges attention and retains the exact result",
          arguments: [ClipboardCopyOutcome.copied, .busy, .failed, .restorationFailed])
    func copyAttention(outcome: ClipboardCopyOutcome) async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
        let entry = try #require(fixture.history.entries.first)
        fixture.paste.copyOutcome = outcome

        fixture.app.copyFailedPasteAgain()

        #expect(fixture.paste.copied == [entry.displayText])
        #expect(fixture.app.recoveryMessage == outcome.message)
        if outcome == .copied {
            #expect(!fixture.app.needsPasteRecoveryAttention)
            #expect(await waitUntil(timeoutMs: 200) { !fixture.display.visible })
            #expect(fixture.app.lastError == nil)
        } else {
            #expect(fixture.app.needsPasteRecoveryAttention)
            #expect(fixture.display.visible)
        }
        #expect(fixture.app.recoveryEntryID == entry.id)
        #expect(fixture.app.hasPasteRecovery)
        #expect(fixture.history.entry(id: entry.id)?.displayText == "  Exact retained result.\n")
        #expect(await fixture.history.flush())
        fixture.postResumeNotifications()
        #expect(fixture.display.visible == (outcome != .copied))
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("Dismiss clears attention and stale blocker text without clearing unrelated errors")
    func dismissalRetainsResult() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
        let entry = try #require(fixture.history.entries.first)
        fixture.app.lastError = "A separate model warning"

        fixture.app.dismissPasteRecovery()

        #expect(!fixture.app.needsPasteRecoveryAttention)
        #expect(await waitUntil(timeoutMs: 200) { !fixture.display.visible })
        #expect(fixture.app.lastError == "A separate model warning")
        #expect(fixture.app.recoveryMessage == "Your text remains available in History.")
        #expect(fixture.app.recoveryEntryID == entry.id && fixture.app.hasPasteRecovery)
        fixture.postResumeNotifications()
        #expect(!fixture.display.visible && !fixture.app.needsPasteRecoveryAttention)
        #expect(await fixture.history.flush())
        fixture.history.remove(entry: entry)
        #expect(!fixture.app.hasPasteRecovery)
        fixture.postResumeNotifications()
        #expect(!fixture.display.visible)
        fixture.app.copyFailedPasteAgain()
        #expect(fixture.paste.copied.isEmpty)
        #expect(await fixture.history.flush())
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("A later posted command acknowledges old attention without deleting its result")
    func laterPostedCommandAcknowledgesOldAttention() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
        let entry = try #require(fixture.history.entries.first)
        fixture.paste.timing = PasteTiming(commandOutcome: .posted, clipboardDisposition: .restored,
                                          commandSentElapsedMs: 0, totalElapsedMs: 0)
        fixture.audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()

        fixture.app.startRecording()
        #expect(await waitUntil { fixture.app.recordingPhase == .recording })
        #expect(fixture.app.needsPasteRecoveryAttention)
        fixture.app.stopAndProcess()
        #expect(await waitUntil { fixture.app.recordingPhase == .idle && fixture.history.entries.count == 2 })

        #expect(!fixture.app.needsPasteRecoveryAttention)
        #expect(await waitUntil(timeoutMs: 200) { !fixture.display.visible })
        #expect(fixture.app.recoveryEntryID == entry.id && fixture.app.hasPasteRecovery)
        #expect(fixture.history.entry(id: entry.id)?.displayText == entry.displayText)
        #expect(fixture.app.recoveryMessage == "Your text remains available in History.")
        fixture.postResumeNotifications()
        #expect(!fixture.display.visible)
        fixture.paste.timing = PasteTiming(commandOutcome: .blocked(.secureInputActive), clipboardDisposition: .unchanged,
                                          commandSentElapsedMs: nil, totalElapsedMs: 0)
        fixture.audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        fixture.app.startRecording()
        #expect(await waitUntil { fixture.app.recordingPhase == .recording })
        fixture.app.stopAndProcess()
        #expect(await waitUntil { fixture.app.recordingPhase == .idle && fixture.history.entries.count == 3 })
        #expect(fixture.app.needsPasteRecoveryAttention)
        #expect(await waitUntil(timeoutMs: 200) { fixture.display.visible })
        #expect(fixture.app.recoveryEntryID != entry.id)
        #expect(fixture.history.entry(id: entry.id)?.displayText == entry.displayText)
        #expect(await fixture.history.flush())
        withExtendedLifetime(fixture.controller) {}
    }

    @Test("Deleting an unresolved result clears its warning and cannot resurrect the notice")
    func deletionClearsOwnWarning() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.fileURL) }
        let entry = try #require(fixture.history.entries.first)
        #expect(fixture.app.lastError != nil)

        fixture.history.remove(entry: entry)

        #expect(!fixture.app.needsPasteRecoveryAttention)
        #expect(fixture.app.lastError == nil)
        #expect(await waitUntil(timeoutMs: 200) { !fixture.display.visible })
        fixture.postResumeNotifications()
        #expect(!fixture.display.visible)
        #expect(await fixture.history.flush())
        withExtendedLifetime(fixture.controller) {}
    }

    private func makeFixture() async throws -> Fixture {
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let paste = AttentionPasteService()
        let app = AppState(audioRecorder: audio,
            pipelineService: MockPipelineService(transcriptionText: "  Exact retained result.\n",
                                                refinementShouldThrow: false, mode: .transcribeOnly),
            overlay: MockOverlay(), pasteService: paste, historyStore: history,
            permissionService: MockPermissionService(), accessibilityAnnouncement: { _ in })
        let workspace = NotificationCenter()
        let lock = NotificationCenter()
        let display = DisplayState()
        let controller = RecoveryNoticeController(appState: app, history: history,
            workspaceNotifications: workspace, lockNotifications: lock, displayOverride: { display.visible = $0 })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && display.visible })
        #expect(app.needsPasteRecoveryAttention)
        return Fixture(app: app, audio: audio, history: history, paste: paste, controller: controller,
                       display: display, workspace: workspace, lock: lock, fileURL: url)
    }

    @MainActor
    private struct Fixture {
        let app: AppState
        let audio: MockAudioRecorder
        let history: HistoryStore
        let paste: AttentionPasteService
        let controller: RecoveryNoticeController
        let display: DisplayState
        let workspace: NotificationCenter
        let lock: NotificationCenter
        let fileURL: URL

        func postResumeNotifications() {
            lock.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
            workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
            workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
            lock.post(name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
            workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
            workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        }
    }

    @MainActor
    private final class DisplayState {
        var visible = false
    }

    @MainActor
    private final class AttentionPasteService: PasteServicing {
        var timing = PasteTiming(commandOutcome: .blocked(.secureInputActive), clipboardDisposition: .unchanged,
                                 commandSentElapsedMs: nil, totalElapsedMs: 0)
        var copyOutcome = ClipboardCopyOutcome.copied
        private(set) var copied: [String] = []
        func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming { timing }
        func copyToClipboardForRecovery(text: String) -> Bool { copyResult(text: text) == .copied }
        func copyResult(text: String) -> ClipboardCopyOutcome {
            copied.append(text)
            return copyOutcome
        }
    }
}
