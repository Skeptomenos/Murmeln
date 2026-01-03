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
    @ObservedObject private var overlay = OverlayWindowController.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    
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
        
        if !historyStore.recentEntries.isEmpty {
            Menu("History") {
                ForEach(historyStore.recentEntries) { entry in
                    Button {
                        copyToClipboard(entry.displayText)
                    } label: {
                        HStack {
                            Text(entry.formattedTime)
                                .foregroundColor(.secondary)
                            Text(entry.previewText)
                        }
                    }
                }
                
                Divider()
                
                Button("Show All...") {
                    HistoryWindowController.shared.show()
                }
                
                if !historyStore.entries.isEmpty {
                    Button("Clear History") {
                        historyStore.clear()
                    }
                }
            }
            
            Divider()
        }
        
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
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        let hotkey = HotkeyService.shared
        let overlay = OverlayWindowController.shared
        
        overlay.showAlways()
        
        hotkey.onHoldStarted = {
            overlay.state = .waiting
        }
        
        hotkey.onHoldCancelled = {
            overlay.state = .idle
        }
        
        hotkey.onKeyDown = {
            overlay.state = .listening
            AppState.shared.startRecording()
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
    }
}
