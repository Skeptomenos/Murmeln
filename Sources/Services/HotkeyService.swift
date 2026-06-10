import AppKit
import Carbon.HIToolbox

enum HotkeyServiceStopReason: String, Sendable {
    case applicationTerminating = "application_terminating"
    case restartingMonitor = "restarting_monitor"
    case manualStop = "manual_stop"
}

struct HotkeyModifierEvent {
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    init(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }
}

@MainActor
final class HotkeyService {
    static let shared = HotkeyService()
    
    private var flagsMonitor: Any?
    
    private var fnKeyIsDown = false
    private var fnCaptureID: String?
    private var fnDelayedStartTask: Task<Void, Never>?
    private var fnRecordingDidStart = false
    private var fnPressTime: Date?
    
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
    var captureIDFactory: (() -> String?)?
    
    private init() {}
    
    func start() {
        if flagsMonitor != nil || fnCaptureID != nil || fnDelayedStartTask != nil || fnRecordingDidStart || fnKeyIsDown || rightOptionDown || lastRightOptionTapTime != nil || isLocked {
            stop(reason: .restartingMonitor)
        } else {
            resetState()
        }
        
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        logDiagnostics("hotkey.service_started", metadata: [
            "hold_threshold_ms": String(Int(holdThreshold * 1000)),
            "double_tap_threshold_ms": String(Int(doubleTapThreshold * 1000))
        ])
    }
    
    private func handleFlagsChanged(_ event: NSEvent) {
        handleModifierEvent(HotkeyModifierEvent(event: event))
    }

    func handleModifierEvent(_ event: HotkeyModifierEvent) {
        handleFnKey(event)
        handleRightOptionKey(event)
    }
    
    private func handleFnKey(_ event: HotkeyModifierEvent) {
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
        fnPressTime = Date()
         
        if isLocked {
            logDiagnostics("hotkey.fn.press_ignored_locked", metadata: [
                "reason": "lock_mode_active"
            ])
            return
        }

        fnCaptureID = captureIDFactory?()
        logDiagnostics("hotkey.fn.press", captureID: fnCaptureID, metadata: [
            "hold_threshold_ms": String(Int(holdThreshold * 1000))
        ])
        
        onHoldStarted?()
        
        let threshold = holdThreshold
        fnDelayedStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(threshold * 1000)))
            guard let self, !Task.isCancelled else { return }
            guard !self.isLocked else { return }
            self.fnDelayedStartTask = nil
            self.fnRecordingDidStart = true
            if let pressTime = self.fnPressTime {
                let elapsedMs = Int(Date().timeIntervalSince(pressTime) * 1000)
                self.logDiagnostics("hotkey.fn.threshold_met", captureID: self.fnCaptureID, metadata: [
                    "elapsed_ms": String(elapsedMs),
                    "hold_threshold_ms": String(Int(threshold * 1000))
                ])
            } else {
                self.logDiagnostics("hotkey.fn.threshold_met", captureID: self.fnCaptureID, metadata: [
                    "hold_threshold_ms": String(Int(threshold * 1000))
                ])
            }
            self.onKeyDown?()
        }
    }
    
    private func handleFnReleased() {
        fnKeyIsDown = false
        let captureID = fnCaptureID
        let holdDurationMs = fnPressTime.map { Int(Date().timeIntervalSince($0) * 1000) }
        fnPressTime = nil
        
        if isLocked {
            logDiagnostics("hotkey.fn.release_ignored_locked", metadata: holdDurationMs.map {
                [
                    "hold_ms": String($0),
                    "reason": "lock_mode_active"
                ]
            } ?? ["reason": "lock_mode_active"])
            return
        }
        
        if let task = fnDelayedStartTask {
            task.cancel()
            fnDelayedStartTask = nil
            
            if !fnRecordingDidStart {
                logDiagnostics("hotkey.fn.release_before_threshold", captureID: captureID, metadata: holdDurationMs.map {
                    [
                        "hold_ms": String($0),
                        "hold_threshold_ms": String(Int(holdThreshold * 1000))
                    ]
                } ?? ["hold_threshold_ms": String(Int(holdThreshold * 1000))])
                onHoldCancelled?()
            } else {
                fnRecordingDidStart = false
                logDiagnostics("hotkey.fn.release_stop", captureID: captureID, metadata: holdDurationMs.map {
                    ["hold_ms": String($0)]
                } ?? [:])
                onKeyUp?()
            }
        } else if fnRecordingDidStart {
            fnRecordingDidStart = false
            logDiagnostics("hotkey.fn.release_stop_no_task", captureID: captureID, metadata: holdDurationMs.map {
                [
                    "hold_ms": String($0),
                    "reason": "threshold_task_already_finished"
                ]
            } ?? ["reason": "threshold_task_already_finished"])
            onKeyUp?()
        } else {
            logDiagnostics("hotkey.fn.release_noop", captureID: captureID, metadata: holdDurationMs.map {
                [
                    "hold_ms": String($0),
                    "reason": "no_recording_in_progress"
                ]
            } ?? ["reason": "no_recording_in_progress"])
        }

        fnCaptureID = nil
    }
    
    private func handleRightOptionKey(_ event: HotkeyModifierEvent) {
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
        logDiagnostics("hotkey.lock.right_option_press")
    }
    
    private func handleRightOptionReleased() {
        rightOptionDown = false
        
        let now = Date()
        
        if isLocked {
            isLocked = false
            fnRecordingDidStart = false
            fnCaptureID = nil
            lastRightOptionTapTime = nil
            logDiagnostics("hotkey.lock.disengaged")
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
            logDiagnostics("hotkey.lock.engaged", metadata: ["double_tap_threshold_ms": String(Int(doubleTapThreshold * 1000))])
            onLockEngaged?()
            onKeyDown?()
        } else {
            lastRightOptionTapTime = now
            logDiagnostics("hotkey.lock.tap_registered")
        }
    }
    
    func stop(reason: HotkeyServiceStopReason = .manualStop) {
        let hadMonitor = flagsMonitor != nil
        let hadPendingThresholdTask = fnDelayedStartTask != nil
        let recordingActive = fnRecordingDidStart
        let fnWasDown = fnKeyIsDown
        let wasLocked = isLocked
        let captureID = fnCaptureID

        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }

        resetState()

        logDiagnostics("hotkey.service_stopped", captureID: captureID, metadata: [
            "reason": reason.rawValue,
            "had_monitor": String(hadMonitor),
            "had_pending_threshold_task": String(hadPendingThresholdTask),
            "recording_active": String(recordingActive),
            "fn_key_down": String(fnWasDown),
            "was_locked": String(wasLocked)
        ])
    }

    private func resetState() {
        flagsMonitor = nil
        fnKeyIsDown = false
        fnCaptureID = nil
        fnDelayedStartTask?.cancel()
        fnDelayedStartTask = nil
        fnRecordingDidStart = false
        rightOptionDown = false
        lastRightOptionTapTime = nil
        isLocked = false
        fnPressTime = nil
    }

    private func logDiagnostics(_ event: String, captureID: String? = nil, metadata: [String: String] = [:]) {
        Task {
            await CaptureDiagnostics.shared.mark(event, captureID: captureID, metadata: metadata)
        }
    }
}
