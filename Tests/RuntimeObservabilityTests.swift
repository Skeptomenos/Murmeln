import Combine
import Foundation
import FluidAudio
import Testing
@testable import mrml

/// Slice 5c: the dogfood-surfaced defects (plan Discoveries F–J + Alfred
/// P1.1/P2.4/P2.5). Each test fails against the pre-5c code and passes after
/// the fix — the falsifiability contract from the self-correction-loop skill.
@MainActor
@Suite("Runtime Observability & Load Safety Tests", .serialized)
struct RuntimeObservabilityTests {

    // MARK: F1 — state transitions are observable (the "Loading…" forever bug)

    @Test("A runtime publishes every state transition on stateChanged")
    func stateTransitionsArePublished() async throws {
        let runtime = MockRuntime(id: .fluidAudio)
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        runtime.installedModels = [model]

        var published: [RuntimeState] = []
        let cancellable = runtime.stateChanged.sink { published.append($0) }
        defer { cancellable.cancel() }

        try await runtime.load(model)

        // The load path must emit .loading then .ready — the transition the UI
        // needs to leave the spinner. Pre-5c the runtime published nothing.
        #expect(published.contains(.loading(model)))
        #expect(published.contains(.ready(model)))
        #expect(published.last == .ready(model))
    }

    @Test("RuntimeStatusModel reflects the runtime's post-load state")
    func statusModelReflectsReadyState() async throws {
        let runtime = MockRuntime(id: .fluidAudio)
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        runtime.installedModels = [model]

        let status = RuntimeStatusModel(runtime: runtime)
        #expect(status.state == .notLoaded)

        try await runtime.load(model)
        // stateChanged delivers on the main run loop; let it drain.
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(status.state == .ready(model))
    }

    /// The real bug guard: FluidAudioRuntime (not the mock) must publish its
    /// own transitions. Requires the model cached on disk — skipped otherwise
    /// so CI without the ~469 MB Parakeet weights still runs the rest.
    @Test("FluidAudioRuntime publishes .loading then .ready on a real load")
    func fluidAudioRuntimePublishesTransitions() async throws {
        let runtime = FluidAudioRuntime()
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        try #require(runtime.isInstalled(model), "Parakeet v3 must be cached for this test")

        var published: [RuntimeState] = []
        let cancellable = runtime.stateChanged.sink { published.append($0) }
        defer { cancellable.cancel() }

        try await runtime.load(model)
        #expect(published.contains(.loading(model)))
        #expect(published.last == .ready(model))
    }

    // MARK: Slice 5d — one progress source for badge + main bar

    @Test("FluidAudio download forwards one clamped progress fraction")
    func fluidAudioDownloadProgressIsClamped() {
        let runtime = FluidAudioRuntime()
        var callerProgress = -1.0
        runtime.acceptDownloadProgress(1.10) { callerProgress = $0 }

        #expect(callerProgress == 1.0)
    }

    @Test("Distinct FluidAudio downloads can both report progress and finish")
    func distinctFluidAudioDownloadsCanProgressIndependently() throws {
        let runtime = FluidAudioRuntime()
        var callerA = -1.0
        var callerB = -1.0

        // A reports after B starts; switching/starting B must not cancel A.
        runtime.acceptDownloadProgress(0.80) { callerA = $0 }
        #expect(callerA == 0.80)

        runtime.acceptDownloadProgress(0.20) { callerB = $0 }
        #expect(callerB == 0.20)

        runtime.finishDownloadProgress { callerA = $0 }
        #expect(callerA == 1.0)

        runtime.finishDownloadProgress { callerB = $0 }
        #expect(callerB == 1.0)
    }

    @Test("Catalog downloads remain model-keyed and active across selection changes")
    func catalogDownloadsRemainVisibleAcrossModelChanges() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let modelA = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let modelB = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        manager.start(modelA, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [modelA] }
        #expect(manager.activity(for: modelA) == .downloading(progress: 0.25))

        manager.start(modelB, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [modelA, modelB] }

        #expect(manager.activity(for: modelA) == .downloading(progress: 0.25))
        #expect(manager.activity(for: modelB) == .downloading(progress: 0.25))

        runtime.complete(modelA)
        runtime.complete(modelB)
        try await waitUntil {
            manager.activity(for: modelA) == .downloaded
                && manager.activity(for: modelB) == .downloaded
        }
    }

    @Test("Starting the same catalog download twice is deduplicated")
    func duplicateCatalogDownloadIsDeduplicated() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")

        manager.start(model, runtime: runtime)
        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }

        #expect(runtime.downloadCalls == [model])
        runtime.complete(model)
        try await waitUntil { manager.activity(for: model) == .downloaded }
    }

    @Test("Cancelling then retrying keeps late cancelled completion from overwriting the retry")
    func cancelledDownloadCannotOverwriteImmediateRetry() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }

        manager.cancel(model)
        #expect(runtime.cancelDownloadCalls == [model])
        #expect(manager.activity(for: model) == .idle)

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model, model] }
        #expect(manager.activity(for: model) == .downloading(progress: 0.25))

        // The first transfer ignores cancellation until this late completion.
        // It must not reset or complete the retry that now owns the model.
        runtime.complete(model, attempt: 0)
        try await Task.sleep(for: .milliseconds(10))
        #expect(manager.activity(for: model) == .downloading(progress: 0.25))

        runtime.complete(model, attempt: 1)
        try await waitUntil { manager.activity(for: model) == .downloaded }
    }

    @Test("Cancelled download late progress and failure cannot overwrite its retry")
    func cancelledDownloadCannotReportLateProgressOrFailure() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }
        manager.cancel(model)

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model, model] }

        runtime.reportProgress(0.9, for: model, attempt: 0)
        runtime.fail(model, attempt: 0)
        try await Task.sleep(for: .milliseconds(10))
        #expect(manager.activity(for: model) == .downloading(progress: 0.25))

        runtime.complete(model, attempt: 1)
        try await waitUntil { manager.activity(for: model) == .downloaded }
    }

    @Test("Deleting through the catalog manager removes the installed model")
    func catalogManagerDeletesInstalledModel() async {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        runtime.installedModels = [model]

        await manager.delete(model, runtime: runtime)

        #expect(runtime.deleteCalls == [model])
        #expect(runtime.isInstalled(model) == false)
        #expect(manager.activity(for: model) == .idle)
    }

    @Test("FluidAudio delete removes only the requested model cache")
    func fluidAudioDeleteRemovesRequestedCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-delete-\(UUID().uuidString)")
        let requested = root.appendingPathComponent("parakeet-tdt-0.6b-v3")
        let unrelated = root.appendingPathComponent("parakeet-tdt-0.6b-v2")
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let runtime = FluidAudioRuntime(modelsDirectory: root, initialState: .ready(model))

        try await runtime.delete(model)

        #expect(FileManager.default.fileExists(atPath: requested.path) == false)
        #expect(FileManager.default.fileExists(atPath: unrelated.path) == true)
        #expect(runtime.state == .notLoaded)
    }

    @Test("FluidAudio delete does not invalidate a different model loading")
    func fluidAudioDeletePreservesUnrelatedLoad() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-delete-unrelated-\(UUID().uuidString)")
        let deletedModel = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")
        let loadingModel = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let deletedDirectory = root.appendingPathComponent(deletedModel.rawValue)
        try FileManager.default.createDirectory(at: deletedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let runtime = FluidAudioRuntime(
            modelsDirectory: root,
            initialState: .loading(loadingModel)
        )

        try await runtime.delete(deletedModel)

        #expect(runtime.state == .loading(loadingModel))
        #expect(FileManager.default.fileExists(atPath: deletedDirectory.path) == false)
    }

    @Test("WhisperKit delete removes only the selected variant and its index entry")
    func whisperKitDeleteRemovesSelectedVariant() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-delete-\(UUID().uuidString)")
        let variantsRoot = root.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
        let variant = "openai_whisper-small"
        let unrelatedVariant = "openai_whisper-base"
        let requested = variantsRoot.appendingPathComponent(variant)
        let unrelated = variantsRoot.appendingPathComponent(unrelatedVariant)
        try FileManager.default.createDirectory(at: requested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)

        let previousIndex = AppSettings.shared.installedWhisperModels
        defer {
            AppSettings.shared.installedWhisperModels = previousIndex
            try? FileManager.default.removeItem(at: root)
        }
        AppSettings.shared.installedWhisperModels = [variant, unrelatedVariant]

        let service = WhisperKitService(modelsDirectory: root)
        try await service.deleteModel(variant)

        #expect(FileManager.default.fileExists(atPath: requested.path) == false)
        #expect(FileManager.default.fileExists(atPath: unrelated.path) == true)
        #expect(AppSettings.shared.installedWhisperModels == [unrelatedVariant])
    }

    @Test("WhisperKit runtime forwards determinate service download progress")
    func whisperKitRuntimeForwardsDownloadProgress() async throws {
        let service = ProgressingWhisperKitService()
        let runtime = WhisperKitRuntime(
            service: service,
            variantProvider: { "openai_whisper-small" }
        )
        let model = TranscriptionModelID.whisperKit
        var observedProgress: [Double] = []

        try await runtime.download(model) { observedProgress.append($0) }

        #expect(observedProgress == [0.25, 0.75, 1.0])
    }

    @Test("WhisperKit progress bridge drops a stale value from a previous download")
    func whisperKitProgressBridgeDropsStaleInitialValue() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-progress-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let service = WhisperKitService(modelsDirectory: root)
        service.downloadProgress = 0.8
        var observedProgress: [Double] = []

        let observation = service.downloadProgressChanged
            .sink { observedProgress.append($0) }
        service.downloadProgress = 0
        observation.cancel()

        #expect(observedProgress == [0])
    }

    @Test("WhisperKit runtime forwards a non-English catalog language hint")
    func whisperKitRuntimeForwardsCatalogLanguageHint() async throws {
        let service = ProgressingWhisperKitService()
        let runtime = WhisperKitRuntime(
            service: service,
            variantProvider: { "openai_whisper-small" }
        )
        let modelID = TranscriptionModelID.whisperKit
        try await runtime.load(modelID)

        _ = try await runtime.transcribe(
            audioURL: FileManager.default.temporaryDirectory.appendingPathComponent("speech.wav"),
            options: TranscriptionOptions(languageCode: "de")
        )

        #expect(service.transcriptionLanguageCodes == ["de"])
    }

    // MARK: P1.1 / F3 — load is load-only (never downloads, never hits network)

    @Test("Loading a catalog model with no assets on disk throws modelNotInstalled")
    func loadUninstalledThrowsNotInstalled() async throws {
        // Point the runtime at an empty temp dir so the assertion holds even on
        // this machine (whose real FluidAudio cache is fully populated).
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-5c-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let runtime = FluidAudioRuntime(modelsDirectory: emptyDir)
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        var published: [RuntimeState] = []
        let cancellable = runtime.stateChanged.sink { published.append($0) }
        defer { cancellable.cancel() }

        await #expect(throws: TranscriptionRuntimeError.modelNotInstalled(model)) {
            try await runtime.load(model)
        }
        // Load-only fail-fast: the not-installed guard rejects BEFORE the load
        // body, so state never enters .loading and the empty dir stays empty
        // (no download was triggered).
        #expect(!published.contains(.loading(model)))
        let contents = try FileManager.default.contentsOfDirectory(atPath: emptyDir.path)
        #expect(contents.isEmpty)
    }

    @Test("isInstalled is false when required files are absent (empty cache dir)")
    func isInstalledFalseForEmptyCache() throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-5c-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let runtime = FluidAudioRuntime(modelsDirectory: emptyDir)
        #expect(runtime.isInstalled(TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")) == false)
        #expect(runtime.isInstalled(TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")) == false)
    }

    // MARK: F2 / Alfred P2.4 — model-switch race guard

    @Test("Overlapping loads leave a coherent terminal state, never stuck loading")
    func overlappingLoadsDoNotStickLoading() async throws {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-5c-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let runtime = FluidAudioRuntime(modelsDirectory: emptyDir)
        let a = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")
        let b = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")

        async let ra: Void = attempt { try await runtime.load(a) }
        async let rb: Void = attempt { try await runtime.load(b) }
        _ = await (ra, rb)

        if case .loading = runtime.state {
            Issue.record("runtime stuck in .loading after overlapping loads")
        }
    }

    @Test("Unloading invalidates an in-flight FluidAudio load")
    func unloadInvalidatesInFlightFluidAudioLoad() async throws {
        let gate = SuspendedFluidAudioLoadGate()
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let runtime = FluidAudioRuntime(
            installationCheck: { $0 == model },
            modelLoader: { requestedModel, _ in
                #expect(requestedModel == model)
                await gate.suspend()
                return .parakeet(AsrManager(config: .default))
            }
        )

        let load = Task { try await runtime.load(model) }
        try await waitUntil { gate.hasStarted }

        runtime.unload()
        #expect(runtime.state == .notLoaded)

        gate.finish()
        try await load.value

        #expect(runtime.state == .notLoaded)
        #expect(!runtime.hasResidentEngine)
    }

    @Test("MockRuntime load-only contract: load never appends a download call")
    func mockLoadDoesNotDownload() async throws {
        let runtime = MockRuntime(id: .fluidAudio)
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        runtime.installedModels = [model]
        try await runtime.load(model)
        #expect(runtime.downloadCalls.isEmpty)
    }

    @Test("isInstalled is false for an unknown (non-catalog) model")
    func isInstalledFalseForUnknownModel() {
        let runtime = FluidAudioRuntime()
        #expect(runtime.isInstalled(TranscriptionModelID(rawValue: "does-not-exist")) == false)
    }

    @Test("WhisperKit readiness is tied to the concrete loaded variant")
    func whisperKitReadinessTracksVariant() async throws {
        let service = ProgressingWhisperKitService()
        var selectedVariant = "openai_whisper-small"
        let runtime = WhisperKitRuntime(
            service: service,
            variantProvider: { selectedVariant }
        )
        let modelID = TranscriptionModelID.whisperKit

        try await runtime.load(modelID)
        #expect(runtime.state == .ready(modelID))

        selectedVariant = "openai_whisper-medium"
        #expect(runtime.state != .ready(modelID))

        try await runtime.load(modelID)
        #expect(service.loadedVariants == [
            "openai_whisper-small", "openai_whisper-medium"
        ])
        #expect(runtime.state == .ready(modelID))
    }

    @Test("Catalog WhisperKit selection stores and loads through the runtime")
    func catalogWhisperKitSelectionLoadsThroughRuntime() async throws {
        let modelID = TranscriptionModelID.whisperKit
        let variant = "openai_whisper-medium"
        var storedVariants: [String] = []
        var runtimeLoads: [TranscriptionModelID] = []
        var legacyLoads: [String] = []

        try await WhisperKitSetupView.applySelection(
            variant,
            for: .catalog(modelID),
            storeVariant: { storedVariants.append($0) },
            loadCatalogModel: { runtimeLoads.append($0) },
            loadLegacyVariant: { legacyLoads.append($0) }
        )

        #expect(storedVariants == [variant])
        #expect(runtimeLoads == [modelID])
        #expect(legacyLoads.isEmpty)
    }

    @Test("WhisperKit variant change retargets subsequent download and load")
    func whisperKitVariantChangeRetargetsDownloadAndLoad() async throws {
        let service = ProgressingWhisperKitService()
        var selectedVariant = "openai_whisper-small"
        let runtime = WhisperKitRuntime(
            service: service,
            variantProvider: { selectedVariant }
        )
        let modelID = TranscriptionModelID.whisperKit

        selectedVariant = "openai_whisper-medium"
        try await runtime.download(modelID) { _ in }
        try await runtime.load(modelID)

        #expect(service.downloadedVariants == ["openai_whisper-medium"])
        #expect(service.loadedVariants == ["openai_whisper-medium"])
        #expect(runtime.state == .ready(modelID))
    }

    private func attempt(_ body: () async throws -> Void) async {
        do { try await body() } catch { /* expected in unit env */ }
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 where !predicate() {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate())
    }

    @MainActor
    private final class SuspendedFluidAudioLoadGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var hasStarted = false

        func suspend() async {
            hasStarted = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func finish() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private final class SuspendedDownloadRuntime: TranscriptionRuntime {
        let id: RuntimeID = .fluidAudio
        var state: RuntimeState = .notLoaded
        var stateChanged: AnyPublisher<RuntimeState, Never> {
            Empty().eraseToAnyPublisher()
        }

        private(set) var downloadCalls: [TranscriptionModelID] = []
        private(set) var cancelDownloadCalls: [TranscriptionModelID] = []
        private(set) var deleteCalls: [TranscriptionModelID] = []
        var installedModels: Set<TranscriptionModelID> = []
        private var nextAttempt = 0
        private var attemptTokens: [TranscriptionModelID: [Int]] = [:]
        private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
        private var progressCallbacks: [Int: @MainActor (Double) -> Void] = [:]

        func isInstalled(_ modelID: TranscriptionModelID) -> Bool {
            installedModels.contains(modelID)
        }

        func download(
            _ modelID: TranscriptionModelID,
            progress: @escaping @MainActor (Double) -> Void
        ) async throws {
            downloadCalls.append(modelID)
            progress(0.25)
            let attempt = nextAttempt
            nextAttempt += 1
            attemptTokens[modelID, default: []].append(attempt)
            progressCallbacks[attempt] = progress
            try await withCheckedThrowingContinuation { continuation in
                continuations[attempt] = continuation
            }
            installedModels.insert(modelID)
        }

        func complete(_ modelID: TranscriptionModelID, attempt: Int = 0) {
            guard let token = attemptToken(for: modelID, attempt: attempt) else { return }
            continuations.removeValue(forKey: token)?.resume(returning: ())
            progressCallbacks[token] = nil
        }

        func reportProgress(
            _ progress: Double,
            for modelID: TranscriptionModelID,
            attempt: Int
        ) {
            guard let token = attemptToken(for: modelID, attempt: attempt) else { return }
            progressCallbacks[token]?(progress)
        }

        func fail(_ modelID: TranscriptionModelID, attempt: Int) {
            guard let token = attemptToken(for: modelID, attempt: attempt) else { return }
            continuations.removeValue(forKey: token)?.resume(throwing: ProbeFailure())
            progressCallbacks[token] = nil
        }

        private func attemptToken(for modelID: TranscriptionModelID, attempt: Int) -> Int? {
            guard let attempts = attemptTokens[modelID], attempts.indices.contains(attempt) else {
                return nil
            }
            return attempts[attempt]
        }

        func cancelDownload(_ modelID: TranscriptionModelID) {
            cancelDownloadCalls.append(modelID)
        }

        func delete(_ modelID: TranscriptionModelID) async throws {
            deleteCalls.append(modelID)
            installedModels.remove(modelID)
            state = .notLoaded
        }

        func load(_ modelID: TranscriptionModelID) async throws {}
        func unload() {}
        func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String { "" }

        private struct ProbeFailure: Error {}
    }

    private final class ProgressingWhisperKitService:
        WhisperKitTranscribing, WhisperKitModelManaging
    {
        var modelState: WhisperKitService.ModelState = .unloaded
        var selectedModel = ""
        var downloadedVariants: [String] = []
        var loadedVariants: [String] = []
        var transcriptionLanguageCodes: [String?] = []
        private let downloadProgressSubject = PassthroughSubject<Double, Never>()

        var modelStateChanged: AnyPublisher<WhisperKitService.ModelState, Never> {
            Just(modelState).eraseToAnyPublisher()
        }

        var downloadProgressChanged: AnyPublisher<Double, Never> {
            downloadProgressSubject.eraseToAnyPublisher()
        }

        func isModelDownloaded(_ variant: String) -> Bool { false }

        func downloadModel(_ variant: String) async throws -> URL {
            downloadedVariants.append(variant)
            downloadProgressSubject.send(0.25)
            downloadProgressSubject.send(0.75)
            return FileManager.default.temporaryDirectory
        }

        func cancelDownload() {}
        func deleteModel(_ variant: String) async throws {}
        func unloadModel() async {}
        func loadModel(_ variant: String) async throws {
            loadedVariants.append(variant)
            modelState = .ready
        }
        func transcribe(audioURL: URL) async throws -> String { "" }
        func transcribe(audioURL: URL, languageCode: String?) async throws -> String {
            transcriptionLanguageCodes.append(languageCode)
            return ""
        }
    }
}
