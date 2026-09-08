import Foundation
import Observation

/// Hidden, production-bound paste probe for Tier 2 validation.
@MainActor
@Observable
final class PasteDiagnosticCommand {
    static let shared = PasteDiagnosticCommand()
    static let environmentKey = "MURMELN_PASTE_DIAGNOSTIC_TRIGGER"
    static let fixedText = "Murmeln paste diagnostic"

    private(set) var isRunning = false
    private var suspended = false
    private(set) var resultMessage: String?
    private(set) var lastCaptureID: String?
    private(set) var lastPasteAttemptID: String?

    let isVisible: Bool

    @ObservationIgnored private let pasteService: any PasteServicing
    @ObservationIgnored private let captureIDFactory: @MainActor () -> String
    @ObservationIgnored private let accessibilityAnnouncement: @MainActor (String) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        pasteService: any PasteServicing = PasteService.shared,
        captureIDFactory: @escaping @MainActor () -> String = { UUID().uuidString },
        accessibilityAnnouncement: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.isVisible = environment[Self.environmentKey] == "1"
        self.pasteService = pasteService
        self.captureIDFactory = captureIDFactory
        self.accessibilityAnnouncement = accessibilityAnnouncement
    }

    deinit {
        task?.cancel()
    }

    func start() {
        guard isVisible, !isRunning, !suspended, task == nil else { return }
        task = Task { [weak self] in
            await self?.performRun()
        }
    }

    func run() async {
        start()
        await task?.value
    }

    func suspend() { suspended = true; task?.cancel() }
    func quiesce() async { suspend(); await task?.value }
    func resume() { suspended = false }

    private func performRun() async {
        guard !Task.isCancelled else { task = nil; return }
        isRunning = true
        defer {
            isRunning = false
            task = nil
        }

        let captureID = captureIDFactory()
        lastCaptureID = captureID

        let message: String
        do {
            let timing = try await pasteService.pasteAndRestore(
                text: Self.fixedText,
                captureID: captureID
            )
            lastPasteAttemptID = timing.pasteAttemptID
            message = Self.message(for: timing, captureID: captureID)
        } catch is CancellationError {
            message = "Paste diagnostic cancelled. Capture \(Self.shortID(captureID))."
        } catch {
            message = "Paste diagnostic stopped before a result. Capture \(Self.shortID(captureID))."
        }

        resultMessage = message
        accessibilityAnnouncement(message)
    }

    private static func message(for timing: PasteTiming, captureID: String) -> String {
        let correlation = "Capture \(shortID(captureID)), paste attempt \(shortID(timing.pasteAttemptID))."

        switch timing.commandOutcome {
        case .notAttempted:
            return "Paste diagnostic did not send a command. \(correlation)"
        case .posted:
            if timing.clipboardDisposition == .restoreFailed {
                return "Paste diagnostic command sent, but Murmeln could not restore the previous clipboard. \(correlation)"
            }
            return "Paste diagnostic command sent. Check the target separately. \(correlation)"
        case .blocked(let blocker):
            let recovery: String
            switch blocker {
            case .postEventAccessDenied:
                recovery = "Murmeln does not have paste permission. Select Open Accessibility Settings, then retry."
            case .secureInputActive:
                recovery = "Secure Input blocked paste. Leave the password or secure-entry field, then retry."
            case .keyEventCreationFailed:
                recovery = "Murmeln could not create the paste command. Retry the diagnostic."
            case .clipboardChanged:
                recovery = "The clipboard changed before the diagnostic could post. No command was sent."
            case .clipboardSnapshotUnavailable:
                recovery = "The previous clipboard could not be safely preserved. No command was sent."
            case .cancelled:
                recovery = "The paste diagnostic stopped before the command was sent."
            case .clipboardWriteFailed:
                recovery = "Murmeln could not copy the fixed diagnostic text. Retry the diagnostic."
            }

            let clipboardStatus: String
            switch timing.clipboardDisposition {
            case .transcriptPreserved:
                clipboardStatus = "The fixed diagnostic text is on the clipboard."
            case .externalWritePreserved:
                clipboardStatus = "The clipboard changed, so Murmeln did not overwrite its current state."
            case .restoreFailed:
                clipboardStatus = "Murmeln could not restore the previous clipboard."
            case .restored, .unchanged:
                clipboardStatus = "The fixed diagnostic text is not on the clipboard."
            }
            return "\(recovery) \(clipboardStatus) \(correlation)"
        }
    }

    private static func shortID(_ identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else { return "unavailable" }
        return String(identifier.prefix(8))
    }
}
