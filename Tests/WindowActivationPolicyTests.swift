import AppKit
import Testing
@testable import mrml

@MainActor
private final class ApplicationPresenterSpy: ApplicationPresenting {
    private(set) var requestedPolicies: [NSApplication.ActivationPolicy] = []
    private(set) var activationCount = 0
    private let record: (String) -> Void

    init(record: @escaping (String) -> Void = { _ in }) {
        self.record = record
    }

    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        requestedPolicies.append(activationPolicy)
        record("policy")
        return true
    }

    func activate(ignoringOtherApps flag: Bool) {
        activationCount += 1
        record("activate")
    }
}

@Suite("Window Activation Policy Tests")
@MainActor
struct WindowActivationPolicyTests {
    @Test("Recovery selects Transcription and the exact model before showing as accessory")
    func recoverySelectsTranscriptionModelAndKeepsAccessoryPolicy() {
        var events: [String] = []
        let application = ApplicationPresenterSpy { events.append($0) }
        let route = SettingsRoute(selectedPage: .prompt)
        let modelID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        var selectedModels: [TranscriptionModelID] = []
        let controller = SettingsWindowController(
            application: application,
            route: route,
            selectModel: { selectedModelID in
                #expect(route.selectedPage == .transcription)
                selectedModels.append(selectedModelID)
                events.append("model")
            }
        )

        controller.showRecovery(for: modelID)

        #expect(route.selectedPage == .transcription)
        #expect(selectedModels == [modelID])
        #expect(events == ["model", "policy", "activate"])
        #expect(application.requestedPolicies == [.accessory])
        #expect(application.activationCount == 1)
    }

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
