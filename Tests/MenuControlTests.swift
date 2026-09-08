import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Menu control routing")
struct MenuControlTests {
    @Test("Restart reaches the adaptor-owned delegate without looking up NSApp.delegate")
    func restartUsesOwnedDelegate() {
        _ = NSApplication.shared
        var terminationRequests = 0
        let delegate = AppDelegate(terminateApplication: { terminationRequests += 1 })
        let menu = MenuContent(appDelegate: delegate)

        menu.restartApp()

        #expect(terminationRequests == 1)
    }

    @Test("Repeated Restart requests cannot schedule more than one replacement")
    func repeatedRestartIsIgnored() {
        var terminationRequests = 0
        let delegate = AppDelegate(terminateApplication: { terminationRequests += 1 })

        delegate.requestRestart()
        delegate.requestRestart()

        #expect(terminationRequests == 1)
    }

    @Test("Quit anyway reaches the same adaptor-owned delegate")
    func lossConfirmationUsesOwnedDelegate() {
        _ = NSApplication.shared
        let delegate = LossConfirmationDelegate(terminateApplication: {})
        let menu = MenuContent(appDelegate: delegate)

        menu.confirmLossAndQuit()

        #expect(delegate.confirmations == 1)
    }
}

@MainActor
private final class LossConfirmationDelegate: AppDelegate {
    var confirmations = 0

    override func confirmLossAndQuit() {
        confirmations += 1
    }
}
