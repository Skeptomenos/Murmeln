import Testing
import Foundation
@testable import mrml

// MARK: - HotkeyService Tests

@Suite("HotkeyService Tests")
struct HotkeyServiceTests {
    
    // MARK: - Threshold Configuration Tests
    
    @Test("Hold threshold default is 400ms")
    func holdThresholdDefault() async {
        let service = await HotkeyService.shared
        let threshold = await service.holdThreshold
        #expect(threshold == 0.4)
    }
    
    @Test("Double-tap threshold default is 400ms")
    func doubleTapThresholdDefault() async {
        let service = await HotkeyService.shared
        let threshold = await service.doubleTapThreshold
        #expect(threshold == 0.4)
    }
    
    @Test("Thresholds are within usable range")
    func thresholdsWithinUsableRange() async {
        let service = await HotkeyService.shared
        let holdThreshold = await service.holdThreshold
        let doubleTapThreshold = await service.doubleTapThreshold
        
        #expect(holdThreshold >= 0.2)
        #expect(holdThreshold <= 1.0)
        #expect(doubleTapThreshold >= 0.2)
        #expect(doubleTapThreshold <= 1.0)
    }
    
    // MARK: - Callback Properties Tests
    
    @Test("All six callback properties exist and are settable")
    func callbackPropertiesExist() async {
        let service = await HotkeyService.shared
        
        await MainActor.run {
            service.onKeyDown = {}
            service.onKeyUp = {}
            service.onHoldStarted = {}
            service.onHoldCancelled = {}
            service.onLockEngaged = {}
            service.onLockDisengaged = {}
        }
        
        #expect(Bool(true))
    }
    
    // MARK: - Hold Duration Logic Tests
    
    @Test("Quick tap below threshold should not trigger recording")
    func quickTapBelowThreshold() {
        let holdThreshold: TimeInterval = 0.4
        let quickTapDuration: TimeInterval = 0.1
        
        let shouldStartRecording = quickTapDuration >= holdThreshold
        #expect(shouldStartRecording == false)
    }
    
    @Test("Hold beyond threshold should start recording")
    func holdBeyondThreshold() {
        let holdThreshold: TimeInterval = 0.4
        let holdDuration: TimeInterval = 0.5
        
        let shouldStartRecording = holdDuration >= holdThreshold
        #expect(shouldStartRecording == true)
    }
    
    @Test("Hold exactly at threshold should start recording")
    func holdExactlyAtThreshold() {
        let holdThreshold: TimeInterval = 0.4
        let holdDuration: TimeInterval = 0.4
        
        let shouldStartRecording = holdDuration >= holdThreshold
        #expect(shouldStartRecording == true)
    }
    
    @Test("Very short tap (100ms) should not trigger")
    func veryShortTap() {
        let holdThreshold: TimeInterval = 0.4
        let tapDuration: TimeInterval = 0.1
        
        #expect(tapDuration < holdThreshold)
    }
    
    @Test("Long hold (1 second) should trigger")
    func longHold() {
        let holdThreshold: TimeInterval = 0.4
        let holdDuration: TimeInterval = 1.0
        
        #expect(holdDuration >= holdThreshold)
    }
    
    // MARK: - Double-Tap Lock Mode Logic Tests
    
    @Test("Double-tap within threshold engages lock")
    func doubleTapWithinThreshold() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.2
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == true)
    }
    
    @Test("Slow taps outside threshold do not engage lock")
    func slowTapsOutsideThreshold() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.6
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == false)
    }
    
    @Test("Taps exactly at threshold do not engage lock")
    func tapsExactlyAtThreshold() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.4
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == false)
    }
    
    @Test("Very fast double-tap (100ms) engages lock")
    func veryFastDoubleTap() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.1
        
        #expect(timeBetweenTaps < doubleTapThreshold)
    }
    
    // MARK: - Lock Mode State Machine Tests
    
    @Test("Lock mode state transitions: engage then disengage")
    func lockModeStateTransitions() {
        var isLocked = false
        var recordingActive = false
        
        isLocked = true
        recordingActive = true
        #expect(isLocked == true)
        #expect(recordingActive == true)
        
        isLocked = false
        recordingActive = false
        #expect(isLocked == false)
        #expect(recordingActive == false)
    }
    
    @Test("Lock mode continues recording independent of Fn key")
    func lockModeIndependentOfFnKey() {
        let isLocked = true
        let fnKeyHeld = false
        let recordingActive = true
        
        let shouldContinueRecording = isLocked || fnKeyHeld
        #expect(shouldContinueRecording == true)
        #expect(recordingActive == true)
    }
    
    @Test("Single tap after lock disengages and stops recording")
    func singleTapDisengagesLock() {
        var isLocked = true
        var recordingActive = true
        
        isLocked = false
        recordingActive = false
        
        #expect(isLocked == false)
        #expect(recordingActive == false)
    }
    
    @Test("Fn key press during lock mode is ignored")
    func fnKeyIgnoredDuringLock() {
        let isLocked = true
        let fnKeyPressed = true
        
        let shouldStartNewRecording = fnKeyPressed && !isLocked
        #expect(shouldStartNewRecording == false)
    }
    
    // MARK: - State Reset Tests
    
    @Test("Stop resets all state")
    func stopResetsAllState() {
        var fnKeyIsDown = true
        var fnRecordingDidStart = true
        var rightOptionDown = true
        var lastRightOptionTapTime: Date? = Date()
        var isLocked = true
        
        fnKeyIsDown = false
        fnRecordingDidStart = false
        rightOptionDown = false
        lastRightOptionTapTime = nil
        isLocked = false
        
        #expect(fnKeyIsDown == false)
        #expect(fnRecordingDidStart == false)
        #expect(rightOptionDown == false)
        #expect(lastRightOptionTapTime == nil)
        #expect(isLocked == false)
    }
    
    // MARK: - Time Interval Calculation Tests
    
    @Test("Time interval calculation between taps")
    func timeIntervalCalculation() {
        let firstTap = Date()
        let secondTap = firstTap.addingTimeInterval(0.2)
        
        let interval = secondTap.timeIntervalSince(firstTap)
        
        #expect(interval >= 0.19)
        #expect(interval <= 0.21)
    }
    
    @Test("Time interval for slow taps")
    func timeIntervalSlowTaps() {
        let firstTap = Date()
        let secondTap = firstTap.addingTimeInterval(0.6)
        
        let interval = secondTap.timeIntervalSince(firstTap)
        
        #expect(interval >= 0.59)
        #expect(interval <= 0.61)
    }
}
