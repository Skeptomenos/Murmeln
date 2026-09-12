import FluidAudio

/// FluidAudio engine variant used to load one catalog model.
enum FluidAudioEngine: Sendable, Equatable {
    case parakeetV3
    case parakeetV2
    case cohere

    var parakeetVersion: AsrModelVersion? {
        switch self {
        case .parakeetV3: .v3
        case .parakeetV2: .v2
        case .cohere: nil
        }
    }
}
