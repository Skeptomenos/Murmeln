import Foundation
import Testing
@testable import mrml

private actor SuspendedCaptureAudio: AudioCapturing {
    var stopCount = 0
    var preparing = false
    private var readingLevels = false
    private var stops: [CheckedContinuation<URL?, Never>] = []
    private var stopsReleased = false
    private var prepare: CheckedContinuation<AsyncStream<Float>, Never>?
    func prepareEngine(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float> {
        preparing = true
        return await withCheckedContinuation { prepare = $0 }
    }
    func beginCapture(captureID: String?) async throws {}
    func cancelWarmUp() async {}
    func startRecording(highQuality: Bool, captureID: String?) async throws -> AsyncStream<Float> {
        AsyncStream(unfolding: { await self.markReadingLevels(); return nil })
    }
    private func markReadingLevels() { readingLevels = true }
    func waitForRecordingReady() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !readingLevels && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return readingLevels
    }
    func stopRecording(captureID: String?) async -> URL? {
        stopCount += 1
        guard !stopsReleased else { return nil }
        return await withCheckedContinuation { stops.append($0) }
    }
    func release() {
        stopsReleased = true
        for stop in stops { stop.resume(returning: nil) }
        stops.removeAll()
        prepare?.resume(returning: AsyncStream { $0.finish() })
        prepare = nil
    }
    func waitForStop() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while stopCount == 0 && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return stopCount > 0
    }
    func waitForPreparation() async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !preparing && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return preparing
    }
}

@MainActor
@Suite("Capture quiescence")
struct CaptureQuiescenceTests {
    private func app(_ audio: SuspendedCaptureAudio) throws -> AppState {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        return AppState(audioRecorder: audio,
            pipelineService: MockPipelineService(transcriptionText: "unused", refinementShouldThrow: false),
            overlay: MockOverlay(), pasteService: MockPasteService(), historyStore: history,
            permissionService: MockPermissionService(), capturePasteTarget: { nil },
            accessibilityAnnouncement: { _ in })
    }

    @Test("A second stop cannot start a second audio-finalization task")
    func duplicateStopIsIgnored() async throws {
        let audio = SuspendedCaptureAudio()
        let app = try app(audio)
        app.startRecording()
        #expect(await waitUntil { app.recordingPhase == .recording })
        // .recording precedes the start await. Level consumption proves that
        // startup and its separate cancellation-cleanup guard have completed.
        #expect(await audio.waitForRecordingReady())
        app.stopAndProcess()
        #expect(await audio.waitForStop())
        app.stopAndProcess()
        await audio.release()
        _ = await app.quiesceForTermination()
        // Join every finalization task before asserting; task yields do not
        // guarantee actor entry, and must not hide a late duplicate stop.
        #expect(await audio.stopCount == 1)
    }

    @Test("Quit joins preparation even after warm-up cancellation discarded its old handle")
    func cancelledPreparationRemainsOwned() async throws {
        let audio = SuspendedCaptureAudio()
        let app = try app(audio)
        app.warmUpEngine()
        #expect(await audio.waitForPreparation())
        app.cancelWarmUp()
        var finished = false
        let quit = Task { _ = await app.quiesceForTermination(); finished = true }
        for _ in 0..<100 { await Task.yield() }
        #expect(!finished)
        await audio.release()
        await quit.value
        #expect(app.recordingPhase == .idle)
    }
}
