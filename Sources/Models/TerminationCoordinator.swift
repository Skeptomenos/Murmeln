import Observation

@MainActor
@Observable
final class TerminationCoordinator {
    private(set) var isInFlight = false
    private(set) var needsLossConfirmation = false
    private let suspend: @MainActor () -> Void
    private let quiesce: @MainActor () async -> Bool
    private let restore: @MainActor () -> Void
    private let beforeExit: @MainActor () async -> Bool
    private var task: Task<Void, Never>?

    init(suspend: @escaping @MainActor () -> Void,
         quiesce: @escaping @MainActor () async -> Bool,
         restore: @escaping @MainActor () -> Void,
         beforeExit: @escaping @MainActor () async -> Bool = { true }) {
        self.suspend = suspend
        self.quiesce = quiesce
        self.restore = restore
        self.beforeExit = beforeExit
    }

    @discardableResult
    func begin(allowLoss: Bool = false, reply: @escaping @MainActor (Bool) -> Void) -> Bool {
        guard !isInFlight else { return false }
        isInFlight = true
        needsLossConfirmation = false
        suspend()
        task = Task { @MainActor in
            let saved = await quiesce()
            if !saved && !allowLoss {
                needsLossConfirmation = true
                isInFlight = false
                restore()
                reply(false)
                return
            }
            let canExit = await beforeExit()
            if !canExit {
                isInFlight = false
                restore()
            }
            reply(canExit)
        }
        return true
    }
}
