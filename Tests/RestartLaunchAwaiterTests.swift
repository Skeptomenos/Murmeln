import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("Restart readiness and cleanup")
struct RestartLaunchAwaiterTests {
    private let appURL = URL(fileURLWithPath: "/tmp/Murmeln Dev.app")
    private let identifier = "com.mrml.app.dev"

    @Test("A returned process may finish launch only after the workspace callback")
    func awaitsLateReadiness() async throws {
        let state = CandidateState()
        var pauses = 0
        let receipt = try await RestartLaunchAwaiter.waitForReady(state.candidate, expectedURL: appURL,
            expectedIdentifier: identifier, currentPID: 10, readinessChecks: 3, cleanupChecks: 2,
            pause: { pauses += 1; state.finished = true })

        #expect(receipt.isFinishedLaunching)
        #expect(pauses == 1)
        #expect(state.terminationRequests == 0)
    }

    @Test("Readiness timeout joins graceful cleanup before restoring the old process")
    func timeoutCleansOwnedCandidate() async {
        let state = CandidateState()
        do {
            _ = try await RestartLaunchAwaiter.waitForReady(state.candidate, expectedURL: appURL,
                expectedIdentifier: identifier, currentPID: 10, readinessChecks: 2, cleanupChecks: 2,
                pause: { if state.terminationRequests > 0 { state.terminated = true } })
            Issue.record("An unready replacement must not permit old-process exit")
        } catch {
            #expect(error as? RestartLaunchAwaiter.Failure == .notReady)
        }
        #expect(state.terminationRequests == 1)
        #expect(state.terminated)
    }

    @Test("Cancellation still joins cleanup of the exact newly launched process")
    func cancellationCleansOwnedCandidate() async {
        let state = CandidateState()
        do {
            _ = try await RestartLaunchAwaiter.waitForReady(state.candidate, expectedURL: appURL,
                expectedIdentifier: identifier, currentPID: 10, readinessChecks: 2, cleanupChecks: 2,
                pause: {
                    if state.terminationRequests == 0 { throw CancellationError() }
                    state.terminated = true
                })
            Issue.record("Cancelled restart must not permit old-process exit")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(state.terminationRequests == 1)
        #expect(state.terminated)
    }

    @Test("An identity mismatch is never terminated")
    func neverCleansAnotherApplication() async {
        let state = CandidateState()
        state.bundleIdentifier = "com.mrml.app"
        state.finished = true
        do {
            _ = try await RestartLaunchAwaiter.waitForReady(state.candidate, expectedURL: appURL,
                expectedIdentifier: identifier, currentPID: 10, readinessChecks: 2, cleanupChecks: 2,
                pause: {})
            Issue.record("A different app must not become the restart replacement")
        } catch {
            #expect(error as? RestartLaunchAwaiter.Failure == .identityMismatch)
        }
        #expect(state.terminationRequests == 0)
    }

    @Test("Failed cleanup keeps old capture suspended instead of enabling two monitors")
    func failedCleanupKeepsOldCaptureSuspended() async {
        let state = CandidateState()
        state.acceptsTermination = false
        let service = RestartService(bundleURL: appURL, bundleIdentifier: identifier, currentProcessIdentifier: 10,
            otherInstanceIsRunning: { _, _ in false }, launch: { _ in
                try await RestartLaunchAwaiter.waitForReady(state.candidate, expectedURL: appURL,
                    expectedIdentifier: identifier, currentPID: 10, readinessChecks: 1, cleanupChecks: 1,
                    pause: {})
            })
        var monitorResumes = 0
        var replies: [Bool] = []
        let coordinator = TerminationCoordinator(suspend: {}, quiesce: { true },
            restore: { service.resumeCurrentAppIfSafe { monitorResumes += 1 } },
            beforeExit: { await service.launchReplacement() })

        #expect(coordinator.begin { replies.append($0) })
        #expect(await waitUntil { replies == [false] })
        #expect(state.terminationRequests == 1)
        #expect(monitorResumes == 0)
        #expect(!service.canResumeCurrentApp)
        #expect(service.failureMessage?.contains("paused") == true)
    }
}

@MainActor
private final class CandidateState {
    var finished = false
    var terminated = false
    var bundleIdentifier = "com.mrml.app.dev"
    var acceptsTermination = true
    var terminationRequests = 0

    var candidate: RestartLaunchAwaiter.Candidate {
        .init(snapshot: { [self] in
            .init(processIdentifier: 11, bundleIdentifier: bundleIdentifier,
                bundleURL: URL(fileURLWithPath: "/tmp/Murmeln Dev.app"),
                isFinishedLaunching: finished, isTerminated: terminated)
        }, requestTermination: { [self] in
            terminationRequests += 1
            return acceptsTermination
        })
    }
}
