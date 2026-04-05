@testable import mrml
import Testing
import Foundation

@MainActor
@Suite struct CohereMLXServiceTests {

    /// Creates a CohereMLXService in .ready state with a dummy stdinPipe,
    /// suitable for testing transcribe() without a real Python process.
    private func makeReadyService() -> CohereMLXService {
        let svc = CohereMLXService()
        svc.handleOutput("READY\n")
        svc.installTestStdinPipe()
        return svc
    }

    @Test func readyTransition() {
        let svc = CohereMLXService()
        svc.handleOutput("READY\n")
        #expect(svc.modelState == .ready)
    }

    @Test func okLineReturnsTranscript() async throws {
        let svc = makeReadyService()
        // Prime a pending continuation via a task
        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)  // let transcribe() register continuation
        svc.handleOutput("OK|Hello world\n")
        let result = try await task.value
        #expect(result == "Hello world")
    }

    @Test func errorLineThrows() async {
        let svc = makeReadyService()
        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try? await Task.sleep(nanoseconds: 1_000_000)
        svc.handleOutput("ERROR|inference failed\n")
        await #expect(throws: CohereMLXError.self) { try await task.value }
    }

    @Test func transcribeThrowsWhenNotReady() async {
        let svc = CohereMLXService()
        // modelState is .notLoaded — should throw immediately
        await #expect(throws: CohereMLXError.bridgeNotReady) {
            try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav"))
        }
    }

    @Test func loadErrorSetsFailedState() {
        let svc = CohereMLXService()
        svc.handleOutput("LOAD_ERROR|No module named mlx_audio\n")
        if case .failed(let msg) = svc.modelState {
            #expect(msg == "No module named mlx_audio")
        } else {
            Issue.record("Expected .failed state")
        }
    }

    @Test func partialLineBuffer() {
        let svc = CohereMLXService()
        svc.handleOutput("REA")
        #expect(svc.modelState == .notLoaded)  // incomplete line not processed
        svc.handleOutput("DY\n")
        #expect(svc.modelState == .ready)
    }

    // MARK: - P0/P1 regression tests

    // P0-1: Second concurrent transcribe() call should throw immediately
    @Test func testConcurrentTranscribeThrows() async throws {
        let svc = makeReadyService()

        // First call — registers a pending continuation
        let first = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)

        // Second call while first is in-flight should throw .transcriptionInFlight
        await #expect(throws: CohereMLXError.transcriptionInFlight) {
            try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/b.wav"))
        }

        // Clean up first task
        svc.handleOutput("OK|done\n")
        _ = try await first.value
    }

    // P0-2: Multi-line transcripts should be preserved via \\n escaping
    @Test func testMultiLineTranscript() async throws {
        let svc = makeReadyService()

        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)

        // Bridge sends escaped newlines: OK|Hello\\nworld\\ntest
        svc.handleOutput("OK|Hello\\nworld\\ntest\n")
        let result = try await task.value
        #expect(result == "Hello\nworld\ntest")
    }

    // P0-3: stopBridge() during transcription should resume continuation with error
    @Test func testStopBridgeDuringTranscription() async throws {
        let svc = makeReadyService()

        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)

        svc.stopBridge()

        await #expect(throws: CohereMLXError.bridgeStopped) {
            try await task.value
        }
    }

    // P0-3: Process termination during transcription should resume continuation with error
    @Test func testProcessTerminationDuringTranscription() async throws {
        let svc = makeReadyService()

        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)

        // Simulate the terminationHandler's logic: grab and nil continuation, then resume with bridgeCrashed
        let cont = svc.pendingContinuation_testAccess
        svc.clearPendingContinuation_testAccess()
        cont?.resume(throwing: CohereMLXError.bridgeCrashed)

        await #expect(throws: CohereMLXError.bridgeCrashed) {
            try await task.value
        }
    }

    // P0-3: After stopBridge(), state is clean
    @Test func testStopBridgeCleansUpState() {
        let svc = makeReadyService()
        #expect(svc.modelState == .ready)

        svc.stopBridge()

        #expect(svc.modelState == .notLoaded)
        #expect(svc.pendingContinuation_testAccess == nil)
    }
}
