import FluidAudio

/// Typed bridge between Murmeln's model catalog and FluidAudio's closed APIs.
struct FluidAudioModelDescriptor: Sendable {
    let modelID: TranscriptionModelID
    let repo: Repo
    let engine: FluidAudioEngine

    /// FluidAudio exposes `Repo` as a closed enum. This is the only bridge
    /// from Murmeln's stable catalog IDs to that dependency-specific API.
    static let all: [Self] = [
        Self(
            modelID: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"),
            repo: .parakeetV3,
            engine: .parakeetV3
        ),
        Self(
            modelID: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2"),
            repo: .parakeetV2,
            engine: .parakeetV2
        ),
        Self(
            modelID: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8"),
            repo: .cohereTranscribeCoreml,
            engine: .cohere
        ),
    ]

    static func descriptor(for modelID: TranscriptionModelID) -> Self? {
        all.first { $0.modelID == modelID }
    }
}
