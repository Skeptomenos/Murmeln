import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Verified application restart")
struct RestartServiceTests {
    private let appURL = URL(fileURLWithPath: "/tmp/Murmeln Dev.app")
    private let identifier = "com.mrml.app.dev"

    @Test("Restart cannot replay a one-shot delivery probe")
    func removesOneShotDiagnosticEnvironment() {
        let environment = RestartService.relaunchEnvironment(from: [
            "MURMELN_DEV_DELIVERY_PROBE": "1",
            "MURMELN_DEV_DELIVERY_PROBE_RUN_ID": "arbitrary-run-id",
            "MURMELN_PASTE_DIAGNOSTIC_TRIGGER": "1",
            "LANG": "de_DE.UTF-8"
        ])

        #expect(environment["MURMELN_DEV_DELIVERY_PROBE"] == nil)
        #expect(environment["MURMELN_DEV_DELIVERY_PROBE_RUN_ID"] == nil)
        #expect(environment["MURMELN_PASTE_DIAGNOSTIC_TRIGGER"] == "1")
        #expect(environment["LANG"] == "de_DE.UTF-8")
    }

    private func receipt(
        pid: Int32 = 11,
        bundleIdentifier: String? = "com.mrml.app.dev",
        bundleURL: URL? = URL(fileURLWithPath: "/tmp/Murmeln Dev.app"),
        finished: Bool = true,
        terminated: Bool = false
    ) -> RestartService.LaunchedApplication {
        .init(processIdentifier: pid, bundleIdentifier: bundleIdentifier, bundleURL: bundleURL,
            isFinishedLaunching: finished, isTerminated: terminated)
    }

    @Test("Launch acceptance cannot stand in for a verified replacement process")
    func rejectsUnverifiedReplacement() async {
        let invalidReceipts = [
            receipt(pid: 10),
            receipt(pid: 0),
            receipt(bundleIdentifier: "com.mrml.app"),
            receipt(bundleIdentifier: nil),
            receipt(bundleURL: URL(fileURLWithPath: "/tmp/Other/Murmeln Dev.app")),
            receipt(bundleURL: nil),
            receipt(finished: false),
            receipt(terminated: true)
        ]
        for invalidReceipt in invalidReceipts {
            let service = RestartService(bundleURL: appURL, bundleIdentifier: identifier, currentProcessIdentifier: 10,
                otherInstanceIsRunning: { _, _ in false }, launch: { _ in invalidReceipt })
            #expect(await !service.launchReplacement())
            #expect(service.failureMessage != nil)
        }
    }

    @Test("An existing second instance prevents a third launch")
    func refusesDuplicateInstance() async {
        var launches = 0
        let service = RestartService(bundleURL: appURL, bundleIdentifier: identifier, currentProcessIdentifier: 10,
            otherInstanceIsRunning: { _, _ in true }, launch: { _ in
                launches += 1
                return receipt()
            })

        #expect(await !service.launchReplacement())
        #expect(launches == 0)
        #expect(service.failureMessage?.contains("Another copy") == true)
    }

    @Test("Restart waits for launch completion and creates only one replacement")
    func waitsForReplacementAndCoalescesRequests() async {
        let suspended = SuspendedRestartLaunch()
        let service = RestartService(bundleURL: appURL, bundleIdentifier: identifier, currentProcessIdentifier: 10,
            otherInstanceIsRunning: { _, _ in false }, launch: { _ in try await suspended.launch() })
        var completed = false
        let first = Task { let result = await service.launchReplacement(); completed = true; return result }
        #expect(await waitUntil { suspended.continuation != nil })
        #expect(!completed)
        #expect(await !service.launchReplacement())
        #expect(suspended.launchCount == 1)

        suspended.continuation?.resume(returning: receipt())
        suspended.continuation = nil
        #expect(await first.value)
        #expect(await service.launchReplacement())
        #expect(suspended.launchCount == 1)
    }

    @Test("Launch failure cancels termination and restores the old app exactly once")
    func failedLaunchRestoresCurrentApp() async {
        var launches = 0
        var events: [String] = []
        var replies: [Bool] = []
        let service = RestartService(bundleURL: appURL, bundleIdentifier: identifier, currentProcessIdentifier: 10,
            otherInstanceIsRunning: { _, _ in false }, launch: { _ in
                launches += 1
                if launches == 1 { throw CocoaError(.fileNoSuchFile) }
                return receipt()
            })
        let coordinator = TerminationCoordinator(suspend: { events.append("suspend") }, quiesce: { true },
            restore: { events.append("restore") }, beforeExit: { await service.launchReplacement() })

        #expect(coordinator.begin { replies.append($0) })
        #expect(await waitUntil { replies == [false] })
        #expect(events == ["suspend", "restore"])
        #expect(!coordinator.isInFlight)
        #expect(!coordinator.needsLossConfirmation)
        #expect(service.failureMessage != nil)

        #expect(coordinator.begin { replies.append($0) })
        #expect(await waitUntil { replies == [false, true] })
        #expect(events == ["suspend", "restore", "suspend"])
        #expect(launches == 2)
    }
}

@MainActor
private final class SuspendedRestartLaunch {
    var launchCount = 0
    var continuation: CheckedContinuation<RestartService.LaunchedApplication, any Error>?

    func launch() async throws -> RestartService.LaunchedApplication {
        launchCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
