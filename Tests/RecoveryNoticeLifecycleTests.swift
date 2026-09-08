import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Recovery notice lifecycle")
struct RecoveryNoticeLifecycleTests {
    @Test("Wake, lock, session switch, dismissal and deletion preserve notice lifecycle")
    func visibilityAndActions() async throws {
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let paste = MockPasteService(pasteTiming: PasteTiming(commandOutcome: .blocked(.secureInputActive),
            clipboardDisposition: .unchanged, commandSentElapsedMs: nil, totalElapsedMs: 0), recoveryCopyResults: [true])
        let app = AppState(audioRecorder: audio,
            pipelineService: MockPipelineService(transcriptionText: "private result", refinementShouldThrow: true),
            overlay: MockOverlay(), pasteService: paste, historyStore: history, permissionService: MockPermissionService(),
            accessibilityAnnouncement: { _ in })
        let workspace = NotificationCenter()
        let lock = NotificationCenter()
        var visible = false
        let controller = RecoveryNoticeController(appState: app, history: history, workspaceNotifications: workspace,
            lockNotifications: lock, displayOverride: { visible = $0 })
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { visible })
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        #expect(!visible)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(visible)
        lock.post(name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!visible)
        lock.post(name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        #expect(visible)
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(!visible)
        app.copyFailedPasteAgain() // The menu action remains usable with the panel hidden.
        #expect(paste.recoveryCopyTexts == ["private result"])
        app.dismissPasteRecovery()
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        #expect(!visible)
        #expect(await history.flush())
        #expect(!visible && app.hasPasteRecovery)
        history.clear()
        #expect(!app.hasPasteRecovery)
        #expect(await history.flush())
        withExtendedLifetime(controller) {}
    }

    @Test("Recovery panel cannot take keyboard or main-window focus")
    func panelNeverBecomesKey() {
        let panel = RecoveryNoticePanel(contentRect: .zero, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)
        #expect(!panel.canBecomeKey && !panel.canBecomeMain)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }
}
