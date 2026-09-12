import Combine
import FluidAudio
import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("Transcription Selection Lifecycle Tests")
struct TranscriptionSelectionLifecycleTests {
    @Test("Lifecycle resolves a catalog selection through the injected registry")
    func lifecycleUsesInjectedRegistry() async {
        let modelID = ModelCatalog.defaultModelID
        let fluidAudio = MockRuntime(id: .fluidAudio)
        fluidAudio.installedModels = [modelID]
        let whisperKit = MockRuntime(id: .whisperKit)
        let registry = TranscriptionRuntimeRegistry(runtimes: [
            .fluidAudio: fluidAudio,
            .whisperKit: whisperKit,
        ])
        let lifecycle = TranscriptionSelectionLifecycle(runtimeRegistry: registry)

        lifecycle.warm(.catalog(modelID))
        await lifecycle.waitUntilIdle()

        #expect(fluidAudio.loadCalls == [modelID])
        #expect(whisperKit.loadCalls.isEmpty)
    }

    @Test("A newer selection prevents a suspended stale load from becoming ready")
    func newerSelectionSupersedesSuspendedLoad() async throws {
        let firstID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        let secondID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let runtime = SuspendedLifecycleRuntime(
            id: .fluidAudio,
            suspendedModel: firstID,
            honorsCancellationBeforeReady: true
        )
        let lifecycle = TranscriptionSelectionLifecycle(
            runtimeRegistry: makeRegistry(fluidAudio: runtime)
        )

        lifecycle.warm(.catalog(firstID))
        try await waitUntil { runtime.loadCalls == [firstID] }

        lifecycle.apply(.init(
            previous: .catalog(firstID),
            current: .catalog(secondID)
        ))
        runtime.completeSuspendedLoad()
        await lifecycle.waitUntilIdle()

        #expect(runtime.state == .ready(secondID))
        #expect(!runtime.observedStates.contains(.ready(firstID)))
        #expect(runtime.loadCalls == [firstID, secondID])
    }

    @Test("Termination cancellation prevents a suspended load from restoring readiness")
    func cancellationSupersedesSuspendedLoad() async throws {
        let modelID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        let runtime = SuspendedLifecycleRuntime(id: .fluidAudio, suspendedModel: modelID)
        let lifecycle = TranscriptionSelectionLifecycle(
            runtimeRegistry: makeRegistry(fluidAudio: runtime)
        )

        lifecycle.apply(.init(
            previous: .legacy(.openAIWhisper),
            current: .catalog(modelID)
        ))
        try await waitUntil { runtime.loadCalls == [modelID] }

        let cancellation = Task { @MainActor in
            await lifecycle.cancel()
        }
        await Task.yield()
        runtime.completeSuspendedLoad()

        await cancellation.value

        #expect(runtime.state == .notLoaded)
    }

    @Test("Lifecycle cleanup does not invalidate a newer externally owned load")
    func externalLoadSupersedesLifecycleLoadOnSharedRuntime() async throws {
        let firstID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")
        let secondID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        var continuations: [
            TranscriptionModelID: CheckedContinuation<FluidAudioRuntime.LoadedEngine, Never>
        ] = [:]
        let runtime = FluidAudioRuntime(
            installationCheck: { $0 == firstID || $0 == secondID },
            modelLoader: { modelID, _ in
                await withCheckedContinuation { continuation in
                    continuations[modelID] = continuation
                }
            }
        )
        let lifecycle = TranscriptionSelectionLifecycle(
            runtimeRegistry: makeRegistry(fluidAudio: runtime)
        )

        lifecycle.warm(.catalog(firstID))
        try await waitUntil { continuations[firstID] != nil }

        let externalLoad = Task { try await runtime.load(secondID) }
        try await waitUntil { continuations[secondID] != nil }

        continuations.removeValue(forKey: firstID)?.resume(
            returning: .parakeet(AsrManager(config: .default))
        )
        await lifecycle.waitUntilIdle()
        continuations.removeValue(forKey: secondID)?.resume(
            returning: .parakeet(AsrManager(config: .default))
        )

        try await externalLoad.value
        #expect(runtime.state == .ready(secondID))
        #expect(runtime.hasResidentEngine)
    }

    private func makeRegistry(
        fluidAudio: any TranscriptionRuntime
    ) -> TranscriptionRuntimeRegistry {
        TranscriptionRuntimeRegistry(runtimes: [
            .fluidAudio: fluidAudio,
            .whisperKit: MockRuntime(id: .whisperKit),
        ])
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                throw LifecycleProbeError.timedOut
            }
            await Task.yield()
        }
    }

    private enum LifecycleProbeError: Error {
        case timedOut
    }

    @MainActor
    private final class SuspendedLifecycleRuntime: TranscriptionRuntime {
        let id: RuntimeID
        private(set) var state: RuntimeState = .notLoaded {
            didSet {
                observedStates.append(state)
                stateSubject.send(state)
            }
        }
        var stateChanged: AnyPublisher<RuntimeState, Never> {
            stateSubject.eraseToAnyPublisher()
        }

        private let stateSubject = PassthroughSubject<RuntimeState, Never>()
        private let suspendedModel: TranscriptionModelID?
        private let honorsCancellationBeforeReady: Bool
        private var loadContinuation: CheckedContinuation<Void, Never>?
        private(set) var observedStates: [RuntimeState] = []
        private(set) var loadCalls: [TranscriptionModelID] = []
        private(set) var unloadCalls = 0

        init(
            id: RuntimeID,
            suspendedModel: TranscriptionModelID? = nil,
            honorsCancellationBeforeReady: Bool = false
        ) {
            self.id = id
            self.suspendedModel = suspendedModel
            self.honorsCancellationBeforeReady = honorsCancellationBeforeReady
        }

        func isInstalled(_ modelID: TranscriptionModelID) -> Bool { true }

        func download(
            _ modelID: TranscriptionModelID,
            progress: @escaping @MainActor (Double) -> Void
        ) async throws {}

        func cancelDownload(_ modelID: TranscriptionModelID) {}

        func delete(_ modelID: TranscriptionModelID) async throws {}

        func load(_ modelID: TranscriptionModelID) async throws {
            loadCalls.append(modelID)
            state = .loading(modelID)
            if modelID == suspendedModel {
                await withCheckedContinuation { continuation in
                    loadContinuation = continuation
                }
            }
            if honorsCancellationBeforeReady {
                try Task.checkCancellation()
            }
            state = .ready(modelID)
        }

        func unload() async {
            unloadCalls += 1
            state = .notLoaded
        }

        func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
            ""
        }

        func completeSuspendedLoad() {
            loadContinuation?.resume()
            loadContinuation = nil
        }
    }
}
