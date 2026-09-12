/// Identity registry for the app's transcription runtimes.
@MainActor
final class TranscriptionRuntimeRegistry {
    static let shared = TranscriptionRuntimeRegistry(runtimes: [
        .fluidAudio: FluidAudioRuntime.shared,
        .whisperKit: WhisperKitRuntime.shared,
    ])

    private let runtimes: [RuntimeID: any TranscriptionRuntime]

    init(runtimes: [RuntimeID: any TranscriptionRuntime]) {
        precondition(Set(runtimes.keys) == Set(RuntimeID.allCases))
        precondition(runtimes.allSatisfy { runtimeID, runtime in
            runtime.id == runtimeID
        })
        self.runtimes = runtimes
    }

    func runtime(for runtimeID: RuntimeID) -> any TranscriptionRuntime {
        guard let runtime = runtimes[runtimeID] else {
            preconditionFailure("Missing runtime for \(runtimeID.rawValue)")
        }
        return runtime
    }

    func runtime(forModel modelID: TranscriptionModelID) -> (any TranscriptionRuntime)? {
        guard let entry = ModelCatalog.entry(for: modelID) else { return nil }
        return runtime(for: entry.runtime)
    }
}
