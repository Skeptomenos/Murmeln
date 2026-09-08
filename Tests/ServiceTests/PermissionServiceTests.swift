import Foundation
import Testing
@testable import mrml

@Suite("Permission Service Tests")
struct PermissionServiceTests {
    @Test("Permission status checks only the no-prompt preflight boundary")
    func permissionStatusUsesOnlyPreflight() {
        let calls = PermissionCallRecorder()
        let service = PermissionService(
            preflightPostEventAccess: {
                calls.recordPreflight()
                return false
            },
            requestPostEventAccess: {
                calls.recordRequest()
                return true
            }
        )

        #expect(service.hasPostEventAccess() == false)
        #expect(calls.snapshot == .init(preflight: 1, request: 0))
    }

    @Test("Explicit permission requests only the request boundary")
    func explicitPermissionRequestUsesOnlyRequest() {
        let calls = PermissionCallRecorder()
        let service = PermissionService(
            preflightPostEventAccess: {
                calls.recordPreflight()
                return false
            },
            requestPostEventAccess: {
                calls.recordRequest()
                return true
            }
        )

        #expect(service.requestPostEventAccess())
        #expect(calls.snapshot == .init(preflight: 0, request: 1))
    }

    @Test("Permission menu action requests access before opening Settings and refreshes actual permission", arguments: [true, false])
    @MainActor
    func permissionMenuActionOpensSettings(requestGranted: Bool) {
        let calls = PermissionCallRecorder()
        var openedURLs: [URL] = []
        let service = PermissionService(
            preflightPostEventAccess: {
                calls.recordPreflight()
                return false
            },
            requestPostEventAccess: {
                calls.recordRequest()
                return requestGranted
            },
            openURL: { calls.recordOpen(); openedURLs.append($0); return true }
        )
        let controller = PastePermissionController(permissionService: service)
        let menu = MenuContent(
            appDelegate: AppDelegate(terminateApplication: {}),
            permissionService: service,
            pastePermissionController: controller
        )

        menu.openAccessibilitySettings()

        #expect(openedURLs.map(\.absoluteString) == ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
        #expect(calls.snapshot == .init(preflight: 2, request: 1))
        #expect(calls.events == ["preflight", "request", "open", "preflight"])
        #expect(!controller.hasPostEventAccess)
    }

    @Test("Permission initialization and repeated refresh never request access or navigate")
    @MainActor
    func ordinaryRefreshUsesOnlyPreflight() {
        let calls = PermissionCallRecorder()
        let access = PermissionAccessState()
        let service = PermissionService(
            preflightPostEventAccess: { calls.recordPreflight(); return access.granted },
            requestPostEventAccess: { calls.recordRequest(); return true },
            openURL: { _ in calls.recordOpen(); return true }
        )
        let controller = PastePermissionController(permissionService: service)
        #expect(!controller.hasPostEventAccess)

        controller.refresh()
        #expect(!controller.hasPostEventAccess)
        access.granted = true
        controller.refresh()
        controller.refresh()

        #expect(controller.hasPostEventAccess)
        #expect(controller.navigationMessage == nil)
        #expect(calls.snapshot == .init(preflight: 4, request: 0))
        #expect(calls.events == ["preflight", "preflight", "preflight", "preflight"])
    }

    @Test("Settings URL rejection falls back to System Settings and keeps manual directions")
    @MainActor
    func settingsNavigationFallback() {
        let calls = PermissionCallRecorder()
        var openedURLs: [URL] = []
        let service = PermissionService(
            preflightPostEventAccess: { calls.recordPreflight(); return false },
            requestPostEventAccess: { calls.recordRequest(); return false },
            openURL: { url in
                calls.recordOpen()
                openedURLs.append(url)
                return url.isFileURL
            })
        let controller = PastePermissionController(permissionService: service)
        let menu = MenuContent(
            appDelegate: AppDelegate(terminateApplication: {}), permissionService: service,
            pastePermissionController: controller
        )

        menu.openAccessibilitySettings()

        #expect(openedURLs.count == 2)
        #expect(openedURLs.last?.path == "/System/Applications/System Settings.app")
        #expect(controller.navigationMessage?.contains("Privacy & Security → Accessibility") == true)
        #expect(controller.navigationMessage?.contains("could not be opened") == false)
        #expect(!controller.hasPostEventAccess)
        #expect(calls.events == ["preflight", "request", "open", "open", "preflight"])
    }

    @Test("A failed Settings launch remains actionable and return refresh uses preflight")
    @MainActor
    func failedNavigationAndPermissionRefresh() {
        let calls = PermissionCallRecorder()
        let access = PermissionAccessState()
        let service = PermissionService(preflightPostEventAccess: { calls.recordPreflight(); return access.granted },
            requestPostEventAccess: { calls.recordRequest(); return false },
            openURL: { _ in calls.recordOpen(); return false })
        let controller = PastePermissionController(permissionService: service)
        let menu = MenuContent(
            appDelegate: AppDelegate(terminateApplication: {}), permissionService: service,
            pastePermissionController: controller
        )

        menu.openAccessibilitySettings()

        #expect(controller.navigationMessage?.contains("could not be opened") == true)
        #expect(!controller.hasPostEventAccess)
        #expect(calls.events == ["preflight", "request", "open", "open", "preflight"])
        access.granted = true
        controller.refresh()
        #expect(controller.hasPostEventAccess)
        #expect(controller.navigationMessage == nil)
        #expect(calls.snapshot == .init(preflight: 3, request: 1))
        #expect(calls.events == ["preflight", "request", "open", "open", "preflight", "preflight"])
    }
}

// The injected C permission boundary is synchronous and Sendable; this lock
// keeps its test state safe if the boundary moves off the main actor.
private final class PermissionAccessState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var granted: Bool {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class PermissionCallRecorder: @unchecked Sendable {
    struct Snapshot: Equatable {
        let preflight: Int
        let request: Int
    }

    private let lock = NSLock()
    private var preflightCount = 0
    private var requestCount = 0
    private var recordedEvents: [String] = []

    var events: [String] {
        lock.withLock { recordedEvents }
    }

    var snapshot: Snapshot {
        lock.withLock {
            Snapshot(preflight: preflightCount, request: requestCount)
        }
    }

    func recordPreflight() {
        lock.withLock {
            preflightCount += 1
            recordedEvents.append("preflight")
        }
    }

    func recordRequest() {
        lock.withLock {
            requestCount += 1
            recordedEvents.append("request")
        }
    }

    func recordOpen() {
        lock.withLock { recordedEvents.append("open") }
    }
}
