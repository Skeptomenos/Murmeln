import SwiftUI
import AppKit

@main
struct MurmelnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    
    var body: some Scene {
        MenuBarExtra("Murmeln", systemImage: iconName) {
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
    enum RecordingState {
        case idle, recording, processing
    }
    
    var currentState: RecordingState {
        if isRecording { return .recording }
        if isProcessing { return .processing }
        return .idle
    }
}

struct MenuContent: View {
    @ObservedObject private var appState = AppState.shared
    
    var body: some View {
        if appState.isRecording {
            Text("Recording...")
                .foregroundColor(.red)
        } else if appState.isProcessing {
            Text("Processing...")
                .foregroundColor(.blue)
        } else {
            Text("Ready (Hold Fn to record)")
                .foregroundColor(.secondary)
        }
        
        if let error = appState.lastError {
            Text(error)
                .foregroundColor(.red)
                .font(.caption)
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
        
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        HotkeyService.shared.onKeyDown = {
            AppState.shared.startRecording()
        }
        
        HotkeyService.shared.onKeyUp = {
            AppState.shared.stopAndProcess()
        }
        
        HotkeyService.shared.start()
    }
}
