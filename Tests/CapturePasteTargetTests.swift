import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Capture paste target lifetime", .serialized)
struct CapturePasteTargetTests {
    @Test("Failed Notion capture remains refused after focus changes and preserves exact recovery")
    func notionRefusalSurvivesTargetChangeAndRecoversExactText() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("unrelated clipboard", forType: .string)
        let generation = board.changeCount
        let previousBytes = try #require(board.data(forType: .string))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let history = HistoryStore(fileURL: file, legacyDefaults: defaults)
        let exactText = "Exact Notion result.\nSecond line: Grüße."
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        var snapshots = 0
        var writes = 0
        var posts = 0
        var records: [PasteOperationalRecord] = []
        let paste: any PasteServicing = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, captureClipboard: { board in snapshots += 1; return ClipboardSnapshot.capture(from: board) },
            setPasteboardString: { text, board in writes += 1; return board.setString(text, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { [] },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 },
            recordPasteAttempt: { records.append($0) }))
        let current = TargetSelection(nil)
        current.bundleIdentifier = "notion.id"
        let laterTarget = Target()
        var sampledProof: (any PasteTargetChecking)?
        var samples = 0
        let app = AppState(audioRecorder: audio,
            pipelineService: MockPipelineService(transcriptionText: exactText, refinementShouldThrow: false, mode: .transcribeOnly),
            overlay: MockOverlay(), pasteService: paste, historyStore: history, permissionService: MockPermissionService(),
            capturePasteTarget: {
                samples += 1
                sampledProof = CapturedPasteTarget.select(bundleIdentifier: current.bundleIdentifier,
                    capturedTarget: current.target)
                return sampledProof
            }, accessibilityAnnouncement: { _ in })
        let id = try #require(app.prepareCaptureIDForHotkeyPressIfPossible())
        current.bundleIdentifier = "com.apple.TextEdit"
        current.target = laterTarget
        app.warmUpEngine()
        #expect(app.beginRecording(expectedCaptureID: id))
        #expect(await waitUntil { app.recordingPhase == .recording && audio.beginCaptureCalls == 1 })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && records.count == 1 })

        #expect(samples == 1 && sampledProof != nil && sampledProof?.isStillValid() == false)
        #expect(snapshots == 0 && writes == 0 && posts == 0)
        #expect(board.changeCount == generation && board.data(forType: .string) == previousBytes)
        let record = try #require(records.first)
        #expect(record.captureID == id && record.blocker == .cancelled && record.commandOutcome == "blocked")
        #expect(record.postAccessState == true && record.secureInputState == false)
        #expect(history.entries.count == 1)
        let entry = try #require(history.entries.first)
        #expect(entry.captureID == id && entry.original == exactText && entry.displayText == exactText)
        #expect(app.recoveryEntryID == entry.id && history.protectedRecoveryID == entry.id)
        #expect(app.hasPasteRecovery && app.needsPasteRecoveryAttention)
        #expect(app.recoveryMessage == "Automatic paste stopped before the command was sent. Your text is available to copy.")
        #expect(await history.flush())
        let reloaded = HistoryStore(fileURL: file, legacyDefaults: defaults)
        #expect(reloaded.entries.first?.id == entry.id && reloaded.entries.first?.displayText == exactText)

        app.copyFailedPasteAgain()
        #expect(board.string(forType: .string) == exactText)
        #expect(posts == 0 && records.count == 1)
        #expect(app.recoveryEntryID == entry.id && history.entry(id: entry.id)?.displayText == exactText)
        #expect(await app.quiesceForTermination())
    }

    @Test("A Fn press while busy cannot start later with a different field's proof")
    func busyGestureCannotSampleTargetAfterBecomingIdle() async {
        var samples = 0
        let audio = MockAudioRecorder()
        let app = makeApp(audio: audio, paste: PasteSpy()) {
            samples += 1
            return Target()
        }
        let originalID = app.prepareCaptureIDForHotkeyPressIfPossible()
        app.warmUpEngine()
        let deniedID = app.prepareCaptureIDForHotkeyPressIfPossible()
        #expect(deniedID == nil)
        app.cancelWarmUp()
        #expect(await waitUntil { app.recordingPhase == .idle && app.diagnosticsActiveCaptureID == nil })

        // The old timer can carry either a rejected nil or its previous ID.
        #expect(!app.beginRecording(expectedCaptureID: deniedID))
        #expect(!app.beginRecording(expectedCaptureID: originalID))
        #expect(app.recordingPhase == .idle)
        #expect(app.diagnosticsActiveCaptureID == nil)
        #expect(samples == 1)
        #expect(await app.quiesceForTermination())
    }

    @Test("History admission failure cannot become a late recording after space is freed")
    func rejectedHistoryGestureCannotRestartAtThreshold() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let history = HistoryStore(fileURL: file, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        history.mutationsSuspended = true
        var samples = 0
        let app = AppState(audioRecorder: MockAudioRecorder(), overlay: MockOverlay(),
            pasteService: PasteSpy(), historyStore: history, permissionService: MockPermissionService(),
            capturePasteTarget: { samples += 1; return Target() }, accessibilityAnnouncement: { _ in })
        let rejectedID = app.prepareCaptureIDForHotkeyPressIfPossible()
        app.warmUpEngine()
        history.mutationsSuspended = false

        #expect(!app.beginRecording(expectedCaptureID: rejectedID))
        #expect(app.recordingPhase == .idle)
        #expect(samples == 1)
        #expect(await app.quiesceForTermination())
    }

    @Test("A gesture while termination is suspended cannot allocate a future paste target")
    func suspendedTerminationRejectsTargetAllocation() async {
        var samples = 0
        let app = makeApp(audio: MockAudioRecorder(), paste: PasteSpy()) {
            samples += 1
            return Target()
        }
        #expect(await app.quiesceForTermination())

        let rejectedID = app.prepareCaptureIDForHotkeyPressIfPossible()
        app.warmUpEngine()

        #expect(rejectedID == nil)
        #expect(app.diagnosticsActiveCaptureID == nil)
        #expect(samples == 0)
        app.resumeAfterCancelledTermination()
        #expect(app.prepareCaptureIDForHotkeyPressIfPossible() != nil)
        #expect(samples == 1)
    }

    @Test("Rejected History admission drops the gesture's target before another capture")
    func rejectedAdmissionDropsProof() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let history = HistoryStore(fileURL: file, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        history.mutationsSuspended = true
        var samples = 0
        let app = AppState(audioRecorder: MockAudioRecorder(), overlay: MockOverlay(),
                           pasteService: PasteSpy(), historyStore: history,
                           capturePasteTarget: { samples += 1; return Target() }, accessibilityAnnouncement: { _ in })
        let first = app.prepareCaptureIDForHotkeyPressIfPossible()
        app.warmUpEngine()
        #expect(app.recordingPhase == .idle)
        #expect(app.diagnosticsActiveCaptureID == nil)
        history.mutationsSuspended = false
        let next = app.prepareCaptureIDForHotkeyPressIfPossible()
        #expect(next != first)
        #expect(samples == 2)
    }

    @Test("Capture retains the original target before warm-up and delivers it once")
    func retainsOriginalTarget() async throws {
        let first = Target()
        let second = Target()
        let current = TargetSelection(first)
        var captures = 0
        let paste = PasteSpy()
        let audio = MockAudioRecorder()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        let overlay = MockOverlay()
        let app = makeApp(audio: audio, paste: paste, overlay: overlay) {
            #expect(overlay.showCalls == 0)
            captures += 1
            return current.target
        }
        let id = app.prepareCaptureIDForHotkeyPressIfPossible()
        #expect(captures == 1)
        #expect(app.prepareCaptureIDForHotkeyPressIfPossible() == id)
        current.target = second
        app.warmUpEngine()
        #expect(app.beginRecording(expectedCaptureID: id))
        #expect(await waitUntil { app.recordingPhase == .recording && audio.beginCaptureCalls == 1 })
        // Fn-to-lock admits the same recording without starting audio again.
        #expect(app.beginRecording(expectedCaptureID: id))
        #expect(audio.beginCaptureCalls == 1)
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && paste.calls.count == 1 })
        #expect(captures == 1)
        #expect(paste.calls.first?.target === first)
        #expect(paste.calls.first?.captureID == id)
        #expect(paste.calls.first?.text == "Exact capture target result.")
        #expect(paste.legacyCalls == 0)
    }

    @Test("Cancelled capture cannot reuse its proof for the next unsupported target")
    func cancelledCaptureDoesNotLeakProof() async throws {
        let original = Target()
        let current = TargetSelection(original)
        var captures = 0
        let audio = MockAudioRecorder()
        let paste = PasteSpy()
        let app = makeApp(audio: audio, paste: paste) { captures += 1; return current.target }
        let cancelledID = app.prepareCaptureIDForHotkeyPressIfPossible()
        app.warmUpEngine()
        app.cancelWarmUp()
        #expect(await waitUntil { app.recordingPhase == .idle && app.diagnosticsActiveCaptureID == nil })
        current.target = nil
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && paste.calls.count == 1 })
        #expect(captures == 2)
        #expect(paste.calls.first?.target == nil)
        #expect(paste.calls.first?.captureID != cancelledID)
        #expect(paste.legacyCalls == 0)
    }

    @Test("Completed captures sample a new proof and termination releases a pending proof")
    func completionAndTerminationClearProof() async throws {
        let paste = PasteSpy()
        let audio = MockAudioRecorder()
        var sampled = 0
        weak var released: Target?
        let app = makeApp(audio: audio, paste: paste) {
            let target = Target()
            released = target
            sampled += 1
            return target
        }
        _ = app.prepareCaptureIDForHotkeyPressIfPossible()
        #expect(released != nil)
        #expect(await app.quiesceForTermination())
        #expect(released == nil)
        app.resumeAfterCancelledTermination()
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && paste.calls.count == 1 })
        let firstDelivered = paste.calls.first?.target
        audio.recordingURL = try AppStateTestFixtures.makeAudibleWAV()
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        app.stopAndProcess()
        #expect(await waitUntil { app.recordingPhase == .idle && paste.calls.count == 2 })
        #expect(sampled == 3)
        #expect(paste.calls.last?.target !== firstDelivered)
    }

    private func makeApp(audio: MockAudioRecorder, paste: PasteSpy, overlay: MockOverlay = MockOverlay(),
                         capture: @escaping @MainActor () -> (any PasteTargetChecking)?) -> AppState {
        AppState(audioRecorder: audio,
                 pipelineService: MockPipelineService(transcriptionText: "Exact capture target result.", refinementShouldThrow: false, mode: .transcribeOnly),
                 overlay: overlay, pasteService: paste, historyStore: MockHistoryStore(),
                 permissionService: MockPermissionService(), capturePasteTarget: capture,
                 accessibilityAnnouncement: { _ in })
    }

    @MainActor private final class TargetSelection {
        var target: Target?
        var bundleIdentifier: String?
        init(_ target: Target?) { self.target = target }
    }

    @MainActor private final class Target: PasteTargetChecking {
        func isStillValid() -> Bool { true }
    }

    @MainActor private final class PasteSpy: PasteServicing {
        struct Call { let text: String; let captureID: String?; let target: (any PasteTargetChecking)? }
        var calls: [Call] = []
        var legacyCalls = 0
        private var timing: PasteTiming { PasteTiming(commandOutcome: .posted, clipboardDisposition: .restored, commandSentElapsedMs: 0, totalElapsedMs: 0) }
        func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming {
            legacyCalls += 1
            calls.append(Call(text: text, captureID: captureID, target: nil))
            return timing
        }
        func pasteAndRestore(text: String, captureID: String?, target: (any PasteTargetChecking)?) async throws -> PasteTiming {
            calls.append(Call(text: text, captureID: captureID, target: target))
            return timing
        }
        func copyToClipboardForRecovery(text: String) -> Bool { false }
    }
}
