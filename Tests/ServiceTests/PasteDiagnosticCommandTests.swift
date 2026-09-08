import Testing
@testable import mrml

@Suite("Paste Diagnostic Command Tests")
@MainActor
struct PasteDiagnosticCommandTests {
    @Test("Preservation diagnostic keeps correlation and does not promise retained text", arguments: [PasteBlocker.clipboardChanged, .clipboardSnapshotUnavailable])
    func preservationDiagnosticDoesNotPromiseCopy(blocker: PasteBlocker) async {
        let command = PasteDiagnosticCommand(environment: [PasteDiagnosticCommand.environmentKey: "1"],
            pasteService: Recorder(timing: PasteTiming(commandOutcome: .blocked(blocker), clipboardDisposition: .unchanged,
                commandSentElapsedMs: nil, totalElapsedMs: 0, pasteAttemptID: "attempt-fixed")),
            captureIDFactory: { "capture-fixed" })
        await command.run()
        #expect(command.resultMessage?.contains("available to copy") == false)
        #expect(command.resultMessage?.contains("Capture capture-, paste attempt attempt-") == true)
    }

    @Test("Command is visible only for the exact environment flag")
    func visibleOnlyForExactEnvironmentFlag() {
        for value in [nil, "0", "true", "yes"] {
            let environment = value.map { [PasteDiagnosticCommand.environmentKey: $0] } ?? [:]
            let command = PasteDiagnosticCommand(environment: environment, pasteService: Recorder())
            #expect(!command.isVisible)
        }

        let enabled = PasteDiagnosticCommand(
            environment: [PasteDiagnosticCommand.environmentKey: "1"],
            pasteService: Recorder()
        )
        #expect(enabled.isVisible)
    }

    @Test("Command runs the fixed phrase through the injected paste boundary")
    func runsFixedPhraseThroughInjectedPasteBoundary() async {
        let recorder = Recorder(timing: PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restored,
            commandSentElapsedMs: 1,
            totalElapsedMs: 2,
            pasteAttemptID: "attempt-12345678",
            postAccessState: true,
            secureInputState: false
        ))
        var announcements: [String] = []
        let command = PasteDiagnosticCommand(
            environment: [PasteDiagnosticCommand.environmentKey: "1"],
            pasteService: recorder,
            captureIDFactory: { "capture-12345678" },
            accessibilityAnnouncement: { announcements.append($0) }
        )

        await command.run()

        #expect(recorder.texts == [PasteDiagnosticCommand.fixedText])
        #expect(recorder.captureIDs == ["capture-12345678"])
        #expect(command.lastCaptureID == "capture-12345678")
        #expect(command.lastPasteAttemptID == "attempt-12345678")
        #expect(command.resultMessage?.contains("Check the target separately") == true)
        #expect(announcements == [command.resultMessage])
    }

    @Test("Blocked command shows only the short attempt ID and truthful fixed-text recovery")
    func blockedCommandShowsShortAttemptID() async {
        let fullAttemptID = "ABCDEF12-3456-7890-ABCD-EF1234567890"
        let recorder = Recorder(timing: PasteTiming(
            commandOutcome: .blocked(.secureInputActive),
            clipboardDisposition: .transcriptPreserved,
            commandSentElapsedMs: nil,
            totalElapsedMs: 2,
            pasteAttemptID: fullAttemptID,
            postAccessState: true,
            secureInputState: true
        ))
        let command = PasteDiagnosticCommand(
            environment: [PasteDiagnosticCommand.environmentKey: "1"],
            pasteService: recorder,
            captureIDFactory: { "capture-87654321" }
        )

        await command.run()

        #expect(command.resultMessage?.contains("Secure Input blocked paste") == true)
        #expect(command.resultMessage?.contains("fixed diagnostic text is on the clipboard") == true)
        #expect(command.resultMessage?.contains("ABCDEF12") == true)
        #expect(command.resultMessage?.contains(fullAttemptID) == false)
        #expect(command.resultMessage?.contains("History") == false)
    }

    @Test("Changed clipboard diagnostic never claims History recovery")
    func changedClipboardDiagnosticAvoidsHistoryClaim() async {
        let recorder = Recorder(timing: PasteTiming(
            commandOutcome: .blocked(.postEventAccessDenied),
            clipboardDisposition: .externalWritePreserved,
            commandSentElapsedMs: nil,
            totalElapsedMs: 2,
            pasteAttemptID: "87654321-ABCD-EF00-1234-567890ABCDEF",
            postAccessState: false,
            secureInputState: nil
        ))
        let command = PasteDiagnosticCommand(
            environment: [PasteDiagnosticCommand.environmentKey: "1"],
            pasteService: recorder,
            captureIDFactory: { "capture-changed" }
        )

        await command.run()

        #expect(command.resultMessage?.contains("clipboard changed") == true)
        #expect(command.resultMessage?.contains("did not overwrite") == true)
        #expect(command.resultMessage?.contains("History") == false)
        #expect(command.resultMessage?.contains("on the clipboard") == false)
    }

    @MainActor
    private final class Recorder: PasteServicing {
        var timing: PasteTiming
        private(set) var texts: [String] = []
        private(set) var captureIDs: [String?] = []

        init(timing: PasteTiming = PasteTiming(
            commandOutcome: .posted,
            clipboardDisposition: .restored,
            commandSentElapsedMs: 0,
            totalElapsedMs: 0,
            pasteAttemptID: "attempt-default",
            postAccessState: true,
            secureInputState: false
        )) {
            self.timing = timing
        }

        func pasteAndRestore(text: String, captureID: String?) async throws -> PasteTiming {
            texts.append(text)
            captureIDs.append(captureID)
            return timing
        }

        func copyToClipboardForRecovery(text: String) -> Bool {
            false
        }
    }
}
