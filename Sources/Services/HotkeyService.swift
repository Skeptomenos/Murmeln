import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()
    
    private var flagsMonitor: Any?
    
    private var fnKeyIsDown = false
    private var fnDelayedStartTask: Task<Void, Never>?
    private var fnRecordingDidStart = false
    
    private var rightOptionDown = false
    private var lastRightOptionTapTime: Date?
    private var isLocked = false
    
    var holdThreshold: TimeInterval = 0.4
    var doubleTapThreshold: TimeInterval = 0.4
    
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onHoldStarted: (() -> Void)?
    var onHoldCancelled: (() -> Void)?
    var onLockEngaged: (() -> Void)?
    var onLockDisengaged: (() -> Void)?
    
    private init() {}
    
    func start() {
        stop()
        
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        handleFnKey(event)
        handleRightOptionKey(event)
    }
    
    private func handleFnKey(_ event: NSEvent) {
        let fnPressed = event.modifierFlags.contains(.function)
        let noOtherModifiers = !event.modifierFlags.contains(.command) &&
                               !event.modifierFlags.contains(.option) &&
                               !event.modifierFlags.contains(.control) &&
                               !event.modifierFlags.contains(.shift)
        
        if fnPressed && noOtherModifiers && !fnKeyIsDown {
            handleFnPressed()
        } else if !fnPressed && fnKeyIsDown {
            handleFnReleased()
        }
    }
    
    private func handleFnPressed() {
        fnKeyIsDown = true
        
        if isLocked {
            return
        }
        
        onHoldStarted?()
        
        let threshold = holdThreshold
        fnDelayedStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(threshold * 1000)))
            guard let self, !Task.isCancelled else { return }
            guard !self.isLocked else { return }
            self.fnDelayedStartTask = nil
            self.fnRecordingDidStart = true
            self.onKeyDown?()
        }
    }
    
    private func handleFnReleased() {
        fnKeyIsDown = false
        
        if isLocked {
            return
        }
        
        if let task = fnDelayedStartTask {
            task.cancel()
            fnDelayedStartTask = nil
            
            if !fnRecordingDidStart {
                onHoldCancelled?()
            } else {
                fnRecordingDidStart = false
                onKeyUp?()
            }
        } else if fnRecordingDidStart {
            fnRecordingDidStart = false
            onKeyUp?()
        }
    }
    
    private func handleRightOptionKey(_ event: NSEvent) {
        // Only handle events for the Right Option key specifically
        guard event.keyCode == kVK_RightOption else { return }
        
        // Right Option pressed: option flag is set and we weren't tracking it
        let isRightOptionPressed = event.modifierFlags.contains(.option) && !rightOptionDown
        
        if isRightOptionPressed {
            handleRightOptionPressed()
        } else if rightOptionDown {
            // Right Option released: we were tracking it as down and this is a Right Option key event
            // Note: We detect release by keyCode, NOT by checking if .option flag is cleared
            // This fixes the bug where Left Option being held would prevent release detection
            handleRightOptionReleased()
        }
    }
    
    private func handleRightOptionPressed() {
        rightOptionDown = true
    }
    
    private func handleRightOptionReleased() {
        rightOptionDown = false
        
        let now = Date()
        
        if isLocked {
            isLocked = false
            fnRecordingDidStart = false
            lastRightOptionTapTime = nil
            onLockDisengaged?()
            onKeyUp?()
            return
        }
        
        if let lastTap = lastRightOptionTapTime,
           now.timeIntervalSince(lastTap) < doubleTapThreshold {
            fnDelayedStartTask?.cancel()
            fnDelayedStartTask = nil
            if fnRecordingDidStart {
                fnRecordingDidStart = false
            }
            
            isLocked = true
            lastRightOptionTapTime = nil
            onLockEngaged?()
            onKeyDown?()
        } else {
            lastRightOptionTapTime = now
        }
    }
    
    func stop() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        flagsMonitor = nil
        fnKeyIsDown = false
        fnDelayedStartTask?.cancel()
        fnDelayedStartTask = nil
        fnRecordingDidStart = false
        rightOptionDown = false
        lastRightOptionTapTime = nil
        isLocked = false
    }
}
