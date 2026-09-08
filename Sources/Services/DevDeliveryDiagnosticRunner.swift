import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// One explicit, fixed-receiver experiment per Dev process. No polling or retries.
@MainActor
final class DevDeliveryDiagnosticRunner {
    static let shared = DevDeliveryDiagnosticRunner()
    static let runIDEnvironmentKey = "MURMELN_DEV_DELIVERY_PROBE_RUN_ID"
    private var task: Task<Void, Never>?
    private var started = false

    func startIfRequested() {
        #if MURMELN_DEV_DIAGNOSTICS
        let environment = ProcessInfo.processInfo.environment
        guard !started,
              DevDeliveryDiagnostic.isEnabled(bundleIdentifier: Bundle.main.bundleIdentifier, environment: environment),
              let rawID = environment[Self.runIDEnvironmentKey], let runID = UUID(uuidString: rawID) else { return }
        started = true
        task = Task {
            // Give the test operator time to select the receiver. No automatic focus change.
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            await run(runID: runID)
            task = nil
        }
        #endif
    }

    func suspend() { task?.cancel() }
    func quiesce() async { suspend(); await task?.value }

    private func run(runID: UUID) async {
        var receipt = Receipt(runID: runID.uuidString,
            processID: ProcessInfo.processInfo.processIdentifier,
            postAccess: CGPreflightPostEventAccess(), accessibilityAccess: AXIsProcessTrusted(),
            secureInputBefore: IsSecureEventInputEnabled())
        defer { write(receipt, runID: runID) }
        guard receipt.postAccess && receipt.accessibilityAccess else {
            receipt.result = "permission_unavailable"
            return
        }
        guard let target = DevDeliveryDiagnosticTarget() else {
            receipt.result = "invalid_target"
            return
        }
        switch await PasteService.shared.runDevDeliveryDiagnostic(target: target) {
        case .refused(let reason): receipt.result = reason.rawValue
        case .completed(let timing):
            receipt.pasteAttemptID = timing.pasteAttemptID
            receipt.commandOutcome = timing.commandOutcome.telemetryValue
            receipt.clipboardDisposition = timing.clipboardDisposition.rawValue
            receipt.postAccessAtDecision = timing.postAccessState
            receipt.secureInputAtDecision = timing.secureInputState
            receipt.secureInputAfter = IsSecureEventInputEnabled()
            switch timing.commandOutcome {
            case .posted:
                let matches = target.currentValueMatches(DevDeliveryDiagnosticTarget.initialText + DevDeliveryDiagnostic.fixedText)
                receipt.receiverMatches = matches
                receipt.result = matches ? "receiver_verified" : "receiver_not_verified"
            case .blocked(let reason): receipt.result = reason.rawValue
            case .notAttempted: receipt.result = "not_attempted"
            }
        }
    }

    private func write(_ receipt: Receipt, runID: UUID) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-dev-delivery-probe-\(runID.uuidString).json")
        // This is a private, explicitly requested test artifact. It contains no
        // clipboard contents, AX values, transcript, document paths or owner hints.
        if let data = try? encoder.encode(receipt) { try? data.write(to: url, options: .atomic) }
    }

    private struct Receipt: Encodable {
        let schemaVersion = 1
        let runID: String
        let processID: Int32
        let postAccess: Bool
        let accessibilityAccess: Bool
        let secureInputBefore: Bool
        var result = "cancelled"
        var pasteAttemptID: String?
        var commandOutcome: String?
        var clipboardDisposition: String?
        var postAccessAtDecision: Bool?
        var secureInputAtDecision: Bool?
        var secureInputAfter: Bool?
        var receiverMatches: Bool?
    }
}
