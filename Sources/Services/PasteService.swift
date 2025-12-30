import Foundation
import AppKit
import Carbon.HIToolbox

final class PasteService: Sendable {
    @MainActor static let shared = PasteService()
    
    func paste(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.simulatePasteViaCGEvent()
        }
    }
    
    private func simulatePasteViaCGEvent() {
        print("⌨️ Simulating paste via CGEvent (Accessibility)")
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        cmdVDown?.flags = .maskCommand
        
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        cmdVUp?.flags = .maskCommand
        
        cmdVDown?.post(tap: .cgSessionEventTap)
        cmdVUp?.post(tap: .cgSessionEventTap)
    }
    
    private func simulatePasteViaAppleScript() {
        print("🍎 Fallback: Simulating paste via AppleScript (System Events)")
        var error: NSDictionary?
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        
        script?.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript Paste Error: \(error)")
        }
    }
}
