import AppKit
import Testing
@testable import mrml

@MainActor
private final class ApplicationPresenterSpy: ApplicationPresenting {
    private(set) var requestedPolicies: [NSApplication.ActivationPolicy] = []
    private(set) var activationCount = 0

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        requestedPolicies.append(activationPolicy)
        return true
    }

    func activate(ignoringOtherApps flag: Bool) {
        activationCount += 1
    }
}

@Suite("Window Activation Policy Tests")
@MainActor
struct WindowActivationPolicyTests {
    @Test("Opening Settings keeps Murmeln menu-bar-only")
    func openingSettingsKeepsAccessoryPolicy() {
        let application = ApplicationPresenterSpy()
        let controller = SettingsWindowController(application: application)

        controller.show()

        #expect(application.requestedPolicies == [.accessory])
        #expect(application.activationCount == 1)
    }

    @Test("Closing Settings does not control process presentation")
    func closingSettingsDoesNotChangeActivationPolicy() {
        let application = ApplicationPresenterSpy()
        let controller = SettingsWindowController(application: application)

        controller.hide()

        #expect(application.requestedPolicies.isEmpty)
        #expect(application.activationCount == 0)
    }
}
