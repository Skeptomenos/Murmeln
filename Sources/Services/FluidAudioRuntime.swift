import Combine
import FluidAudio
import Foundation
import os

private let logger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "FluidAudioRuntime")

/// Slice 3: in-process CoreML runtime via FluidAudio (pinned exact 0.15.5).
/// Serves the catalog's Parakeet TDT v2/v3 and Cohere Transcribe INT8 entries.
/// Models download from ungated FluidInference HuggingFace repos into
/// Application Support/FluidAudio/Models.
@MainActor
final class FluidAudioRuntime: TranscriptionRuntime {
    static let shared = FluidAudioRuntime()

    enum LoadedEngine {
        case parakeet(AsrManager)
        case cohere(CoherePipeline.LoadedModels)
    }

    typealias ModelLoader = @MainActor (
        TranscriptionModelID, URL
    ) async throws -> LoadedEngine

    let id: RuntimeID = .fluidAudio

    /// Slice 5c/F1: every write publishes so SwiftUI settings rows repaint on
    /// `.loading→.ready`. Route ALL mutations through `setState`.
    private(set) var state: RuntimeState = .notLoaded {
        didSet { stateSubject.send(state) }
    }

    private let stateSubject = PassthroughSubject<RuntimeState, Never>()
    var stateChanged: AnyPublisher<RuntimeState, Never> { stateSubject.eraseToAnyPublisher() }

    // Loaded engines — exactly one model is resident at a time (Murmeln's
    // one-at-a-time usage; keeps RSS bounded).
    private var parakeetManager: AsrManager?
    private var cohereModels: CoherePipeline.LoadedModels?
    var hasResidentEngine: Bool {
        parakeetManager != nil || cohereModels != nil
    }
    private let coherePipeline = CoherePipeline()
    private let audioConverter = AudioConverter()

    /// Slice 5c/F2: monotonic load token. A `load()` that finishes after a
    /// newer `load()` began discards its result instead of clobbering state —
    /// switching models mid-load can no longer leave a stale engine resident.
    private var loadGeneration = 0

    /// Base directory for FluidAudio model caches (its own convention).
    /// Injectable so tests can point at an empty dir and exercise the genuine
    /// not-installed path even on a machine whose real cache is populated.
    private let modelsDirectory: URL
    private let installationCheck: ((TranscriptionModelID) -> Bool)?
    private let modelLoader: ModelLoader?

    init(
        modelsDirectory: URL = FluidAudioRuntime.defaultModelsDirectory,
        initialState: RuntimeState = .notLoaded,
        installationCheck: ((TranscriptionModelID) -> Bool)? = nil,
        modelLoader: ModelLoader? = nil
    ) {
        self.modelsDirectory = modelsDirectory
        self.installationCheck = installationCheck
        self.modelLoader = modelLoader
        state = initialState
    }

    static var defaultModelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models")
    }

    /// The per-model cache directory under `modelsDirectory`, matching
    /// FluidAudio's own `defaultModelsDirectory(for:)` layout
    /// (`…/FluidAudio/Models/<repo.folderName>`).
    private func cacheDirectory(for served: ServedModel) -> URL {
        modelsDirectory.appendingPathComponent(Self.repo(for: served).folderName)
    }

    // MARK: Catalog mapping

    private enum ServedModel {
        case parakeet(AsrModelVersion)
        case cohere
    }

    private static func servedModel(for modelID: TranscriptionModelID) -> ServedModel? {
        switch modelID.rawValue {
        case "parakeet-tdt-0.6b-v3": return .parakeet(.v3)
        case "parakeet-tdt-0.6b-v2": return .parakeet(.v2)
        case "cohere-transcribe-03-2026-int8": return .cohere
        default: return nil
        }
    }

    private static func repo(for served: ServedModel) -> Repo {
        switch served {
        case .parakeet(.v3): return .parakeetV3
        case .parakeet(.v2): return .parakeetV2
        case .parakeet: return .parakeetV3
        case .cohere: return .cohereTranscribeCoreml
        }
    }

    // MARK: TranscriptionRuntime

    func isInstalled(_ modelID: TranscriptionModelID) -> Bool {
        if let installationCheck {
            return installationCheck(modelID)
        }
        guard let served = Self.servedModel(for: modelID) else { return false }
        // Slice 5c/P2.5: verify the runtime's actual required files, not just a
        // non-empty folder — a partial/interrupted download must read as "not
        // installed" so the UI offers a download instead of failing at load.
        switch served {
        case .parakeet(let version):
            return AsrModels.modelsExist(
                at: cacheDirectory(for: served), version: version)
        case .cohere:
            let repoDir = cacheDirectory(for: served)
            return ModelNames.CohereTranscribe.requiredModels.allSatisfy { file in
                FileManager.default.fileExists(atPath: repoDir.appendingPathComponent(file).path)
            }
        }
    }

    func download(
        _ modelID: TranscriptionModelID,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        guard let served = Self.servedModel(for: modelID) else {
            throw TranscriptionRuntimeError.unsupportedModel(modelID, id)
        }
        progress(0)
        do {
            try await ModelHub.download(
                Self.repo(for: served),
                to: modelsDirectory,
                progressHandler: { update in
                    Task { @MainActor in
                        self.acceptDownloadProgress(
                            update.fractionCompleted,
                            progress: progress
                        )
                    }
                }
            )
            finishDownloadProgress(progress: progress)
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            throw mapError(error, modelID: modelID, operation: .download)
        }
    }

    func cancelDownload(_ modelID: TranscriptionModelID) {
        // ModelHub runs inside the manager-owned task, so cancelling that task
        // is the cancellation mechanism. There is no nested FluidAudio task.
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        guard let served = Self.servedModel(for: modelID) else {
            throw TranscriptionRuntimeError.unsupportedModel(modelID, id)
        }

        let shouldInvalidateLoad: Bool = switch state {
        case .ready(let loadedID): loadedID == modelID
        case .loading(let loadingID): loadingID == modelID
        default: false
        }
        if shouldInvalidateLoad {
            loadGeneration += 1
            unload(publish: true)
        }

        let directory = cacheDirectory(for: served)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Deterministic seam for ModelHub callback normalization. Download
    /// ownership and per-model presentation live in CatalogDownloadManager;
    /// runtime load state remains independent so downloads can coexist.
    func acceptDownloadProgress(
        _ fractionCompleted: Double,
        progress: @MainActor (Double) -> Void
    ) {
        let acceptedProgress = min(max(fractionCompleted, 0), 1)
        progress(acceptedProgress)
    }

    func finishDownloadProgress(
        progress: @MainActor (Double) -> Void
    ) {
        progress(1.0)
    }

    /// Load-only (Slice 5c/P1.1 + F3): never downloads. Throws
    /// `.modelNotInstalled` when assets are absent so a cold-load in the
    /// dictation path can't silently pull multi-GB weights or hit the network
    /// (downloads go solely through `download(_:progress:)`).
    func load(_ modelID: TranscriptionModelID) async throws {
        guard let served = Self.servedModel(for: modelID) else {
            throw TranscriptionRuntimeError.unsupportedModel(modelID, id)
        }
        guard isInstalled(modelID) else {
            throw TranscriptionRuntimeError.modelNotInstalled(modelID)
        }

        // Slice 5c/F2: claim a generation; a stale load discards its result.
        loadGeneration += 1
        let generation = loadGeneration

        // Switching models: drop the previous engine first.
        unload(publish: false)
        state = .loading(modelID)

        let captureID = "runtime-load-\(generation)"
        let loadStart = DispatchTime.now().uptimeNanoseconds
        await CaptureDiagnostics.shared.mark("runtime.load.started", captureID: captureID, metadata: [
            "runtime": id.rawValue, "model": modelID.rawValue,
        ])

        do {
            let loadedEngine: LoadedEngine
            if let modelLoader {
                loadedEngine = try await modelLoader(modelID, cacheDirectory(for: served))
            } else {
                loadedEngine = try await loadEngine(for: served)
            }
            guard generation == loadGeneration else {
                logger.info("Discarding stale FluidAudio load (gen \(generation) != \(self.loadGeneration))")
                return
            }
            switch loadedEngine {
            case .parakeet(let manager):
                parakeetManager = manager
            case .cohere(let models):
                cohereModels = models
            }
            state = .ready(modelID)
            let elapsedMs = (DispatchTime.now().uptimeNanoseconds - loadStart) / 1_000_000
            await CaptureDiagnostics.shared.mark("runtime.load.completed", captureID: captureID, metadata: [
                "runtime": id.rawValue, "model": modelID.rawValue, "elapsed_ms": String(elapsedMs),
            ])
            logger.info("Loaded \(modelID.rawValue, privacy: .public) in \(elapsedMs) ms")
        } catch {
            if Self.shouldPreserveCancellation(error) {
                if generation == loadGeneration {
                    state = .notLoaded
                }
                throw CancellationError()
            }
            let mapped = mapError(error, modelID: modelID, operation: .load)
            // Only the current generation owns the state; a superseded load
            // must not stomp a newer load's state with its own failure.
            if generation == loadGeneration {
                state = .failed(mapped.localizedDescription)
            }
            await CaptureDiagnostics.shared.mark("runtime.load.failed", captureID: captureID, metadata: [
                "runtime": id.rawValue, "model": modelID.rawValue, "error": mapped.localizedDescription,
            ])
            logger.error("Load failed for \(modelID.rawValue, privacy: .public): \(mapped.localizedDescription, privacy: .public)")
            throw mapped
        }
    }

    func unload() {
        // Relinquish ownership of any in-flight load before clearing the
        // resident engine. A late completion must not republish `.ready`.
        loadGeneration += 1
        unload(publish: true)
    }

    private func loadEngine(for served: ServedModel) async throws -> LoadedEngine {
        switch served {
        case .parakeet(let version):
            let models = try await AsrModels.load(
                from: cacheDirectory(for: served), version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return .parakeet(manager)
        case .cohere:
            let repoDir = cacheDirectory(for: served)
            // F4: the multi-minute CoreML specialization lives here — logged
            // start/complete with elapsed so a long first load is visible.
            let models = try await CoherePipeline.loadModels(
                encoderDir: repoDir, decoderDir: repoDir, vocabDir: repoDir)
            return .cohere(models)
        }
    }

    /// `publish: false` lets `load()` reset engines without emitting a
    /// transient `.notLoaded` between `.ready`/`.loading` transitions.
    private func unload(publish: Bool) {
        parakeetManager = nil
        cohereModels = nil
        if publish {
            state = .notLoaded
        }
    }

    /// Collapse raw FluidAudio/CoreML errors into a typed operation failure
    /// before they reach the UI. Missing assets remain actionable as a model
    /// download; corrupt CoreML, OOM, hardware, and inference failures retain
    /// their actual operation and underlying description.
    func mapError(
        _ error: Error,
        modelID: TranscriptionModelID,
        operation: RuntimeOperation,
        assetsInstalled: Bool? = nil
    ) -> TranscriptionRuntimeError {
        if let typed = error as? TranscriptionRuntimeError {
            return typed
        }
        let installed = assetsInstalled ?? isInstalled(modelID)
        if operation != .download && !installed {
            return .modelNotInstalled(modelID)
        }
        return .runtimeFailure(id, operation, error.localizedDescription)
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        guard case .ready(let modelID) = state, let served = Self.servedModel(for: modelID) else {
            throw TranscriptionRuntimeError.runtimeNotReady(id)
        }

        do {
            let samples = try audioConverter.resampleAudioFile(path: audioURL.path)

            switch served {
            case .parakeet:
                guard let manager = parakeetManager else {
                    throw TranscriptionRuntimeError.runtimeNotReady(id)
                }
                // Fresh decoder state per capture — push-to-talk utterances are
                // independent; no cross-capture context carryover.
                var decoderState = try TdtDecoderState(decoderLayers: currentParakeetVersion?.decoderLayers ?? 2)
                let result = try await manager.transcribe(samples, decoderState: &decoderState)
                return result.text

            case .cohere:
                guard let models = cohereModels else {
                    throw TranscriptionRuntimeError.runtimeNotReady(id)
                }
                guard let maxSeconds = Self.maxUtteranceSeconds(for: modelID) else {
                    throw TranscriptionRuntimeError.runtimeFailure(
                        id, .transcribe, "Catalog is missing the Cohere utterance limit."
                    )
                }
                let language = CohereAsrConfig.Language(rawValue: options.languageCode ?? "en") ?? .english
                let durationSeconds = Double(samples.count) / Double(CohereAsrConfig.sampleRate)
                // Keep capped audio on FluidAudio's byte-identical single-call
                // path; longer audio uses Murmeln's regression-tested overlap.
                switch AudioChunkingRoute.route(
                    durationSeconds: durationSeconds,
                    maxUtteranceSeconds: Double(maxSeconds)
                ) {
                case .singleCall:
                    let result = try await coherePipeline.transcribe(
                        audio: samples, models: models, language: language)
                    return result.text
                case .longForm:
                    let ranges = CohereLongFormChunking.ranges(
                        sampleCount: samples.count,
                        sampleRate: CohereAsrConfig.sampleRate,
                        maxChunkSeconds: maxSeconds
                    )
                    var transcript = ""
                    for range in ranges {
                        let result = try await coherePipeline.transcribe(
                            audio: Array(samples[range]), models: models, language: language)
                        transcript = CohereLongFormChunking.merge(
                            prefix: transcript,
                            suffix: result.text
                        )
                    }
                    return transcript
                }
            }
        } catch {
            if Self.shouldPreserveCancellation(error) {
                throw CancellationError()
            }
            throw mapError(error, modelID: modelID, operation: .transcribe)
        }
    }

    nonisolated static func shouldPreserveCancellation(_ error: Error) -> Bool {
        error is CancellationError
    }

    static func maxUtteranceSeconds(for modelID: TranscriptionModelID) -> Int? {
        ModelCatalog.entry(for: modelID)?.maxUtteranceSeconds
    }

    private var currentParakeetVersion: AsrModelVersion? {
        guard case .ready(let modelID) = state,
              case .parakeet(let version) = Self.servedModel(for: modelID) else {
            return nil
        }
        return version
    }
}
