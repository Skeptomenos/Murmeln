import Foundation

@MainActor
enum RestartLaunchAwaiter {
    struct Candidate {
        let snapshot: @MainActor () -> RestartService.LaunchedApplication
        let requestTermination: @MainActor () -> Bool
    }

    enum Failure: Error, Equatable {
        case identityMismatch
        case notReady
        case exited
        case cleanupUnconfirmed
    }

    static func waitForReady(
        _ candidate: Candidate,
        expectedURL: URL,
        expectedIdentifier: String,
        currentPID: Int32,
        readinessChecks: Int = 50,
        cleanupChecks: Int = 20,
        pause: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .milliseconds(100)) }
    ) async throws -> RestartService.LaunchedApplication {
        let initial = candidate.snapshot()
        let candidatePID = initial.processIdentifier
        let matchesIdentity: @MainActor (RestartService.LaunchedApplication) -> Bool = { snapshot in
            snapshot.processIdentifier == candidatePID && candidatePID > 0 && candidatePID != currentPID
                && snapshot.bundleIdentifier == expectedIdentifier
                && snapshot.bundleURL?.standardizedFileURL.resolvingSymlinksInPath()
                    == expectedURL.standardizedFileURL.resolvingSymlinksInPath()
        }
        guard matchesIdentity(initial) else { throw Failure.identityMismatch }

        do {
            for check in 0..<max(1, readinessChecks) {
                try Task.checkCancellation()
                let snapshot = candidate.snapshot()
                if snapshot.isTerminated { throw Failure.exited }
                guard matchesIdentity(snapshot) else { throw Failure.identityMismatch }
                if snapshot.isFinishedLaunching { return snapshot }
                if check + 1 < readinessChecks { try await pause() }
            }
            throw Failure.notReady
        } catch {
            // Cleanup has its own bounded task so cancellation of the restart
            // cannot skip joining the exact candidate's graceful termination.
            let cleanup = Task { @MainActor in
                await stopCandidate(candidate, matchesIdentity: matchesIdentity, checks: cleanupChecks, pause: pause)
            }
            guard await cleanup.value else { throw Failure.cleanupUnconfirmed }
            throw error
        }
    }

    private static func stopCandidate(
        _ candidate: Candidate,
        matchesIdentity: @MainActor (RestartService.LaunchedApplication) -> Bool,
        checks: Int,
        pause: @MainActor () async throws -> Void
    ) async -> Bool {
        let initial = candidate.snapshot()
        if initial.isTerminated { return true }
        guard matchesIdentity(initial) else { return false }
        _ = candidate.requestTermination()
        for check in 0..<max(1, checks) {
            let snapshot = candidate.snapshot()
            if snapshot.isTerminated { return true }
            guard matchesIdentity(snapshot) else { return false }
            if check + 1 < checks {
                do { try await pause() }
                catch { return false }
            }
        }
        return false
    }
}
