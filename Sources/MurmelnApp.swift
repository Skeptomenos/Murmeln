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
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MoleIcon: View {
    var state: AppState.RecordingState
    
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            
            var path = Path()
            path.move(to: CGPoint(x: width * 0.1, y: height * 0.9))
            path.addCurve(
                to: CGPoint(x: width * 0.9, y: height * 0.9),
                control1: CGPoint(x: width * 0.1, y: height * 0.1),
                control2: CGPoint(x: width * 0.9, y: height * 0.1)
            )
            path.closeSubpath()
            
            context.fill(path, with: .color(fillColor))
            
            let noseRect = CGRect(x: width * 0.75, y: height * 0.38, width: width * 0.15, height: width * 0.15)
            context.fill(Path(ellipseIn: noseRect), with: .color(state == .recording ? .red : .pink))
            
            let eyeRect = CGRect(x: width * 0.62, y: height * 0.32, width: width * 0.08, height: width * 0.08)
            context.fill(Path(ellipseIn: eyeRect), with: .color(.primary.opacity(0.8)))
            
            var whiskers = Path()
            whiskers.move(to: CGPoint(x: width * 0.85, y: height * 0.5))
            whiskers.addLine(to: CGPoint(x: width * 0.98, y: height * 0.45))
            whiskers.move(to: CGPoint(x: width * 0.85, y: height * 0.55))
            whiskers.addLine(to: CGPoint(x: width * 0.98, y: height * 0.55))
            context.stroke(whiskers, with: .color(.primary.opacity(0.5)), lineWidth: 1)
            
            if state == .processing {
                var sparkle = Path()
                let center = CGPoint(x: width * 0.2, y: height * 0.3)
                let size = width * 0.15
                sparkle.move(to: CGPoint(x: center.x, y: center.y - size))
                sparkle.addQuadCurve(to: CGPoint(x: center.x + size, y: center.y), control: CGPoint(x: center.x + size * 0.2, y: center.y - size * 0.2))
                sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y + size), control: CGPoint(x: center.x + size * 0.2, y: center.y + size * 0.2))
                sparkle.addQuadCurve(to: CGPoint(x: center.x - size, y: center.y), control: CGPoint(x: center.x - size * 0.2, y: center.y + size * 0.2))
                sparkle.addQuadCurve(to: CGPoint(x: center.x, y: center.y - size), control: CGPoint(x: center.x - size * 0.2, y: center.y - size * 0.2))
                context.fill(sparkle, with: .color(.blue))
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
