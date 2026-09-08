import Foundation
import os.log

actor CaptureDiagnostics {
    struct PersistedCaptureState: Codable, Equatable {
        let schemaVersion: Int
        let sessionID: String
        let captureID: String
        let lastKnownPhase: String
        let lastEvent: String
        let updatedAt: String
        let metadata: [String: String]
    }

    static let shared = CaptureDiagnostics()

    private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "CaptureDiagnostics")
    private let formatter: ISO8601DateFormatter
    private let fileURL: URL
    private let persistedCaptureStateURL: URL
    private let sessionID: String
    private let isEnabled: Bool
    private let maxLogSizeBytes: Int
    private let dependencies: CaptureDiagnosticsDependencies

    init(
        fileURL: URL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("capture-diagnostics.jsonl"),
        persistedCaptureStateURL: URL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("unfinished-capture.json"),
        sessionID: String = UUID().uuidString,
        isEnabled: Bool = AppIdentity.isDevelopmentBuild || ProcessInfo.processInfo.environment["MURMELN_CAPTURE_DIAGNOSTICS"] == "1",
        maxLogSizeBytes: Int = 10 * 1024 * 1024,
        dependencies: CaptureDiagnosticsDependencies = .live
    ) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.formatter = formatter
        self.fileURL = fileURL
        self.persistedCaptureStateURL = persistedCaptureStateURL
        self.sessionID = sessionID
        self.isEnabled = isEnabled
        self.maxLogSizeBytes = maxLogSizeBytes
        self.dependencies = dependencies
    }

    func startSession() {
        guard isEnabled else { return }

        let recoveredState = recoverPersistedCaptureStateIfPresent()
        if let recoveredState {
            record(
                "app.session.recovered_previous_state",
                captureID: recoveredState.captureID,
                metadata: recoveryMetadata(from: recoveredState),
                updatePersistedCaptureState: false
            )
        }

        record(
            "app.session.started",
            metadata: [
                "app_name": AppIdentity.displayName,
                "bundle_identifier": AppIdentity.bundleIdentifier,
                "development_build": String(AppIdentity.isDevelopmentBuild),
                "recovered_previous_state": String(recoveredState != nil)
            ],
            updatePersistedCaptureState: false
        )
    }

    func endSession(reason: String, recordingPhase: String, activeCaptureID: String?) {
        guard isEnabled else { return }

        var metadata: [String: String] = [
            "reason": reason,
            "recording_phase": recordingPhase,
            "has_unfinished_capture_state": String(FileManager.default.fileExists(atPath: persistedCaptureStateURL.path))
        ]

        if let activeCaptureID {
            metadata["active_capture_id"] = activeCaptureID
        }

        record(
            "app.session.ending",
            captureID: activeCaptureID,
            metadata: metadata,
            updatePersistedCaptureState: false
        )
    }

    func mark(_ event: String, captureID: String? = nil, metadata: [String: String] = [:]) {
        guard isEnabled else {
            return
        }

        record(event, captureID: captureID, metadata: metadata)
    }

    /// Always attempts the closed, privacy-allowlisted paste subset, including
    /// in production where unrestricted capture diagnostics remain disabled.
    @discardableResult
    func recordPasteAttempt(_ record: PasteOperationalRecord) async -> Bool {
        guard let data = dependencies.encodeOperationalRecord(record) else {
            await reportOperationalPersistenceFailure(
                pasteAttemptID: record.pasteAttemptID,
                blocker: record.blocker
            )
            return false
        }

        guard let line = String(data: data, encoding: .utf8) else {
            await reportOperationalPersistenceFailure(
                pasteAttemptID: record.pasteAttemptID,
                blocker: record.blocker
            )
            return false
        }

        guard dependencies.rotateLogIfNeeded(fileURL, maxLogSizeBytes, data.count + 1),
              dependencies.appendLine(data, fileURL) else {
            await reportOperationalPersistenceFailure(
                pasteAttemptID: record.pasteAttemptID,
                blocker: record.blocker
            )
            return false
        }

        if record.level == "warning" {
            logger.warning("\(line, privacy: .public)")
        } else {
            logger.info("\(line, privacy: .public)")
        }
        return true
    }

    private func reportOperationalPersistenceFailure(
        pasteAttemptID: String,
        blocker: PasteBlocker?
    ) async {
        await dependencies.reportOperationalPersistenceFailure(
            CaptureDiagnosticsDependencies.OperationalPersistenceFailure(
                pasteAttemptID: pasteAttemptID,
                blocker: blocker
            )
        )
    }

    private func record(
        _ event: String,
        captureID: String? = nil,
        metadata: [String: String] = [:],
        updatePersistedCaptureState: Bool = true
    ) {
        guard isEnabled else { return }

        var payload: [String: Any] = [
            "event": event,
            "session_id": sessionID,
            "timestamp": formatter.string(from: Date()),
            "uptime_ns": DispatchTime.now().uptimeNanoseconds
        ]

        if let captureID {
            payload["capture_id"] = captureID
        }

        for (key, value) in metadata {
            payload[key] = value
        }

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else {
            logger.error("capture diagnostics serialization failed for event \(event, privacy: .public)")
            return
        }

        logger.info("\(line, privacy: .public)")
        appendLine(line)

        if updatePersistedCaptureState {
            updatePersistedCaptureStateIfNeeded(for: event, captureID: captureID, metadata: metadata)
        }
    }

    private func appendLine(_ line: String) {
        let content = line + "\n"
        guard let data = content.data(using: .utf8) else { return }

        rotateLogIfNeeded()

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.error("capture diagnostics append failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// M9: rotate the diagnostics log at `maxLogSizeBytes` — one previous
    /// generation is kept as `<name>.1`, so disk usage is bounded at ~2x max.
    private func rotateLogIfNeeded() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size]) as? Int,
              size >= maxLogSizeBytes else {
            return
        }
        let rotatedURL = fileURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotatedURL)
        do {
            try FileManager.default.moveItem(at: fileURL, to: rotatedURL)
        } catch {
            logger.error("capture diagnostics rotation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatePersistedCaptureStateIfNeeded(
        for event: String,
        captureID: String?,
        metadata: [String: String]
    ) {
        guard let captureID else { return }

        if event == "app.capture.complete" {
            clearPersistedCaptureState(for: captureID)
            return
        }

        guard let phase = persistedCapturePhase(for: event) else {
            return
        }

        let state = PersistedCaptureState(
            schemaVersion: 1,
            sessionID: sessionID,
            captureID: captureID,
            lastKnownPhase: phase,
            lastEvent: event,
            updatedAt: formatter.string(from: Date()),
            metadata: metadata
        )

        writePersistedCaptureState(state)
    }

    private func persistedCapturePhase(for event: String) -> String? {
        switch event {
        case "app.processing.started":
            return "processing_started"
        case "app.backend_load.started":
            return "backend_load_started"
        case "app.backend_load.completed":
            return "backend_load_completed"
        case "app.backend_load.skipped":
            return "backend_load_skipped"
        case "app.backend_transcription.started":
            return "backend_transcription_started"
        case "app.backend_transcription.completed":
            return "backend_transcription_completed"
        case "app.backend_transcription.failed":
            return "backend_transcription_failed"
        case "paste.requested":
            return "paste_requested"
        case "paste.skipped_empty":
            return "paste_skipped_empty"
        case "paste.attempt_finished":
            return "paste_attempt_finished"
        case "app.processing.failed":
            return "processing_failed"
        default:
            return nil
        }
    }

    private func writePersistedCaptureState(_ state: PersistedCaptureState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: persistedCaptureStateURL, options: [.atomic])
        } catch {
            logger.error("capture diagnostics state write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoverPersistedCaptureStateIfPresent() -> PersistedCaptureState? {
        guard FileManager.default.fileExists(atPath: persistedCaptureStateURL.path) else {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: persistedCaptureStateURL)
        }

        do {
            let data = try Data(contentsOf: persistedCaptureStateURL)
            return try JSONDecoder().decode(PersistedCaptureState.self, from: data)
        } catch {
            logger.error("capture diagnostics state recovery failed: \(error.localizedDescription, privacy: .public)")
            return PersistedCaptureState(
                schemaVersion: 1,
                sessionID: "unknown",
                captureID: "unknown",
                lastKnownPhase: "unreadable_state",
                lastEvent: "unreadable_state",
                updatedAt: formatter.string(from: Date()),
                metadata: ["recovery_error": error.localizedDescription]
            )
        }
    }

    private func clearPersistedCaptureState(for captureID: String) {
        guard FileManager.default.fileExists(atPath: persistedCaptureStateURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: persistedCaptureStateURL)
            let state = try JSONDecoder().decode(PersistedCaptureState.self, from: data)
            guard state.captureID == captureID else { return }
            try FileManager.default.removeItem(at: persistedCaptureStateURL)
        } catch {
            logger.error("capture diagnostics state clear failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func recoveryMetadata(from state: PersistedCaptureState) -> [String: String] {
        var metadata: [String: String] = [
            "previous_session_id": state.sessionID,
            "previous_capture_id": state.captureID,
            "last_known_phase": state.lastKnownPhase,
            "last_event": state.lastEvent,
            "stale_updated_at": state.updatedAt
        ]

        if let updatedAt = formatter.date(from: state.updatedAt) {
            let staleAgeMs = max(0, Int(Date().timeIntervalSince(updatedAt) * 1000))
            metadata["stale_age_ms"] = String(staleAgeMs)
        }

        for (key, value) in state.metadata {
            metadata["previous_\(key)"] = value
        }

        return metadata
    }
}
