import Foundation

/// A fixed-text experiment, separate from every normal dictation entry point.
enum DevDeliveryDiagnostic {
    static let environmentKey = "MURMELN_DEV_DELIVERY_PROBE"
    static let fixedText = "Murmeln Dev controlled delivery marker"

    static func isEnabled(bundleIdentifier: String?, environment: [String: String]) -> Bool {
        bundleIdentifier == "com.mrml.app.dev" && environment[environmentKey] == "1"
    }
}

enum DevDeliveryDiagnosticResult {
    case refused(Refusal)
    case completed(PasteTiming)

    enum Refusal: String {
        case disabled, invalidTarget, busy, cancelled
    }
}
