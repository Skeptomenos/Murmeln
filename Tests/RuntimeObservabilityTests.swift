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

    @Test("Catalog manager retains ownership through the selected model's eager load")
    func catalogManagerOwnsSelectedModelLoad() async throws {
        let model = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let runtime = SuspendedDownloadRuntime()
        runtime.suspendLoads = true
        let manager = CatalogDownloadManager(selectedModel: { model })

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }
        runtime.complete(model)
        try await waitUntil { runtime.loadCalls == [model] }

        manager.start(model, runtime: runtime)
        try await Task.sleep(for: .milliseconds(10))

        #expect(runtime.downloadCalls == [model])
        if runtime.downloadCalls.count > 1 {
            runtime.complete(model, attempt: 1)
            try await waitUntil { runtime.loadCalls.count == 2 }
        }
        runtime.completeLoads()
        try await waitUntil { manager.activity(for: model) == .downloaded }
    }

    @Test("Cancelling a download waits for termination before retry")
    func cancelledDownloadWaitsForTerminationBeforeRetry() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }

        manager.cancel(model)
        #expect(runtime.cancelDownloadCalls == [model])
        #expect(manager.activity(for: model) == .idle)

        manager.start(model, runtime: runtime)
        // Cancellation is a request, not proof that the runtime has stopped.
        // A retry must wait for the old transfer to release its model-cache
        // ownership before it can start.
        try await Task.sleep(for: .milliseconds(10))
        #expect(runtime.downloadCalls == [model])
        #expect(runtime.maximumActiveDownloads == 1)

        // The first transfer ignores cancellation until this late completion.
        // Only after it has terminated may the retry own the model.
        runtime.complete(model, attempt: 0)
        try await waitUntil { runtime.activeDownloads == 0 && manager.activity(for: model) == .idle }

        for _ in 0..<100 where runtime.downloadCalls.count == 1 {
            manager.start(model, runtime: runtime)
            await Task.yield()
        }
        try await waitUntil { runtime.downloadCalls == [model, model] }
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

        runtime.complete(model, attempt: 0)
        try await waitUntil { runtime.activeDownloads == 0 && manager.activity(for: model) == .idle }

        for _ in 0..<100 where runtime.downloadCalls.count == 1 {
            manager.start(model, runtime: runtime)
            await Task.yield()
        }
        try await waitUntil { runtime.downloadCalls == [model, model] }

        runtime.reportProgress(0.9, for: model, attempt: 0)
        runtime.fail(model, attempt: 0)
        try await Task.sleep(for: .milliseconds(10))
        #expect(manager.activity(for: model) == .downloading(progress: 0.25))

        runtime.complete(model, attempt: 1)
        try await waitUntil { manager.activity(for: model) == .downloaded }
    }

    @Test("Deleting after cancellation waits for transfer termination before removing storage")
    func cancelledDownloadCannotWriteAfterDelete() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")

        manager.start(model, runtime: runtime)
        try await waitUntil { runtime.downloadCalls == [model] }
        manager.cancel(model)

        manager.delete(model, runtime: runtime)
        try await Task.sleep(for: .milliseconds(10))
        #expect(runtime.deleteCalls.isEmpty)
        #expect(runtime.deleteWhileDownloadActive == false)

        // The delayed cancelled transfer performs its storage write only when
        // its runtime operation finally returns. Delete must happen after it.
        runtime.complete(model, attempt: 0)
        try await waitUntil { manager.activity(for: model) == .idle }

        #expect(runtime.deleteCalls == [model])
        #expect(runtime.writeCount == 1)
        #expect(runtime.writesAtDelete == runtime.writeCount)
        #expect(runtime.deleteWhileDownloadActive == false)
        #expect(runtime.isInstalled(model) == false)
    }

    @Test("Deleting through the catalog manager removes the installed model")
    func catalogManagerDeletesInstalledModel() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        runtime.installedModels = [model]

        manager.delete(model, runtime: runtime)
        try await waitUntil { manager.activity(for: model) == .idle }

        #expect(runtime.deleteCalls == [model])
        #expect(runtime.isInstalled(model) == false)
        #expect(manager.activity(for: model) == .idle)
    }

    @Test("Catalog manager owns and deduplicates a suspended model deletion")
    func catalogManagerOwnsOneDeletePerModel() async throws {
        let runtime = SuspendedDownloadRuntime()
        let manager = CatalogDownloadManager(selectedModel: { nil })
        let model = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        runtime.installedModels = [model]
        runtime.suspendDeletes = true

        manager.delete(model, runtime: runtime)
        try await waitUntil { runtime.deleteCalls == [model] }
        #expect(manager.activity(for: model) == .deleting)

        manager.delete(model, runtime: runtime)
        try await Task.sleep(for: .milliseconds(10))

        #expect(runtime.deleteCalls == [model])
        #expect(manager.activity(for: model) == .deleting)

        runtime.completeDeletes()
        try await waitUntil { manager.activity(for: model) == .idle }
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

    @Test("WhisperKit cancellation retains download ownership until the writer returns")
    func whisperKitCancellationRetainsWriterOwnership() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-owner-\(UUID().uuidString)")
        let downloader = SuspendedWhisperKitDownloader()
        let previousIndex = AppSettings.shared.installedWhisperModels
        defer {
            AppSettings.shared.installedWhisperModels = previousIndex
            try? FileManager.default.removeItem(at: root)
        }
        let service = WhisperKitService(modelsDirectory: root, modelDownloader: { variant, base, progress in
            try await downloader.download(variant: variant, base: base, progress: progress)
        })

        let first = Task { try await service.downloadModel("openai_whisper-small") }
        try await waitUntil { downloader.starts == 1 }
        service.cancelDownload()

        await #expect(throws: WhisperKitService.ServiceError.downloadInProgress) {
            try await service.downloadModel("openai_whisper-small")
        }
        #expect(downloader.maximumActive == 1)
        #expect(service.isDownloading)

        downloader.finish()
        await #expect(throws: WhisperKitService.ServiceError.downloadCancelled) {
            try await first.value
        }
        #expect(!service.isDownloading)
        #expect(downloader.active == 0)
    }

    @Test("WhisperKit delete joins a cancelled setup download before removing its model")
    func whisperKitDeleteJoinsCancelledSetupDownload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-delete-owner-\(UUID().uuidString)")
        let downloader = SuspendedWhisperKitDownloader()
        let variant = "openai_whisper-small"
        let previousIndex = AppSettings.shared.installedWhisperModels
        defer {
            AppSettings.shared.installedWhisperModels = previousIndex
            try? FileManager.default.removeItem(at: root)
        }
        let service = WhisperKitService(modelsDirectory: root, modelDownloader: { variant, base, progress in
            try await downloader.download(variant: variant, base: base, progress: progress)
        })

        let download = Task { try await service.downloadModel(variant) }
        try await waitUntil { downloader.starts == 1 }
        service.cancelDownload()
        let deletion = Task { try await service.deleteModel(variant) }
        for _ in 0..<100 { await Task.yield() }
        #expect(service.isDownloading)
        #expect(downloader.active == 1)

        downloader.finish()
        await #expect(throws: WhisperKitService.ServiceError.downloadCancelled) {
            try await download.value
        }
        try await deletion.value

        let modelFolder = root
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
        #expect(!FileManager.default.fileExists(atPath: modelFolder.path))
        #expect(!AppSettings.shared.installedWhisperModels.contains(variant))
        #expect(downloader.active == 0)
    }

    @Test("WhisperKit delete excludes setup, service downloads, and duplicate deletion through unload")
    func whisperKitDeleteRetainsExclusiveOwnershipThroughUnload() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-delete-fence-\(UUID().uuidString)")
        let variant = "openai_whisper-small"
        let modelFolder = root
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
        let downloader = SuspendedWhisperKitDownloader()
        let unloader = SuspendedWhisperKitUnloader()
        let previousIndex = AppSettings.shared.installedWhisperModels
        defer {
            AppSettings.shared.installedWhisperModels = previousIndex
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        AppSettings.shared.installedWhisperModels = [variant]

        let service = WhisperKitService(
            modelsDirectory: root,
            modelUnloader: { await unloader.unload() },
            modelDownloader: { variant, base, progress in
                try await downloader.download(variant: variant, base: base, progress: progress)
            }
        )
        service.selectedModel = variant

        let deletion = Task { try await service.deleteModel(variant) }
        try await waitUntil { unloader.starts == 1 }
        #expect(service.isModelMutationInProgress)

        let setup = WhisperKitSelectionController(
            currentVariant: { service.selectedModel },
            storeVariant: { service.selectedModel = $0 },
            isDownloaded: { _ in false },
            isDownloadActive: { service.isModelMutationInProgress },
            downloadVariant: { requestedVariant in
                _ = try await service.downloadModel(requestedVariant)
            },
            loadVariant: { _ in },
            cancelDownload: { service.cancelDownload() }
        )
        #expect(!setup.submit(variant) {})
        await #expect(throws: WhisperKitService.ServiceError.downloadInProgress) {
            try await service.downloadModel(variant)
        }

        let duplicateDeletion = Task { try await service.deleteModel(variant) }
        for _ in 0..<100 { await Task.yield() }
        #expect(unloader.starts == 1)
        #expect(downloader.starts == 0)
        #expect(FileManager.default.fileExists(atPath: modelFolder.path))

        unloader.finish()
        try await deletion.value
        try await duplicateDeletion.value

        #expect(!service.isModelMutationInProgress)
        #expect(!FileManager.default.fileExists(atPath: modelFolder.path))
        #expect(!AppSettings.shared.installedWhisperModels.contains(variant))

        #expect(setup.retry())
        try await waitUntil { downloader.starts == 1 }
        downloader.finish()
        try await waitUntil { !setup.isLoading }

        #expect(FileManager.default.fileExists(atPath: modelFolder.path))
        #expect(AppSettings.shared.installedWhisperModels.contains(variant))
        #expect(downloader.maximumActive == 1)
    }

    @Test("WhisperKit deletion failure releases exclusive ownership")
    func whisperKitDeletionFailureReleasesExclusiveOwnership() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("murmeln-whisper-delete-failure-\(UUID().uuidString)")
        let variant = "openai_whisper-small"
        let modelFolder = root
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
        let downloader = SuspendedWhisperKitDownloader()
        let previousIndex = AppSettings.shared.installedWhisperModels
        var removalAttempts = 0
        defer {
            AppSettings.shared.installedWhisperModels = previousIndex
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: modelFolder, withIntermediateDirectories: true)
        AppSettings.shared.installedWhisperModels = [variant]

        let service = WhisperKitService(
            modelsDirectory: root,
            modelFolderRemover: { folder in
                removalAttempts += 1
                if removalAttempts == 1 {
                    throw WhisperKitDeletionFixtureError.removalFailed
                }
                try FileManager.default.removeItem(at: folder)
            },
            modelDownloader: { variant, base, progress in
                try await downloader.download(variant: variant, base: base, progress: progress)
            }
        )

        await #expect(throws: WhisperKitDeletionFixtureError.removalFailed) {
            try await service.deleteModel(variant)
        }
        #expect(!service.isModelMutationInProgress)

        let download = Task { try await service.downloadModel(variant) }
        try await waitUntil { downloader.starts == 1 }
        downloader.finish()
        _ = try await download.value

        try await service.deleteModel(variant)
        #expect(removalAttempts == 2)
        #expect(!service.isModelMutationInProgress)
        #expect(!FileManager.default.fileExists(atPath: modelFolder.path))
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

        await runtime.unload()
        #expect(runtime.state == .notLoaded)

        gate.finish()
        await #expect(throws: CancellationError.self) {
            try await load.value
        }

        #expect(runtime.state == .notLoaded)
        #expect(!runtime.hasResidentEngine)
    }

    @Test("Unloading invalidates an in-flight WhisperKit load")
    func unloadInvalidatesInFlightWhisperKitLoad() async throws {
        let service = SuspendedWhisperKitService()
        let runtime = WhisperKitRuntime(
            service: service,
            variantProvider: { "openai_whisper-small" }
        )

        let load = Task { try await runtime.load(.whisperKit) }
        try await waitUntil { service.loadStarted }

        await runtime.unload()
        #expect(service.unloadCalls == 1)
        #expect(runtime.state == .notLoaded)

        service.completeLoad()
        await #expect(throws: CancellationError.self) {
            try await load.value
        }

        #expect(runtime.state == .notLoaded)
        #expect(runtime.isReady(.whisperKit) == false)
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

    @Test("Catalog WhisperKit selection routes through the runtime")
    func catalogWhisperKitSelectionLoadsThroughRuntime() async throws {
        let modelID = TranscriptionModelID.whisperKit
        let variant = "openai_whisper-medium"
        var runtimeLoads: [TranscriptionModelID] = []
        var legacyLoads: [String] = []

        try await WhisperKitSelectionController.loadSelection(
            variant,
            for: .catalog(modelID),
            loadCatalogModel: { runtimeLoads.append($0) },
            loadLegacyVariant: { legacyLoads.append($0) }
        )

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
        private(set) var loadCalls: [TranscriptionModelID] = []
        private(set) var activeDownloads = 0
        private(set) var maximumActiveDownloads = 0
        private(set) var writeCount = 0
        private(set) var writesAtDelete = 0
        private(set) var deleteWhileDownloadActive = false
        var installedModels: Set<TranscriptionModelID> = []
        var suspendDeletes = false
        var suspendLoads = false
        private var nextAttempt = 0
        private var attemptTokens: [TranscriptionModelID: [Int]] = [:]
        private var continuations: [Int: CheckedContinuation<Void, Error>] = [:]
        private var progressCallbacks: [Int: @MainActor (Double) -> Void] = [:]
        private var deleteContinuations: [CheckedContinuation<Void, Never>] = []
        private var loadContinuations: [CheckedContinuation<Void, Never>] = []

        func isInstalled(_ modelID: TranscriptionModelID) -> Bool {
            installedModels.contains(modelID)
        }

        func download(
            _ modelID: TranscriptionModelID,
            progress: @escaping @MainActor (Double) -> Void
        ) async throws {
            downloadCalls.append(modelID)
            activeDownloads += 1
            maximumActiveDownloads = max(maximumActiveDownloads, activeDownloads)
            defer { activeDownloads -= 1 }
            progress(0.25)
            let attempt = nextAttempt
            nextAttempt += 1
            attemptTokens[modelID, default: []].append(attempt)
            progressCallbacks[attempt] = progress
            try await withCheckedThrowingContinuation { continuation in
                continuations[attempt] = continuation
            }
            installedModels.insert(modelID)
            writeCount += 1
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
            deleteWhileDownloadActive = activeDownloads > 0
            writesAtDelete = writeCount
            if suspendDeletes {
                await withCheckedContinuation { continuation in
                    deleteContinuations.append(continuation)
                }
            }
            installedModels.remove(modelID)
            state = .notLoaded
        }

        func completeDeletes() {
            let continuations = deleteContinuations
            deleteContinuations.removeAll()
            continuations.forEach { $0.resume() }
        }

        func load(_ modelID: TranscriptionModelID) async throws {
            loadCalls.append(modelID)
            if suspendLoads {
                await withCheckedContinuation { continuation in
                    loadContinuations.append(continuation)
                }
            }
            state = .ready(modelID)
        }

        func completeLoads() {
            let continuations = loadContinuations
            loadContinuations.removeAll()
            continuations.forEach { $0.resume() }
        }

        func unload() async {}
        func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String { "" }

        private struct ProbeFailure: Error {}
    }

    @MainActor
    private final class SuspendedWhisperKitDownloader {
        private(set) var starts = 0
        private(set) var active = 0
        private(set) var maximumActive = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func download(
            variant: String,
            base: URL,
            progress: @escaping @Sendable (Progress) -> Void
        ) async throws -> URL {
            starts += 1
            active += 1
            maximumActive = max(maximumActive, active)
            defer { active -= 1 }
            await withCheckedContinuation { continuations.append($0) }

            let folder = base
                .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent(variant)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: folder.appendingPathComponent("weight.fixture"))
            return folder
        }

        func finish() {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    @MainActor
    private final class SuspendedWhisperKitUnloader {
        private(set) var starts = 0
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func unload() async {
            starts += 1
            await withCheckedContinuation { continuations.append($0) }
        }

        func finish() {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    private enum WhisperKitDeletionFixtureError: Error {
        case removalFailed
    }

    private final class SuspendedWhisperKitService:
        WhisperKitTranscribing, WhisperKitModelManaging
    {
        private let modelStateSubject = PassthroughSubject<WhisperKitService.ModelState, Never>()
        private var loadContinuation: CheckedContinuation<Void, Never>?

        var modelState: WhisperKitService.ModelState = .unloaded {
            didSet { modelStateSubject.send(modelState) }
        }
        var selectedModel = ""
        private(set) var loadStarted = false
        private(set) var unloadCalls = 0

        var modelStateChanged: AnyPublisher<WhisperKitService.ModelState, Never> {
            modelStateSubject.eraseToAnyPublisher()
        }

        var downloadProgressChanged: AnyPublisher<Double, Never> {
            Empty().eraseToAnyPublisher()
        }

        func isModelDownloaded(_ variant: String) -> Bool { true }
        func downloadModel(_ variant: String) async throws -> URL {
            FileManager.default.temporaryDirectory
        }
        func cancelDownload() {}
        func deleteModel(_ variant: String) async throws {}

        func unloadModel() async {
            unloadCalls += 1
            modelState = .unloaded
            selectedModel = ""
        }

        func loadModel(_ variant: String) async throws {
            loadStarted = true
            selectedModel = variant
            modelState = .loading
            await withCheckedContinuation { continuation in
                loadContinuation = continuation
            }
            modelState = .ready
        }

        func completeLoad() {
            loadContinuation?.resume()
            loadContinuation = nil
        }

        func transcribe(audioURL: URL) async throws -> String { "" }
        func transcribe(audioURL: URL, languageCode: String?) async throws -> String { "" }
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
