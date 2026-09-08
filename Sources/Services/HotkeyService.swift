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
    enum MonitorStartFailure: String, Sendable {
        case globalMonitorUnavailable = "global_monitor_unavailable"
        case localMonitorUnavailable = "local_monitor_unavailable"
        case bothMonitorsUnavailable = "both_monitors_unavailable"
    }

    static let shared = HotkeyService()

    private let monitorClient: HotkeyMonitorClient
    private let diagnostics: @MainActor (String, String?, [String: String]) -> Void
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    
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
    
    var onKeyDown: ((String?) -> Bool)?
    var onKeyUp: (() -> Void)?
    var onHoldStarted: (() -> Void)?
    var onHoldCancelled: (() -> Void)?
    var onLockEngaged: (() -> Void)?
    var onLockDisengaged: (() -> Void)?
    var onMonitorStartFailure: ((MonitorStartFailure) -> Void)?
    var captureIDFactory: (() -> String?)?

    /// Internal (not private) so tests can drive fresh instances with
    /// synthetic HotkeyModifierEvents instead of sharing global state.
    init(
        monitorClient: HotkeyMonitorClient = .live,
        diagnostics: @escaping @MainActor (String, String?, [String: String]) -> Void = { event, captureID, metadata in
            Task {
                CaptureDiagnostics.shared.mark(event, captureID: captureID, metadata: metadata)
            }
        }
    ) {
        self.monitorClient = monitorClient
        self.diagnostics = diagnostics
    }
    
    @discardableResult
    func start() -> Bool {
        if globalFlagsMonitor != nil || localFlagsMonitor != nil || fnCaptureID != nil || fnDelayedStartTask != nil || fnRecordingDidStart || fnKeyIsDown || rightOptionDown || lastRightOptionTapTime != nil || isLocked {
            stop(reason: .restartingMonitor)
        } else {
            resetState()
        }

        let installedGlobalMonitor = monitorClient.installGlobalFlagsMonitor { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        let installedLocalMonitor = monitorClient.installLocalFlagsMonitor { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        guard let installedGlobalMonitor, let installedLocalMonitor else {
            if let installedGlobalMonitor {
                monitorClient.removeMonitor(installedGlobalMonitor)
            }
            if let installedLocalMonitor {
                monitorClient.removeMonitor(installedLocalMonitor)
            }
            let failure: MonitorStartFailure
            switch (installedGlobalMonitor != nil, installedLocalMonitor != nil) {
            case (false, false):
                failure = .bothMonitorsUnavailable
            case (false, true):
                failure = .globalMonitorUnavailable
            case (true, false):
                failure = .localMonitorUnavailable
            case (true, true):
                preconditionFailure("complete monitor pair must pass the guard")
            }
            resetState()
            logDiagnostics("hotkey.monitor_start_failed", metadata: [
                "global_installed": String(installedGlobalMonitor != nil),
                "local_installed": String(installedLocalMonitor != nil),
                "failure": failure.rawValue
            ])
            onMonitorStartFailure?(failure)
            return false
        }

        globalFlagsMonitor = installedGlobalMonitor
        localFlagsMonitor = installedLocalMonitor

        logDiagnostics("hotkey.service_started", metadata: [
            "hold_threshold_ms": String(Int(holdThreshold * 1000)),
            "double_tap_threshold_ms": String(Int(doubleTapThreshold * 1000))
        ])
        return true
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

        guard let captureID = captureIDFactory?() else {
            fnCaptureID = nil
            logDiagnostics("hotkey.fn.admission_rejected")
            return
        }
        fnCaptureID = captureID
        logDiagnostics("hotkey.fn.press", captureID: fnCaptureID, metadata: [
            "hold_threshold_ms": String(Int(holdThreshold * 1000))
        ])
        
        onHoldStarted?()
        
        let threshold = holdThreshold
        fnDelayedStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(threshold * 1000)))
            guard let self, !Task.isCancelled else { return }
            guard !self.isLocked else { return }
            guard self.fnKeyIsDown, self.fnCaptureID == captureID else { return }
            self.fnDelayedStartTask = nil
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
            self.fnRecordingDidStart = self.onKeyDown?(captureID) ?? false
            if !self.fnRecordingDidStart {
                self.logDiagnostics("hotkey.fn.capture_rejected", captureID: captureID)
            }
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
            lastRightOptionTapTime = nil
            // Cold lock samples before any UI callback. Fn-to-lock keeps the
            // original gesture's proof and never samples the current field.
            guard let captureID = fnCaptureID ?? captureIDFactory?() else {
                logDiagnostics("hotkey.lock.admission_rejected")
                return
            }
            fnDelayedStartTask?.cancel()
            fnDelayedStartTask = nil
            guard onKeyDown?(captureID) == true else {
                fnRecordingDidStart = false
                fnCaptureID = nil
                logDiagnostics("hotkey.lock.capture_rejected", captureID: captureID)
                return
            }
            fnRecordingDidStart = false
            fnCaptureID = captureID
            isLocked = true
            logDiagnostics("hotkey.lock.engaged", captureID: captureID, metadata: ["double_tap_threshold_ms": String(Int(doubleTapThreshold * 1000))])
            onLockEngaged?()
        } else {
            lastRightOptionTapTime = now
            logDiagnostics("hotkey.lock.tap_registered")
        }
    }
    
    func stop(reason: HotkeyServiceStopReason = .manualStop) {
        let hadGlobalMonitor = globalFlagsMonitor != nil
        let hadLocalMonitor = localFlagsMonitor != nil
        let hadPendingThresholdTask = fnDelayedStartTask != nil
        let recordingActive = fnRecordingDidStart
        let fnWasDown = fnKeyIsDown
        let wasLocked = isLocked
        let captureID = fnCaptureID

        if let globalFlagsMonitor {
            monitorClient.removeMonitor(globalFlagsMonitor)
        }
        if let localFlagsMonitor {
            monitorClient.removeMonitor(localFlagsMonitor)
        }

        resetState()

        logDiagnostics("hotkey.service_stopped", captureID: captureID, metadata: [
            "reason": reason.rawValue,
            "had_monitor": String(hadGlobalMonitor || hadLocalMonitor),
            "had_global_monitor": String(hadGlobalMonitor),
            "had_local_monitor": String(hadLocalMonitor),
            "had_pending_threshold_task": String(hadPendingThresholdTask),
            "recording_active": String(recordingActive),
            "fn_key_down": String(fnWasDown),
            "was_locked": String(wasLocked)
        ])
    }

    private func resetState() {
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
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
        diagnostics(event, captureID, metadata)
    }
}
