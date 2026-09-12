/// User-visible result of one update check.
enum UpdateCheckOutcome: Equatable, Sendable {
    case updateAvailable
    case upToDate
    case failed
    case disabled
}
