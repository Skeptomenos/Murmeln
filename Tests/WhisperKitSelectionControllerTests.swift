import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("WhisperKit Selection Controller Tests")
struct WhisperKitSelectionControllerTests {
    @Test("Catalog selection loads the injected registry runtime")
    func catalogSelectionLoadsInjectedRegistryRuntime() async {
        let state = WhisperKitSelectionControllerTestState()
        let fluidAudio = MockRuntime(id: .fluidAudio)
        let whisperKit = MockRuntime(id: .whisperKit)
        whisperKit.installedModels = [.whisperKit]
        let registry = TranscriptionRuntimeRegistry(runtimes: [
            .fluidAudio: fluidAudio,
            .whisperKit: whisperKit,
        ])
        let controller = WhisperKitSelectionController(
            runtimeRegistry: registry,
            currentSelection: { .catalog(.whisperKit) },
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            cancelDownload: {}
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { !controller.isLoading }

        #expect(whisperKit.loadCalls == [.whisperKit])
        #expect(fluidAudio.loadCalls.isEmpty)
        #expect(state.dismissCount == 1)
    }

    @Test("Failed load restores the previous selection and exposes Retry and Cancel")
    func failedLoadRestoresPreviousSelectionAndExposesRetry() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            loadVariant: { _ in
                throw NSError(
                    domain: "WhisperKitSelectionControllerTests",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Model is unavailable"]
                )
            },
            cancelDownload: {}
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { !controller.isLoading }

        #expect(state.persistedVariant == "openai_whisper-small")
        #expect(state.dismissCount == 0)
        #expect(controller.errorMessage?.contains("Model is unavailable") == true)
        #expect(controller.errorMessage?.contains("Retry or Cancel") == true)
        #expect(controller.canRetry)
        #expect(controller.canCancel)
    }

    @Test("Successful load persists selection and dismisses exactly once after completion")
    func successfulLoadPersistsSelectionAndDismissesExactlyOnce() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in false },
            isDownloadActive: { false },
            downloadVariant: { state.downloadedVariants.append($0) },
            loadVariant: { variant in
                #expect(state.downloadedVariants == [variant])
                state.loadStarted = true
                while !state.releaseLoad {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            },
            cancelDownload: { state.cancelDownloadCount += 1 }
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { state.loadStarted }
        #expect(state.dismissCount == 0)

        state.releaseLoad = true
        await waitUntil { !controller.isLoading }

        #expect(state.persistedVariant == "openai_whisper-medium")
        #expect(state.downloadedVariants == ["openai_whisper-medium"])
        #expect(state.dismissCount == 1)
        #expect(controller.errorMessage == nil)

        controller.cancel()
        #expect(state.cancelDownloadCount == 0)
    }

    @Test("Retry loads the same variant and dismisses once after success")
    func retryAfterFailureLoadsTheSameVariantAndDismissesOnce() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            loadVariant: { variant in
                state.loadedVariants.append(variant)
                if state.loadedVariants.count == 1 {
                    throw NSError(
                        domain: "WhisperKitSelectionControllerTests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "First load failed"]
                    )
                }
            },
            cancelDownload: {}
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { !controller.isLoading }
        #expect(controller.canRetry)

        #expect(controller.retry())
        await waitUntil { !controller.isLoading }

        #expect(state.loadedVariants == ["openai_whisper-medium", "openai_whisper-medium"])
        #expect(state.persistedVariant == "openai_whisper-medium")
        #expect(controller.errorMessage == nil)
        #expect(state.dismissCount == 1)
    }

    @Test("Second submission while loading is ignored")
    func secondSubmissionWhileLoadingIsIgnored() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            loadVariant: { _ in
                state.loadCount += 1
                while !state.releaseLoad {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            },
            cancelDownload: {}
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { state.loadCount == 1 }
        #expect(!controller.submit("openai_whisper-large-v3") { state.dismissCount += 1 })
        #expect(state.loadCount == 1)

        state.releaseLoad = true
        await waitUntil { !controller.isLoading }

        #expect(state.persistedVariant == "openai_whisper-medium")
        #expect(state.dismissCount == 1)
    }

    @Test("Cancel stops the owned task and prevents a late commit")
    func cancelStopsOwnedTaskAndPreventsLateCommit() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            loadVariant: { _ in
                state.loadStarted = true
                do {
                    while true {
                        try Task.checkCancellation()
                        await Task.yield()
                    }
                } catch is CancellationError {
                    state.cancellationObserved = true
                    throw CancellationError()
                }
            },
            cancelDownload: { state.cancelDownloadCount += 1 }
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { state.loadStarted }
        controller.cancel()
        await waitUntil { state.cancellationObserved }

        #expect(state.persistedVariant == "openai_whisper-small")
        #expect(state.dismissCount == 0)
        #expect(controller.errorMessage == nil)
        #expect(!controller.isLoading)
        #expect(state.cancelDownloadCount == 0)
    }

    @Test("Cancel without a submission does not cancel a shared download")
    func cancelWithoutSubmissionDoesNotCancelSharedDownload() {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in false },
            isDownloadActive: { state.externalDownloadActive },
            downloadVariant: { _ in },
            loadVariant: { _ in },
            cancelDownload: { state.cancelDownloadCount += 1 }
        )

        controller.cancel()

        #expect(state.cancelDownloadCount == 0)
    }

    @Test("Cancel during an owned download forwards cancellation exactly once")
    func cancelDuringOwnedDownloadForwardsCancellationExactlyOnce() async {
        let state = WhisperKitSelectionControllerTestState()
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in false },
            isDownloadActive: { false },
            downloadVariant: { _ in
                state.downloadStarted = true
                while true {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            },
            loadVariant: { _ in },
            cancelDownload: { state.cancelDownloadCount += 1 }
        )

        #expect(controller.submit("openai_whisper-medium") { state.dismissCount += 1 })
        await waitUntil { state.downloadStarted }
        controller.cancel()
        await waitUntil { !controller.isLoading }

        #expect(state.cancelDownloadCount == 1)
        #expect(state.persistedVariant == "openai_whisper-small")
        #expect(state.dismissCount == 0)
    }

    @Test("An externally active download blocks submission and remains retryable")
    func externallyActiveDownloadBlocksSubmissionAndRemainsRetryable() async {
        let state = WhisperKitSelectionControllerTestState()
        state.externalDownloadActive = true
        let controller = WhisperKitSelectionController(
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in false },
            isDownloadActive: { state.externalDownloadActive },
            downloadVariant: { state.downloadedVariants.append($0) },
            loadVariant: { _ in },
            cancelDownload: { state.cancelDownloadCount += 1 }
        )

        let accepted = controller.submit("openai_whisper-medium") { state.dismissCount += 1 }
        await waitUntil { !controller.isLoading }

        #expect(!accepted)
        #expect(state.downloadedVariants.isEmpty)
        #expect(state.dismissCount == 0)
        #expect(controller.errorMessage?.contains("already in progress") == true)
        #expect(controller.canRetry)

        state.externalDownloadActive = false
        #expect(controller.retry())
        await waitUntil { !controller.isLoading }

        #expect(state.downloadedVariants == ["openai_whisper-medium"])
        #expect(state.persistedVariant == "openai_whisper-medium")
        #expect(state.dismissCount == 1)
        #expect(state.cancelDownloadCount == 0)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<1_000 {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for condition", sourceLocation: sourceLocation)
    }
}
