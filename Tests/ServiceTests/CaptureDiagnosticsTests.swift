import Testing
import Foundation
@testable import mrml

@Suite("CaptureDiagnostics Tests")
struct CaptureDiagnosticsTests {
    @Test("Session recovery logs the previous unfinished capture state")
    func sessionRecoveryLogsPreviousUnfinishedCaptureState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let stateURL = directory.appendingPathComponent("unfinished-capture.json")

        let firstSession = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: stateURL,
            sessionID: "session-old",
            isEnabled: true
        )
        await firstSession.mark(
            "app.processing.started",
            captureID: "capture-123",
            metadata: [
                "pipeline_mode": "transcribe_only",
                "audio_duration_ms": "800"
            ]
        )

        #expect(FileManager.default.fileExists(atPath: stateURL.path))

        let secondSession = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: stateURL,
            sessionID: "session-new",
            isEnabled: true
        )
        await secondSession.startSession()

        let events = try parseEvents(at: diagnosticsURL)
        let recoveryEvent = try #require(events.first(where: { $0["event"] as? String == "app.session.recovered_previous_state" }))
        let startedEvent = try #require(events.first(where: { $0["event"] as? String == "app.session.started" }))

        #expect(recoveryEvent["session_id"] as? String == "session-new")
        #expect(recoveryEvent["capture_id"] as? String == "capture-123")
        #expect(recoveryEvent["previous_session_id"] as? String == "session-old")
        #expect(recoveryEvent["last_known_phase"] as? String == "processing_started")
        #expect(recoveryEvent["previous_audio_duration_ms"] as? String == "800")

        #expect(startedEvent["session_id"] as? String == "session-new")
        #expect(startedEvent["recovered_previous_state"] as? String == "true")
        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
    }

    @Test("Capture completion clears the unfinished capture breadcrumb")
    func captureCompletionClearsUnfinishedCaptureBreadcrumb() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let stateURL = directory.appendingPathComponent("unfinished-capture.json")

        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: stateURL,
            sessionID: "session-1",
            isEnabled: true
        )

        await diagnostics.mark("app.processing.started", captureID: "capture-123")
        #expect(FileManager.default.fileExists(atPath: stateURL.path))

        await diagnostics.mark(
            "app.capture.complete",
            captureID: "capture-123",
            metadata: [
                "outcome": "completed",
                "reason": "paste_completed"
            ]
        )

        #expect(FileManager.default.fileExists(atPath: stateURL.path) == false)
    }

    private func parseEvents(at url: URL) throws -> [[String: Any]] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return try contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                let data = Data(line.utf8)
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                return try #require(jsonObject as? [String: Any])
            }
    }
    @Test("Diagnostics log rotates at the size cap (M9)")
    func diagnosticsLogRotatesAtSizeCap() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-rotation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let rotatedURL = diagnosticsURL.appendingPathExtension("1")
        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: directory.appendingPathComponent("unfinished-capture.json"),
            sessionID: "session-rotation",
            isEnabled: true,
            maxLogSizeBytes: 512
        )

        for i in 0..<40 {
            await diagnostics.mark("rotation.test.event", metadata: ["i": String(i), "padding": String(repeating: "x", count: 64)])
        }

        #expect(FileManager.default.fileExists(atPath: rotatedURL.path), "rotated generation should exist")
        let mainSize = ((try? FileManager.default.attributesOfItem(atPath: diagnosticsURL.path)[.size]) as? Int) ?? .max
        #expect(mainSize < 1_024, "active log should have been reset by rotation")
    }
}
