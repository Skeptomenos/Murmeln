import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()
    
    private var flagsMonitor: Any?
    
    private var fnKeyIsDown = false
    private var fnDelayedStartWork: DispatchWorkItem?
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
        
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isLocked else { return }
                self.fnDelayedStartWork = nil
                self.fnRecordingDidStart = true
                self.onKeyDown?()
            }
        }
        fnDelayedStartWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
    }
    
    private func handleFnReleased() {
        fnKeyIsDown = false
        
        if isLocked {
            return
        }
        
        if let work = fnDelayedStartWork {
            work.cancel()
            fnDelayedStartWork = nil
            
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
        let isRightOption = event.modifierFlags.contains(.option) && event.keyCode == kVK_RightOption
        let optionReleased = !event.modifierFlags.contains(.option) && rightOptionDown
        
        if isRightOption && !rightOptionDown {
            handleRightOptionPressed()
        } else if optionReleased {
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
            fnDelayedStartWork?.cancel()
            fnDelayedStartWork = nil
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
        fnDelayedStartWork?.cancel()
        fnDelayedStartWork = nil
        fnRecordingDidStart = false
        rightOptionDown = false
        lastRightOptionTapTime = nil
        isLocked = false
    }
}
