import AppKit
import Carbon.HIToolbox
import Testing
@testable import mrml

@Suite("HotkeyService Tests", .serialized)
struct HotkeyServiceTests {

    @Test("Hold threshold default is 400ms")
    @MainActor
    func holdThresholdDefault() {
        let service = HotkeyService.shared
        reset(service)

        #expect(service.holdThreshold == 0.4)
    }

    @Test("Double-tap threshold default is 400ms")
    @MainActor
    func doubleTapThresholdDefault() {
        let service = HotkeyService.shared
        reset(service)

        #expect(service.doubleTapThreshold == 0.4)
    }

    @Test("Quick Fn tap cancels pending hold without starting recording")
    @MainActor
    func fnTapBeforeThresholdCancelsHold() async throws {
        let service = HotkeyService.shared
        reset(service)
        defer { reset(service) }

        service.holdThreshold = 0.05

        var holdStartedCount = 0
        var holdCancelledCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onHoldCancelled = { holdCancelledCount += 1 }
        service.onKeyDown = { keyDownCount += 1 }
        service.onKeyUp = { keyUpCount += 1 }

        service.handleModifierEvent(fnEvent(isPressed: true))
        service.handleModifierEvent(fnEvent(isPressed: false))
        try await Task.sleep(for: .milliseconds(80))

        #expect(holdStartedCount == 1)
        #expect(holdCancelledCount == 1)
        #expect(keyDownCount == 0)
        #expect(keyUpCount == 0)
    }

    @Test("Fn hold starts recording after threshold and release stops it")
    @MainActor
    func fnHoldStartsRecordingAfterThresholdAndReleaseStopsIt() async throws {
        let service = HotkeyService.shared
        reset(service)
        defer { reset(service) }

        service.holdThreshold = 0.02

        var holdStartedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onKeyDown = { keyDownCount += 1 }
        service.onKeyUp = { keyUpCount += 1 }

        service.handleModifierEvent(fnEvent(isPressed: true))
        try await Task.sleep(for: .milliseconds(60))
        service.handleModifierEvent(fnEvent(isPressed: false))

        #expect(holdStartedCount == 1)
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    @Test("Right Option double tap engages lock mode")
    @MainActor
    func rightOptionDoubleTapEngagesLock() {
        let service = HotkeyService.shared
        reset(service)
        defer { reset(service) }

        service.doubleTapThreshold = 1.0

        var lockEngagedCount = 0
        var keyDownCount = 0
        service.onLockEngaged = { lockEngagedCount += 1 }
        service.onKeyDown = { keyDownCount += 1 }

        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        #expect(lockEngagedCount == 1)
        #expect(keyDownCount == 1)
    }

    @Test("Right Option tap while locked disengages lock and stops recording")
    @MainActor
    func rightOptionTapWhileLockedDisengagesAndStops() {
        let service = HotkeyService.shared
        reset(service)
        defer { reset(service) }

        service.doubleTapThreshold = 1.0

        var lockEngagedCount = 0
        var lockDisengagedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onLockEngaged = { lockEngagedCount += 1 }
        service.onLockDisengaged = { lockDisengagedCount += 1 }
        service.onKeyDown = { keyDownCount += 1 }
        service.onKeyUp = { keyUpCount += 1 }

        performRightOptionTap(on: service)
        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        #expect(lockEngagedCount == 1)
        #expect(lockDisengagedCount == 1)
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 1)
    }

    @Test("Fn press is ignored while lock mode is active")
    @MainActor
    func fnPressIgnoredWhileLocked() async throws {
        let service = HotkeyService.shared
        reset(service)
        defer { reset(service) }

        service.doubleTapThreshold = 1.0
        service.holdThreshold = 0.02

        var holdStartedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onKeyDown = { keyDownCount += 1 }
        service.onKeyUp = { keyUpCount += 1 }

        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        service.handleModifierEvent(fnEvent(isPressed: true))
        try await Task.sleep(for: .milliseconds(60))
        service.handleModifierEvent(fnEvent(isPressed: false))

        #expect(holdStartedCount == 0)
        #expect(keyDownCount == 1)
        #expect(keyUpCount == 0)
    }

    @MainActor
    private func reset(_ service: HotkeyService) {
        service.stop(reason: .manualStop)
        service.holdThreshold = 0.4
        service.doubleTapThreshold = 0.4
        service.onKeyDown = nil
        service.onKeyUp = nil
        service.onHoldStarted = nil
        service.onHoldCancelled = nil
        service.onLockEngaged = nil
        service.onLockDisengaged = nil
        service.captureIDFactory = nil
    }

    private func fnEvent(isPressed: Bool) -> HotkeyModifierEvent {
        HotkeyModifierEvent(
            keyCode: UInt16(kVK_Function),
            modifierFlags: isPressed ? [.function] : []
        )
    }

    private func rightOptionEvent(isPressed: Bool) -> HotkeyModifierEvent {
        HotkeyModifierEvent(
            keyCode: UInt16(kVK_RightOption),
            modifierFlags: isPressed ? [.option] : []
        )
    }

    @MainActor
    private func performRightOptionTap(on service: HotkeyService) {
        service.handleModifierEvent(rightOptionEvent(isPressed: true))
        service.handleModifierEvent(rightOptionEvent(isPressed: false))
    }
}
