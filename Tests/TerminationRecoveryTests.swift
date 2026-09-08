import Testing
@testable import mrml

@MainActor
@Suite("Termination recovery")
struct TerminationRecoveryTests {
    @Test("Loss acknowledgment is explicit and cannot bypass a pending Quit")
    func explicitLossAcknowledgment() async {
        var replies: [Bool] = []
        var exits = 0
        let coordinator = TerminationCoordinator(suspend: {}, quiesce: { false }, restore: {},
            beforeExit: { exits += 1; return true })
        #expect(coordinator.begin { replies.append($0) })
        #expect(!coordinator.begin(allowLoss: true) { replies.append($0) })
        #expect(await waitUntil { replies == [false] })
        #expect(exits == 0 && coordinator.needsLossConfirmation)
        #expect(coordinator.begin(allowLoss: true) { replies.append($0) })
        #expect(await waitUntil { replies == [false, true] })
        #expect(exits == 1)
    }

    @Test("Failed Quit restores services, replies once, and permits a later Quit")
    func failedQuitRestoresAndCanRetry() async {
        var saved = false
        var events: [String] = []
        var replies: [Bool] = []
        let coordinator = TerminationCoordinator(
            suspend: { events.append("stop") }, quiesce: { saved },
            restore: { events.append("restore") }, beforeExit: { events.append("exit"); return true })
        #expect(coordinator.begin { replies.append($0) })
        #expect(!coordinator.begin { replies.append($0) })
        #expect(await waitUntil { !replies.isEmpty })
        #expect(replies == [false])
        #expect(events == ["stop", "restore"])
        #expect(!coordinator.isInFlight)
        #expect(coordinator.needsLossConfirmation)
        saved = true
        #expect(coordinator.begin { replies.append($0) })
        #expect(await waitUntil { replies.count == 2 })
        #expect(replies == [false, true])
        #expect(events == ["stop", "restore", "stop", "exit"])
    }
}
