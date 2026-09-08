@MainActor
final class UnverifiedPasteTarget: PasteTargetChecking {
    private let reason: PasteTargetInvalidationReason

    init(reason: PasteTargetInvalidationReason = .initialCaptureUnverifiable) {
        self.reason = reason
    }

    func isStillValid() -> Bool { invalidationReason() == nil }
    func invalidationReason() -> PasteTargetInvalidationReason? { reason }
    var diagnosticPolicy: PasteTargetPolicy { .unverifiedNotion }
}
