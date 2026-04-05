@testable import mrml
import Testing
import Foundation

@MainActor
@Suite struct CohereMLXServiceTests {

    @Test func readyTransition() {
        let svc = CohereMLXService()
        svc.handleOutput("READY\n")
        #expect(svc.modelState == .ready)
    }

    @Test func okLineReturnsTranscript() async throws {
        let svc = CohereMLXService()
        svc.handleOutput("READY\n")
        // Prime a pending continuation via a task
        let task = Task { try await svc.transcribe(audioURL: URL(fileURLWithPath: "/tmp/a.wav")) }
        try await Task.sleep(nanoseconds: 1_000_000)  // let transcribe() register continuation
        svc.handleOutput("OK|Hello world\n")
        let result = try await task.value
        #expect(result == "Hello world")
    }

    @Test func errorLineThrows() async {
        let svc = CohereMLXService()
        svc.handleOutput("READY\n")
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
}
