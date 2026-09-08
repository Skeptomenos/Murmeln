import SwiftUI
import AppKit
import Combine
import os

private let appDelegateLogger = Logger(subsystem: "com.skeptomenos.murmeln", category: "AppDelegate")

@main
struct MurmelnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        MenuBarExtra(AppIdentity.menuBarTitle, systemImage: iconName) {
            MenuContent(appDelegate: appDelegate)
        }
        .menuBarExtraStyle(.menu)
    }
    
    private var iconName: String {
        if appState.isRecording {
            return "mic.fill"
        } else if appState.isProcessing {
            return "sparkles"
        } else if appState.needsPasteRecoveryAttention {
            return "exclamationmark.bubble"
        } else {
            return "mic"
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var overlay = OverlayWindowController.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    @ObservedObject private var updateService = UpdateService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var pasteDiagnosticCommand: PasteDiagnosticCommand
    @State private var pastePermissionController: PastePermissionController
    @State private var termination: TerminationCoordinator
    private let appDelegate: AppDelegate

    init(
        appDelegate: AppDelegate,
        permissionService: PermissionService = .shared,
        pastePermissionController: PastePermissionController? = nil,
        pasteDiagnosticCommand: PasteDiagnosticCommand = .shared
    ) {
        self.appDelegate = appDelegate
        _pastePermissionController = State(initialValue: pastePermissionController ?? PastePermissionController(permissionService: permissionService))
        _termination = State(initialValue: appDelegate.termination)
        _pasteDiagnosticCommand = State(initialValue: pasteDiagnosticCommand)
    }
    
    var body: some View {
        Group {
            if overlay.state == .locked {
                Text("Recording (Locked) - Tap Right Option to stop")
                    .foregroundColor(.orange)
            } else if appState.isRecording {
                Text("Recording...")
                    .foregroundColor(.red)
            } else if appState.isProcessing {
                Text("Processing...")
                    .foregroundColor(.blue)
            } else {
                Text("Hold Fn · Double-tap ⌥ for lock")
                    .foregroundColor(.secondary)
            }
        
            if let error = appState.lastError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            RecoveryActionsView(appState: appState)
            HistorySaveNotice(store: historyStore)
            if let message = appState.captureAdmissionMessage {
                Text(message)
                Button("Open History to recover space") { HistoryWindowController.shared.show() }
            }
            if termination.needsLossConfirmation {
                Text("Quit was cancelled because History could not be saved.")
                Button("Quit anyway…") { confirmLossAndQuit() }
                    .disabled(termination.isInFlight)
            }

            Divider()
        
            Button("Show History (\(historyStore.entries.count))") {
                HistoryWindowController.shared.show()
            }
        
            Divider()

            if pasteDiagnosticCommand.isVisible {
                Button(pasteDiagnosticCommand.isRunning ? "Running Paste Diagnostic..." : "Run Paste Diagnostic") {
                    pasteDiagnosticCommand.start()
                }
                .disabled(pasteDiagnosticCommand.isRunning)

                if let resultMessage = pasteDiagnosticCommand.resultMessage {
                    Text(resultMessage)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Divider()
            }
        
            if !pastePermissionController.hasPostEventAccess {
                Button("Open Accessibility Settings") {
                    openAccessibilitySettings()
                }
                if let message = pastePermissionController.navigationMessage {
                    Text(message).font(.caption)
                    Text("Enable \(AppIdentity.menuBarTitle), then restart.").font(.caption)
                }
                Divider()
            }
        
            Button("Settings...") {
                SettingsWindowController.shared.show()
            }
            .keyboardShortcut(",", modifiers: .command)
        
            Button(updateService.isChecking ? "Checking..." : "Check for Updates...") {
                Task {
                    await updateService.checkForUpdates()
                    if updateService.updateAvailable {
                        updateService.showUpdateAlert()
                    } else {
                        updateService.showUpToDateAlert()
                    }
                }
            }
            .disabled(updateService.isChecking)
        
            if updateService.updateAvailable, let version = updateService.latestVersion {
                Button("Download Update (v\(version))") {
                    updateService.openReleasePage()
                }
                .foregroundColor(.blue)
            }
        
            Button("Restart") {
                restartApp()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(termination.isInFlight)
        
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .disabled(termination.isInFlight)
        }
        .onAppear { pastePermissionController.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            pastePermissionController.refresh()
        }
    }

    func openAccessibilitySettings() {
        pastePermissionController.openSettings()
    }
    
    func restartApp() {
        appDelegate.requestRestart()
    }

    func confirmLossAndQuit() {
        appDelegate.confirmLossAndQuit()
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let terminateApplication: @MainActor () -> Void
    private let restartService: RestartService

    override convenience init() {
        self.init(terminateApplication: { NSApp.terminate(nil) })
    }

    init(terminateApplication: @escaping @MainActor () -> Void, restartService: RestartService = RestartService()) {
        self.terminateApplication = terminateApplication
        self.restartService = restartService
        super.init()
    }
    private var allowLossOnNextQuit = false
    private var restartRequested = false
    lazy var termination: TerminationCoordinator = makeTerminationCoordinator()

    private func makeTerminationCoordinator() -> TerminationCoordinator {
        TerminationCoordinator(
        suspend: {
            HotkeyService.shared.stop(reason: .applicationTerminating)
            PasteDiagnosticCommand.shared.suspend()
            DevDeliveryDiagnosticRunner.shared.suspend()
        },
        quiesce: {
            let saved = await AppState.shared.quiesceForTermination()
            await PasteDiagnosticCommand.shared.quiesce()
            await DevDeliveryDiagnosticRunner.shared.quiesce()
            return saved
        },
        restore: { [weak self] in
            self?.restartRequested = false
            self?.restartService.resumeCurrentAppIfSafe {
                AppState.shared.resumeAfterCancelledTermination()
                PasteDiagnosticCommand.shared.resume()
                HotkeyService.shared.start()
            }
        },
        beforeExit: { [weak self] in await self?.prepareToExit() ?? false })
    }

    private func prepareToExit() async -> Bool {
            if restartRequested {
                guard await restartService.launchReplacement() else {
                    AppState.shared.lastError = restartService.failureMessage
                    return false
                }
            }
            let phase = AppState.shared.diagnosticsRecordingPhaseName
            let captureID = AppState.shared.diagnosticsActiveCaptureID
            await CaptureDiagnostics.shared.endSession(reason: "application_terminating",
                recordingPhase: phase, activeCaptureID: captureID)
            return true
    }
    private var cancellables = Set<AnyCancellable>()
    private var recoveryNotice: RecoveryNoticeController?
    private lazy var selectionLifecycle = TranscriptionSelectionLifecycle(
        runtimeForModel: Self.runtime(for:)
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        recoveryNotice = RecoveryNoticeController(appState: .shared, history: .shared)
        DevDeliveryDiagnosticRunner.shared.startIfRequested()

        Task {
            await CaptureDiagnostics.shared.startSession()
        }
         
        let hotkey = HotkeyService.shared
        let overlay = OverlayWindowController.shared

        hotkey.captureIDFactory = {
            AppState.shared.prepareCaptureIDForHotkeyPressIfPossible()
        }
         
        overlay.showAlways()
        
        Task {
            await UpdateService.shared.checkForUpdates(automatically: true)
            if UpdateService.shared.updateAvailable {
                UpdateService.shared.showUpdateAlert()
            }
        }
        
        hotkey.onHoldStarted = {
            overlay.state = .waiting
            // Start engine warm-up immediately to eliminate startup latency
            AppState.shared.warmUpEngine()
        }
        
        hotkey.onHoldCancelled = {
            overlay.state = .idle
            // Cancel warm-up if user releases before 400ms threshold
            AppState.shared.cancelWarmUp()
        }
        
        hotkey.onKeyDown = { captureID in
            // Engine is already warm, begin actual recording (near-instant)
            let admitted = AppState.shared.beginRecording(expectedCaptureID: captureID)
            if admitted { overlay.state = .listening }
            return admitted
        }
        
        hotkey.onKeyUp = {
            AppState.shared.stopAndProcess()
        }
        
        hotkey.onLockEngaged = {
            overlay.state = .locked
        }
        
        hotkey.onLockDisengaged = {
            overlay.state = .idle
        }
        
        hotkey.start()

        // Phase 8: eager warm-up of the selected catalog runtime; recording
        // state machine remains untouched.
        Task { @MainActor in
            await Self.warmSelectedBackend()
        }

        // Phase 8 / M6: one complete transition owns unload + warm-up for
        // catalog↔catalog and catalog↔legacy changes.
        AppSettings.shared.transcriptionSelectionChanged
            .sink { [weak self] transition in
                Task { @MainActor in
                    await self?.selectionLifecycle.apply(transition)
                }
            }
            .store(in: &cancellables)
    }

    /// Warm whatever backend the persisted selection points at (app launch).
    @MainActor
    private static func warmSelectedBackend() async {
        switch AppSettings.shared.transcriptionSelection {
        case .catalog(let modelID):
            await warmCatalogModel(modelID)
        case .legacy:
            break  // cloud/server: nothing to warm
        }
    }

    /// Load an installed catalog model into its runtime; not-installed models
    /// are left for the settings pane's download flow (no silent downloads
    /// of multi-GB weights at launch).
    @MainActor
    private static func warmCatalogModel(_ modelID: TranscriptionModelID) async {
        guard let runtime = runtime(for: modelID) else { return }
        guard runtime.isInstalled(modelID) else {
            appDelegateLogger.info("Catalog model \(modelID.rawValue, privacy: .public) not installed; skipping warm-up (settings pane offers the download)")
            return
        }
        do {
            try await runtime.load(modelID)
        } catch {
            appDelegateLogger.error("Warm-up failed for \(modelID.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func runtime(for modelID: TranscriptionModelID) -> (any TranscriptionRuntime)? {
        guard let entry = ModelCatalog.entry(for: modelID) else { return nil }
        switch entry.runtime {
        case .fluidAudio: return FluidAudioRuntime.shared
        case .whisperKit: return WhisperKitRuntime.shared
        }
    }

    func requestRestart() {
        guard !termination.isInFlight, !restartRequested else { return }
        restartRequested = true
        terminateApplication()
    }

    func confirmLossAndQuit() {
        guard termination.needsLossConfirmation, !termination.isInFlight else { return }
        let alert = NSAlert()
        alert.messageText = "Quit without saving?"
        alert.informativeText = "Unsaved text will be lost. History deletions that could not be saved may reappear after restart. Copying text does not save History."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit anyway")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        allowLossOnNextQuit = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let allowLoss = allowLossOnNextQuit
        allowLossOnNextQuit = false
        termination.begin(allowLoss: allowLoss) { sender.reply(toApplicationShouldTerminate: $0) }
        return .terminateLater
    }
}
