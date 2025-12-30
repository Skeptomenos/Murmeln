import AppKit

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()
    
    private var monitor: Any?
    private var fnKeyIsDown = false
    
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    
    private init() {}
    
    func start() {
        stop()
        
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)
        let noOtherModifiers = !event.modifierFlags.contains(.command) &&
                               !event.modifierFlags.contains(.option) &&
                               !event.modifierFlags.contains(.control) &&
                               !event.modifierFlags.contains(.shift)
        
        if fnPressed && noOtherModifiers && !fnKeyIsDown {
            fnKeyIsDown = true
            onKeyDown?()
        } else if !fnPressed && fnKeyIsDown {
            fnKeyIsDown = false
            onKeyUp?()
        }
    }
    
    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        fnKeyIsDown = false
    }
}
