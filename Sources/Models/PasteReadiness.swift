struct PasteReadiness: Sendable, Equatable {
    let postAccess: Bool?
    let secureInput: Bool?

    var message: String {
        var observations: [String] = []
        if let postAccess {
            if !postAccess { observations.append("Paste permission is denied.") }
        } else { observations.append("Paste permission status is unavailable.") }
        if let secureInput {
            observations.append(secureInput ? "Secure Input is active." : "Secure Input is off.")
        } else { observations.append("Secure Input status is unavailable.") }
        observations.append("Copy your text, choose a text field, and paste.")
        return observations.joined(separator: " ")
    }
}
