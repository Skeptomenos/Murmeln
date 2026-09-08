import AppKit

@MainActor
final class RestartService {
    struct LaunchedApplication: Sendable {
        let processIdentifier: Int32
        let bundleIdentifier: String?
        let bundleURL: URL?
        let isFinishedLaunching: Bool
        let isTerminated: Bool
    }

    private let bundleURL: URL
    private let bundleIdentifier: String
    private let currentProcessIdentifier: Int32
    private let launch: @MainActor (URL) async throws -> LaunchedApplication
    private let otherInstanceIsRunning: @MainActor (String, Int32) -> Bool
    private var isLaunching = false
    private var didLaunch = false
    private(set) var failureMessage: String?
    private(set) var canResumeCurrentApp = true

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String = AppIdentity.bundleIdentifier,
        currentProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        otherInstanceIsRunning: @escaping @MainActor (String, Int32) -> Bool = { identifier, currentPID in
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains { !$0.isTerminated && $0.processIdentifier != currentPID }
        },
        launch: @escaping @MainActor (URL) async throws -> LaunchedApplication = { url in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            configuration.allowsRunningApplicationSubstitution = false
            configuration.activates = false
            configuration.addsToRecentItems = false
            configuration.promptsUserIfNeeded = false
            configuration.environment = relaunchEnvironment(from: ProcessInfo.processInfo.environment)
            let application = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            let candidate = RestartLaunchAwaiter.Candidate(snapshot: {
                LaunchedApplication(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: application.bundleIdentifier,
                    bundleURL: application.bundleURL,
                    isFinishedLaunching: application.isFinishedLaunching,
                    isTerminated: application.isTerminated
                )
            }, requestTermination: { application.terminate() })
            return try await RestartLaunchAwaiter.waitForReady(candidate, expectedURL: url,
                expectedIdentifier: AppIdentity.bundleIdentifier,
                currentPID: ProcessInfo.processInfo.processIdentifier)
        }
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.currentProcessIdentifier = currentProcessIdentifier
        self.otherInstanceIsRunning = otherInstanceIsRunning
        self.launch = launch
    }

    func launchReplacement() async -> Bool {
        if didLaunch { return true }
        guard !isLaunching else { return false }
        isLaunching = true
        defer { isLaunching = false }
        failureMessage = nil
        guard !otherInstanceIsRunning(bundleIdentifier, currentProcessIdentifier) else {
            failureMessage = "Another copy of \(AppIdentity.menuBarTitle) is running. Quit that copy before restarting."
            return false
        }
        canResumeCurrentApp = true
        do {
            let replacement = try await launch(bundleURL)
            guard replacement.processIdentifier > 0,
                  replacement.processIdentifier != currentProcessIdentifier,
                  replacement.bundleIdentifier == bundleIdentifier,
                  let replacementURL = replacement.bundleURL,
                  replacementURL.standardizedFileURL.resolvingSymlinksInPath()
                    == bundleURL.standardizedFileURL.resolvingSymlinksInPath(),
                  replacement.isFinishedLaunching,
                  !replacement.isTerminated else {
                failureMessage = "Murmeln could not verify the restarted app. The current app is still available."
                return false
            }
            didLaunch = true
            return true
        } catch {
            if error as? RestartLaunchAwaiter.Failure == .cleanupUnconfirmed {
                canResumeCurrentApp = false
                failureMessage = "Dictation is paused. Quit the other \(AppIdentity.menuBarTitle) copy, then restart this app."
            } else {
                failureMessage = "Murmeln could not restart. The current app is still available. Please try again."
            }
            return false
        }
    }

    static func relaunchEnvironment(from environment: [String: String]) -> [String: String] {
        var result = environment
        result.removeValue(forKey: DevDeliveryDiagnostic.environmentKey)
        result.removeValue(forKey: DevDeliveryDiagnosticRunner.runIDEnvironmentKey)
        return result
    }

    func resumeCurrentAppIfSafe(_ resume: @MainActor () -> Void) {
        if canResumeCurrentApp { resume() }
    }
}
