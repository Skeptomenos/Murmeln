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
            MenuContent()
        }
        .menuBarExtraStyle(.menu)
    }
    
    private var iconName: String {
        if appState.isRecording {
            return "mic.fill"
        } else if appState.isProcessing {
            return "sparkles"
        } else {
            return "mic"
        }
    }
}

extension AppState {
    /// Simplified state for UI display (maps from internal RecordingPhase)
    enum DisplayState {
        case idle, recording, processing
    }
    
    var currentState: DisplayState {
        switch recordingPhase {
        case .idle:
            return .idle
        case .warmingUp, .requestingPermission, .recording:
            return .recording
        case .processing:
            return .processing
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var overlay = OverlayWindowController.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    @ObservedObject private var updateService = UpdateService.shared
    
    var body: some View {
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
        
        Divider()
        
        Button("Show History (\(historyStore.entries.count))") {
            HistoryWindowController.shared.show()
        }
        
        Divider()
        
        if !PermissionService.shared.checkAccessibilityPermission() {
            Button("Grant Accessibility Permission") {
                _ = PermissionService.shared.checkAccessibilityPermission(prompt: true)
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
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
    
    private func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [url.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationInFlight = false
    private var cancellables = Set<AnyCancellable>()
    // P1-6: Track last observed provider to avoid spurious bridge lifecycle checks.
    // Initialized in applicationDidFinishLaunching (main thread).
    private var lastObservedProvider: String = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        lastObservedProvider = AppSettings.shared.transcriptionProviderRaw

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
        
        hotkey.onKeyDown = {
            overlay.state = .listening
            // Engine is already warm, begin actual recording (near-instant)
            AppState.shared.beginRecording()
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

        // P1-7: Start Cohere bridge eagerly if it's the persisted provider — log errors
        Task { @MainActor in
            if AppSettings.shared.transcriptionProvider == .cohereMLX {
                do {
                    try await CohereMLXService.shared.startBridge()
                } catch {
                    appDelegateLogger.error("Cohere bridge start failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // P1-6: Observe provider changes — only react when transcriptionProviderRaw actually changes
        AppSettings.shared.objectWillChange
            .sink { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let current = AppSettings.shared.transcriptionProviderRaw
                    guard current != self.lastObservedProvider else { return }
                    self.lastObservedProvider = current

                    let provider = AppSettings.shared.transcriptionProvider
                    if provider == .cohereMLX {
                        // P1-7: Log bridge start errors
                        do {
                            try await CohereMLXService.shared.startBridge()
                        } catch {
                            appDelegateLogger.error("Cohere bridge start failed: \(error.localizedDescription, privacy: .public)")
                        }
                    } else {
                        // Stop the bridge if switching away from Cohere and it is active
                        let bridgeState = CohereMLXService.shared.modelState
                        if bridgeState == .ready || bridgeState == .loading {
                            CohereMLXService.shared.stopBridge()
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInFlight else {
            return .terminateNow
        }

        terminationInFlight = true
        HotkeyService.shared.stop(reason: .applicationTerminating)
        // P1-11: Stop Cohere bridge on app quit to avoid orphaned Python process
        CohereMLXService.shared.stopBridge()

        let activeCaptureID = AppState.shared.diagnosticsActiveCaptureID
        let recordingPhase = AppState.shared.diagnosticsRecordingPhaseName

        Task {
            await CaptureDiagnostics.shared.endSession(
                reason: HotkeyServiceStopReason.applicationTerminating.rawValue,
                recordingPhase: recordingPhase,
                activeCaptureID: activeCaptureID
            )

            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }

        return .terminateLater
    }
}
