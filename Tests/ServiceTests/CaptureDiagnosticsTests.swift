import Testing
import Foundation
@testable import mrml

@Suite("CaptureDiagnostics Tests")
struct CaptureDiagnosticsTests {
    @Test("Production mode retains paste-attempt evidence")
    func productionModeRetainsPasteAttemptEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-production-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: directory.appendingPathComponent("unfinished-capture.json"),
            sessionID: "production-session",
            isEnabled: false
        )

        await diagnostics.mark("app.processing.started", captureID: "must-stay-disabled")
        #expect(!FileManager.default.fileExists(atPath: diagnosticsURL.path))

        let persisted = await diagnostics.recordPasteAttempt(try makeRecord(
            attemptID: "attempt-production",
            commandOutcome: .blocked(.postEventAccessDenied),
            postAccessState: false,
            secureInputState: nil
        ))

        #expect(persisted)
        let events = try parseEvents(at: diagnosticsURL)
        #expect(events.count == 1)
        #expect(Set(events[0].keys) == [
            "schema_version", "event", "level", "timestamp", "app_version", "app_build",
            "capture_id", "paste_attempt_id", "command_outcome", "clipboard_disposition",
            "blocker", "post_access_state", "secure_input_state", "elapsed_ms",
            "app_code_hash", "decision_stage", "decision_reason", "target_policy", "target_invalidation",
            "modifier_flags_before", "modifier_flags_at_decision",
        ])
        #expect(events[0]["event"] as? String == "paste_attempt")
        #expect(events[0]["paste_attempt_id"] as? String == "attempt-production")
        #expect(events[0]["blocker"] as? String == "post_event_access_denied")
        #expect(events[0]["post_access_state"] as? Bool == false)
    }

    @Test("Operational serialization, rotation, and append failures are contained", arguments: [
        "serialization", "rotation", "disk_full", "permission_denied",
    ])
    func operationalPersistenceFailuresAreContained(failure: String) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let failureRecorder = OperationalFailureRecorder()
        let reportFailure: @Sendable (CaptureDiagnosticsDependencies.OperationalPersistenceFailure) async -> Void = {
            await failureRecorder.record($0)
        }
        let dependencies: CaptureDiagnosticsDependencies
        switch failure {
        case "serialization":
            dependencies = CaptureDiagnosticsDependencies(
                encodeOperationalRecord: { _ in nil },
                reportOperationalPersistenceFailure: reportFailure
            )
        case "rotation":
            dependencies = CaptureDiagnosticsDependencies(
                rotateLogIfNeeded: { _, _, _ in false },
                reportOperationalPersistenceFailure: reportFailure
            )
        default:
            dependencies = CaptureDiagnosticsDependencies(
                appendLine: { _, _ in false },
                reportOperationalPersistenceFailure: reportFailure
            )
        }
        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: directory.appendingPathComponent("unfinished-capture.json"),
            sessionID: "failure-session",
            isEnabled: false,
            dependencies: dependencies
        )

        let expectedBlocker: PasteBlocker? = failure == "serialization" ? .secureInputActive : nil
        let commandOutcome: PasteCommandOutcome = expectedBlocker.map { .blocked($0) } ?? .posted
        let persisted = await diagnostics.recordPasteAttempt(try makeRecord(
            attemptID: "attempt-\(failure)",
            commandOutcome: commandOutcome,
            postAccessState: true,
            secureInputState: expectedBlocker == nil ? false : true
        ))

        #expect(!persisted)
        #expect(!FileManager.default.fileExists(atPath: diagnosticsURL.path))
        let reported = await failureRecorder.snapshot()
        #expect(reported.count == 1)
        let event = try #require(reported.first)
        #expect(event.event == "paste_diagnostics_persistence_failed")
        #expect(event.level == "warning")
        #expect(event.pasteAttemptID == "attempt-\(failure)")
        #expect(event.blocker == expectedBlocker)
        #expect(Set(Mirror(reflecting: event).children.compactMap(\.label)) == [
            "event", "level", "pasteAttemptID", "blocker",
        ])
    }

    @Test("Operational rotation retains chronological order and bounds both generations")
    func operationalRotationRetainsOrderAndBoundsStorage() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-diagnostics-operational-rotation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let rotatedURL = diagnosticsURL.appendingPathExtension("1")
        let first = try makeRecord(attemptID: "attempt-00000001")
        let second = try makeRecord(attemptID: "attempt-00000002")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let maximumLineSize = max(
            try encoder.encode(first).count + 1,
            try encoder.encode(second).count + 1
        )
        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: directory.appendingPathComponent("unfinished-capture.json"),
            sessionID: "rotation-session",
            isEnabled: false,
            maxLogSizeBytes: maximumLineSize
        )

        #expect(await diagnostics.recordPasteAttempt(first))
        #expect(await diagnostics.recordPasteAttempt(second))

        let retained = try parseEvents(at: rotatedURL) + parseEvents(at: diagnosticsURL)
        #expect(retained.compactMap { $0["paste_attempt_id"] as? String } == [
            "attempt-00000001", "attempt-00000002",
        ])
        let rotatedSize = try #require((try FileManager.default.attributesOfItem(atPath: rotatedURL.path)[.size]) as? Int)
        let activeSize = try #require((try FileManager.default.attributesOfItem(atPath: diagnosticsURL.path)[.size]) as? Int)
        #expect(rotatedSize <= maximumLineSize)
        #expect(activeSize <= maximumLineSize)
        #expect(rotatedSize + activeSize <= maximumLineSize * 2)
    }

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
                "reason": "paste_command_posted"
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

    private func makeRecord(
        attemptID: String,
        commandOutcome: PasteCommandOutcome = .posted,
        postAccessState: Bool? = true,
        secureInputState: Bool? = false
    ) throws -> PasteOperationalRecord {
        let timing = PasteTiming(
            commandOutcome: commandOutcome,
            clipboardDisposition: commandOutcome == .posted ? .restored : .transcriptPreserved,
            commandSentElapsedMs: commandOutcome == .posted ? 1 : nil,
            totalElapsedMs: 2,
            pasteAttemptID: attemptID,
            postAccessState: postAccessState,
            secureInputState: secureInputState
        )
        return try #require(PasteOperationalRecord(
            timestamp: "2026-08-15T12:00:00.000Z",
            appVersion: "2.6.1",
            appBuild: "626",
            captureID: "capture-operational",
            timing: timing
        ))
    }

    private actor OperationalFailureRecorder {
        private var failures: [CaptureDiagnosticsDependencies.OperationalPersistenceFailure] = []

        func record(_ failure: CaptureDiagnosticsDependencies.OperationalPersistenceFailure) {
            failures.append(failure)
        }

        func snapshot() -> [CaptureDiagnosticsDependencies.OperationalPersistenceFailure] {
            failures
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
