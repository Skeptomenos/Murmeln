import AppKit
import Carbon.HIToolbox
import Testing
@testable import mrml

@Suite("HotkeyService Tests", .serialized)
struct HotkeyServiceTests {
    @Test("Cold lock captures its ID before recording and lock UI callbacks")
    @MainActor
    func coldLockCapturesBeforeCallbacks() {
        let service = makeAdmittedService()
        service.doubleTapThreshold = 1
        var events: [String] = []
        service.captureIDFactory = { events.append("capture"); return "cold-lock" }
        service.onKeyDown = { id in events.append("begin:\(id ?? "nil")"); return true }
        service.onLockEngaged = { events.append("locked") }

        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        #expect(events == ["capture", "begin:cold-lock", "locked"])
        service.stop()
    }

    @Test("Fn to lock preserves its original capture ID without sampling again")
    @MainActor
    func fnToLockReusesCapture() {
        let service = makeAdmittedService()
        service.holdThreshold = 10
        service.doubleTapThreshold = 1
        var samples = 0
        var events: [String] = []
        service.captureIDFactory = { samples += 1; return "held-capture" }
        service.onKeyDown = { id in events.append("begin:\(id ?? "nil")"); return true }
        service.onLockEngaged = { events.append("locked") }

        service.handleModifierEvent(fnEvent(isPressed: true))
        performRightOptionTap(on: service, holdingFn: true)
        performRightOptionTap(on: service, holdingFn: true)

        #expect(samples == 1)
        #expect(events == ["begin:held-capture", "locked"])
        service.stop()
    }

    @Test("Rejected Fn and lock admission cannot show listening or locked UI")
    @MainActor
    func deniedAdmissionHasNoRecordingCallbacks() {
        let service = makeAdmittedService()
        service.doubleTapThreshold = 1
        var callbacks: [String] = []
        service.captureIDFactory = { nil }
        service.onHoldStarted = { callbacks.append("waiting") }
        service.onKeyDown = { _ in callbacks.append("listening"); return false }
        service.onLockEngaged = { callbacks.append("locked") }

        service.handleModifierEvent(fnEvent(isPressed: true))
        service.handleModifierEvent(fnEvent(isPressed: false))
        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        #expect(callbacks.isEmpty)
        service.stop()
    }

    @Test("A rejected threshold callback cannot stop an unrelated recording on Fn release")
    @MainActor
    func rejectedThresholdDoesNotCommitRecordingState() async {
        let service = makeAdmittedService()
        service.holdThreshold = 0
        var attempts = 0
        var stops = 0
        service.captureIDFactory = { "rejected-capture" }
        service.onKeyDown = { _ in attempts += 1; return false }
        service.onKeyUp = { stops += 1 }
        service.handleModifierEvent(fnEvent(isPressed: true))
        #expect(await waitUntil { attempts == 1 })

        service.handleModifierEvent(fnEvent(isPressed: false))

        #expect(stops == 0)
        service.stop()
    }

    @Test("A stale hold ID rejected at lock admission cannot commit locked UI")
    @MainActor
    func rejectedLockCallbackDoesNotCommitState() {
        let service = makeAdmittedService()
        service.holdThreshold = 10
        service.doubleTapThreshold = 1
        var locks = 0
        var stops = 0
        service.captureIDFactory = { "stale-hold" }
        service.onKeyDown = { _ in false }
        service.onLockEngaged = { locks += 1 }
        service.onKeyUp = { stops += 1 }

        service.handleModifierEvent(fnEvent(isPressed: true))
        performRightOptionTap(on: service, holdingFn: true)
        performRightOptionTap(on: service, holdingFn: true)
        service.handleModifierEvent(fnEvent(isPressed: false))

        #expect(locks == 0)
        #expect(stops == 0)
        service.stop()
    }

    @Test("Hold threshold default is 400ms")
    @MainActor
    func holdThresholdDefault() {
        let service = makeAdmittedService()

        #expect(service.holdThreshold == 0.4)
    }

    @Test("Double-tap threshold default is 400ms")
    @MainActor
    func doubleTapThresholdDefault() {
        let service = makeAdmittedService()

        #expect(service.doubleTapThreshold == 0.4)
    }

    @Test("Quick Fn tap cancels pending hold without starting recording")
    @MainActor
    func fnTapBeforeThresholdCancelsHold() async throws {
        let service = makeAdmittedService()

        service.holdThreshold = 0.05

        var holdStartedCount = 0
        var holdCancelledCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onHoldCancelled = { holdCancelledCount += 1 }
        service.onKeyDown = { _ in keyDownCount += 1; return true }
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
        let service = makeAdmittedService()

        service.holdThreshold = 0.02

        var holdStartedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onKeyDown = { _ in keyDownCount += 1; return true }
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
        let service = makeAdmittedService()

        service.doubleTapThreshold = 1.0

        var lockEngagedCount = 0
        var keyDownCount = 0
        service.onLockEngaged = { lockEngagedCount += 1 }
        service.onKeyDown = { _ in keyDownCount += 1; return true }

        performRightOptionTap(on: service)
        performRightOptionTap(on: service)

        #expect(lockEngagedCount == 1)
        #expect(keyDownCount == 1)
    }

    @Test("Right Option tap while locked disengages lock and stops recording")
    @MainActor
    func rightOptionTapWhileLockedDisengagesAndStops() {
        let service = makeAdmittedService()

        service.doubleTapThreshold = 1.0

        var lockEngagedCount = 0
        var lockDisengagedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onLockEngaged = { lockEngagedCount += 1 }
        service.onLockDisengaged = { lockDisengagedCount += 1 }
        service.onKeyDown = { _ in keyDownCount += 1; return true }
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
        let service = makeAdmittedService()

        service.doubleTapThreshold = 1.0
        service.holdThreshold = 0.02

        var holdStartedCount = 0
        var keyDownCount = 0
        var keyUpCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onKeyDown = { _ in keyDownCount += 1; return true }
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

    @Test("Start installs global and local monitors that share the modifier state machine")
    @MainActor
    func startInstallsGlobalAndLocalMonitors() throws {
        let monitors = FakeMonitorSystem()
        var diagnostics: [String] = []
        let service = HotkeyService(
            monitorClient: monitors.client,
            diagnostics: { event, _, _ in diagnostics.append(event) }
        )
        service.captureIDFactory = { "test-capture" }
        service.holdThreshold = 10
        var holdStartedCount = 0
        var holdCancelledCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onHoldCancelled = { holdCancelledCount += 1 }

        #expect(service.start())
        #expect(monitors.globalInstallCount == 1)
        #expect(monitors.localInstallCount == 1)

        let pressed = try #require(flagsChangedEvent(isPressed: true))
        let released = try #require(flagsChangedEvent(isPressed: false))
        monitors.globalHandler?(pressed)
        let returned = monitors.localHandler?(released)

        #expect(holdStartedCount == 1)
        #expect(holdCancelledCount == 1)
        #expect(returned === released)
        #expect(diagnostics.filter { $0 == "hotkey.service_started" }.count == 1)

        service.stop()
        #expect(monitors.removedTokenIDs.count == 2)
    }

    @Test("A local-install failure rolls back global and retry installs one complete pair")
    @MainActor
    func localInstallFailureRollsBackAndRetries() {
        let monitors = FakeMonitorSystem()
        monitors.localInstallSucceeds = false
        var diagnostics: [DiagnosticRecord] = []
        var failures: [HotkeyService.MonitorStartFailure] = []
        let service = HotkeyService(
            monitorClient: monitors.client,
            diagnostics: { event, _, metadata in
                diagnostics.append(DiagnosticRecord(event: event, metadata: metadata))
            }
        )
        service.onMonitorStartFailure = { failures.append($0) }

        #expect(!service.start())
        #expect(monitors.globalInstallCount == 1)
        #expect(monitors.localInstallCount == 1)
        #expect(monitors.removedTokenIDs.count == 1)
        #expect(failures == [.localMonitorUnavailable])
        #expect(diagnostics.first == DiagnosticRecord(
            event: "hotkey.monitor_start_failed",
            metadata: [
                "global_installed": "true",
                "local_installed": "false",
                "failure": "local_monitor_unavailable"
            ]
        ))
        #expect(!diagnostics.contains { $0.event == "hotkey.service_started" })

        service.stop()
        #expect(monitors.removedTokenIDs.count == 1)

        monitors.localInstallSucceeds = true
        #expect(service.start())
        #expect(monitors.globalInstallCount == 2)
        #expect(monitors.localInstallCount == 2)
        #expect(diagnostics.filter { $0.event == "hotkey.service_started" }.count == 1)

        service.stop()
        #expect(monitors.removedTokenIDs.count == 3)
    }

    @Test("A global-install failure rolls back local and retry installs one complete pair")
    @MainActor
    func globalInstallFailureRollsBackAndRetries() {
        let monitors = FakeMonitorSystem()
        monitors.globalInstallSucceeds = false
        var diagnostics: [DiagnosticRecord] = []
        var failures: [HotkeyService.MonitorStartFailure] = []
        let service = HotkeyService(
            monitorClient: monitors.client,
            diagnostics: { event, _, metadata in
                diagnostics.append(DiagnosticRecord(event: event, metadata: metadata))
            }
        )
        service.onMonitorStartFailure = { failures.append($0) }

        #expect(!service.start())
        #expect(monitors.globalInstallCount == 1)
        #expect(monitors.localInstallCount == 1)
        #expect(monitors.removedTokenIDs.count == 1)
        #expect(failures == [.globalMonitorUnavailable])
        #expect(diagnostics.first == DiagnosticRecord(
            event: "hotkey.monitor_start_failed",
            metadata: [
                "global_installed": "false",
                "local_installed": "true",
                "failure": "global_monitor_unavailable"
            ]
        ))
        #expect(!diagnostics.contains { $0.event == "hotkey.service_started" })

        service.stop()
        #expect(monitors.removedTokenIDs.count == 1)

        monitors.globalInstallSucceeds = true
        #expect(service.start())
        #expect(monitors.globalInstallCount == 2)
        #expect(monitors.localInstallCount == 2)
        #expect(diagnostics.filter { $0.event == "hotkey.service_started" }.count == 1)

        service.stop()
        #expect(monitors.removedTokenIDs.count == 3)
    }

    @Test("Repeated start replaces the complete monitor pair without duplicate handling")
    @MainActor
    func repeatedStartReplacesMonitorPair() throws {
        let monitors = FakeMonitorSystem()
        let service = HotkeyService(monitorClient: monitors.client)
        service.captureIDFactory = { "test-capture" }
        service.holdThreshold = 10
        var holdStartedCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }

        #expect(service.start())
        #expect(service.start())

        #expect(monitors.globalInstallCount == 2)
        #expect(monitors.localInstallCount == 2)
        #expect(monitors.removedTokenIDs.count == 2)

        let pressed = try #require(flagsChangedEvent(isPressed: true))
        monitors.globalHandler?(pressed)
        #expect(holdStartedCount == 1)

        service.stop()
        #expect(monitors.removedTokenIDs.count == 4)
    }

    @Test("Local release after a global Fn press reaches the same recording state")
    @MainActor
    func localReleaseAfterGlobalPress() throws {
        var globalHandler: HotkeyMonitorClient.GlobalHandler?
        var localHandler: HotkeyMonitorClient.LocalHandler?
        var removedCount = 0
        let client = HotkeyMonitorClient(
            installGlobalFlagsMonitor: { handler in
                globalHandler = handler
                return NSObject()
            },
            installLocalFlagsMonitor: { handler in
                localHandler = handler
                return NSObject()
            },
            removeMonitor: { _ in removedCount += 1 }
        )
        let service = HotkeyService(monitorClient: client)
        service.captureIDFactory = { "test-capture" }
        service.captureIDFactory = { "test-capture" }
        service.holdThreshold = 10
        var holdStartedCount = 0
        var holdCancelledCount = 0
        service.onHoldStarted = { holdStartedCount += 1 }
        service.onHoldCancelled = { holdCancelledCount += 1 }
        service.start()

        let pressed = try #require(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: [.function],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(kVK_Function)
        ))
        let released = try #require(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false,
            keyCode: UInt16(kVK_Function)
        ))
        globalHandler?(pressed)
        let returned = localHandler?(released)

        #expect(holdStartedCount == 1)
        #expect(holdCancelledCount == 1)
        #expect(returned === released)
        service.stop()
        #expect(removedCount == 2)
    }

    @MainActor
    private func makeAdmittedService() -> HotkeyService {
        let service = HotkeyService()
        service.captureIDFactory = { "test-capture" }
        return service
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

    private struct DiagnosticRecord: Equatable {
        let event: String
        let metadata: [String: String]
    }

    @MainActor
    private func flagsChangedEvent(isPressed: Bool) -> NSEvent? {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: isPressed ? [.function] : [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(kVK_Function)
        )
    }

    @MainActor
    private func performRightOptionTap(on service: HotkeyService, holdingFn: Bool = false) {
        if holdingFn {
            service.handleModifierEvent(HotkeyModifierEvent(keyCode: UInt16(kVK_RightOption), modifierFlags: [.function, .option]))
            service.handleModifierEvent(HotkeyModifierEvent(keyCode: UInt16(kVK_RightOption), modifierFlags: [.function]))
        } else {
            service.handleModifierEvent(rightOptionEvent(isPressed: true))
            service.handleModifierEvent(rightOptionEvent(isPressed: false))
        }
    }

    @MainActor
    private final class FakeMonitorSystem {
        var globalInstallSucceeds = true
        var localInstallSucceeds = true
        private(set) var globalInstallCount = 0
        private(set) var localInstallCount = 0
        private(set) var removedTokenIDs: [ObjectIdentifier] = []
        private(set) var globalHandler: HotkeyMonitorClient.GlobalHandler?
        private(set) var localHandler: HotkeyMonitorClient.LocalHandler?

        var client: HotkeyMonitorClient {
            HotkeyMonitorClient(
                installGlobalFlagsMonitor: { [weak self] handler in
                    guard let self else { return nil }
                    globalInstallCount += 1
                    globalHandler = handler
                    return globalInstallSucceeds ? NSObject() : nil
                },
                installLocalFlagsMonitor: { [weak self] handler in
                    guard let self else { return nil }
                    localInstallCount += 1
                    localHandler = handler
                    return localInstallSucceeds ? NSObject() : nil
                },
                removeMonitor: { [weak self] token in
                    self?.removedTokenIDs.append(ObjectIdentifier(token as AnyObject))
                }
            )
        }
    }
}
