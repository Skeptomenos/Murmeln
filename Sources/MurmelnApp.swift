import SwiftUI
import AppKit

@main
struct MurmelnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            MoleIcon(state: AppState.shared.currentState)
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MoleIcon: View {
    var state: AppState.RecordingState
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                Circle()
                    .fill(fillColor)
                    .scaleEffect(x: 1.2, y: 1.0)
                    .offset(y: h * 0.2)
                    .mask(
                        Rectangle()
                            .frame(width: w, height: h)
                            .offset(y: h * 0.1)
                    )
                
                Circle()
                    .fill(state == .recording ? Color.red : Color.pink)
                    .frame(width: w * 0.2, height: w * 0.2)
                    .position(x: w * 0.85, y: h * 0.55)
                
                Circle()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: w * 0.1, height: w * 0.1)
                    .position(x: w * 0.65, y: h * 0.4)
                
                Path { path in
                    path.move(to: CGPoint(x: w * 0.85, y: h * 0.6))
                    path.addLine(to: CGPoint(x: w * 1.0, y: h * 0.55))
                    path.move(to: CGPoint(x: w * 0.85, y: h * 0.65))
                    path.addLine(to: CGPoint(x: w * 1.0, y: h * 0.7))
                }
                .stroke(Color.primary.opacity(0.5), lineWidth: 1)
                
                if state == .processing {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                        .position(x: w * 0.2, y: h * 0.3)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private var fillColor: Color {
        switch state {
        case .recording: return .red
        case .processing: return .primary.opacity(0.5)
        case .idle: return .primary
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
