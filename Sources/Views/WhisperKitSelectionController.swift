import Foundation
import Observation

@MainActor
@Observable
final class WhisperKitSelectionController {
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var canRetry: Bool {
        errorMessage != nil && retryVariant != nil && !isLoading
    }

    var canCancel: Bool {
        isLoading || errorMessage != nil
    }

    @ObservationIgnored private let currentVariant: @MainActor () -> String
    @ObservationIgnored private let storeVariant: @MainActor (String) -> Void
    @ObservationIgnored private let isDownloaded: @MainActor (String) -> Bool
    @ObservationIgnored private let isDownloadActive: @MainActor () -> Bool
    @ObservationIgnored private let downloadVariant: @MainActor (String) async throws -> Void
    @ObservationIgnored private let loadVariant: @MainActor (String) async throws -> Void
    @ObservationIgnored private let cancelDownload: @MainActor () -> Void
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var retryVariant: String?
    @ObservationIgnored private var retrySuccess: (@MainActor () -> Void)?
    @ObservationIgnored private var previousVariant: String?
    @ObservationIgnored private var candidateStored = false
    @ObservationIgnored private var ownsDownload = false

    init(
        runtimeRegistry: TranscriptionRuntimeRegistry = .shared,
        currentSelection: @escaping @MainActor () -> AppSettings.TranscriptionSelection = {
            AppSettings.shared.transcriptionSelection
        },
        currentVariant: @escaping @MainActor () -> String = {
            AppSettings.shared.whisperKitModel
        },
        storeVariant: @escaping @MainActor (String) -> Void = { variant in
            let settings = AppSettings.shared
            settings.whisperKitModel = variant
            if case .legacy(.whisperKit) = settings.transcriptionSelection {
                settings.transcriptionModel = variant
            }
        },
        isDownloaded: @escaping @MainActor (String) -> Bool = { variant in
            WhisperKitService.shared.isModelDownloaded(variant)
        },
        isDownloadActive: @escaping @MainActor () -> Bool = {
            WhisperKitService.shared.isModelMutationInProgress
        },
        downloadVariant: @escaping @MainActor (String) async throws -> Void = { variant in
            _ = try await WhisperKitService.shared.downloadModel(variant)
        },
        loadVariant: (@MainActor (String) async throws -> Void)? = nil,
        cancelDownload: @escaping @MainActor () -> Void = {
            WhisperKitService.shared.cancelDownload()
        }
    ) {
        self.currentVariant = currentVariant
        self.storeVariant = storeVariant
        self.isDownloaded = isDownloaded
        self.isDownloadActive = isDownloadActive
        self.downloadVariant = downloadVariant
        self.loadVariant = loadVariant ?? { variant in
            try await WhisperKitSelectionController.loadSelection(
                variant,
                for: currentSelection(),
                loadCatalogModel: { modelID in
                    guard let runtime = runtimeRegistry.runtime(forModel: modelID) else {
                        throw TranscriptionRuntimeError.unsupportedModel(modelID, .whisperKit)
                    }
                    try await runtime.load(modelID)
                },
                loadLegacyVariant: { selected in
                    try await WhisperKitService.shared.loadModel(selected)
                }
            )
        }
        self.cancelDownload = cancelDownload
    }

    static func loadSelection(
        _ variant: String,
        for selection: AppSettings.TranscriptionSelection,
        loadCatalogModel: @MainActor (TranscriptionModelID) async throws -> Void,
        loadLegacyVariant: @MainActor (String) async throws -> Void
    ) async throws {
        switch selection {
        case .catalog(let modelID) where modelID == .whisperKit:
            try await loadCatalogModel(modelID)
        case .legacy(.whisperKit):
            try await loadLegacyVariant(variant)
        case .catalog, .legacy:
            break
        }
    }

    @discardableResult
    func submit(
        _ variant: String,
        onSuccess: @escaping @MainActor () -> Void
    ) -> Bool {
        guard operationTask == nil else { return false }

        retryVariant = variant
        retrySuccess = onSuccess
        errorMessage = nil

        let requiresDownload = !isDownloaded(variant)
        guard !requiresDownload || !isDownloadActive() else {
            isLoading = false
            previousVariant = nil
            candidateStored = false
            errorMessage = "Another WhisperKit model operation is already in progress. Wait for it to finish, then Retry or Cancel."
            return false
        }

        isLoading = true
        previousVariant = currentVariant()
        candidateStored = false
        operationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                if requiresDownload {
                    ownsDownload = true
                    do {
                        try await downloadVariant(variant)
                        ownsDownload = false
                    } catch {
                        ownsDownload = false
                        throw error
                    }
                }
                try Task.checkCancellation()

                storeVariant(variant)
                candidateStored = true
                try await loadVariant(variant)
                try Task.checkCancellation()

                completeSuccess(onSuccess)
            } catch {
                restorePreviousVariantIfNeeded()
                if error is CancellationError || Task.isCancelled {
                    completeCancellation()
                } else {
                    completeFailure(variant: variant, error: error)
                }
            }
        }

        return true
    }

    @discardableResult
    func retry() -> Bool {
        guard canRetry, let retryVariant, let retrySuccess else { return false }
        return submit(retryVariant, onSuccess: retrySuccess)
    }

    func cancel() {
        if ownsDownload {
            cancelDownload()
            ownsDownload = false
        }
        operationTask?.cancel()
        restorePreviousVariantIfNeeded()

        if operationTask == nil {
            errorMessage = nil
            retryVariant = nil
            retrySuccess = nil
        }
    }

    private func restorePreviousVariantIfNeeded() {
        guard candidateStored, let previousVariant else { return }
        storeVariant(previousVariant)
        candidateStored = false
    }

    private func completeSuccess(_ onSuccess: @MainActor () -> Void) {
        operationTask = nil
        isLoading = false
        errorMessage = nil
        previousVariant = nil
        candidateStored = false
        ownsDownload = false
        retryVariant = nil
        retrySuccess = nil
        onSuccess()
    }

    private func completeFailure(variant: String, error: Error) {
        operationTask = nil
        isLoading = false
        previousVariant = nil
        candidateStored = false
        ownsDownload = false
        errorMessage = "Could not load \(variant). \(error.localizedDescription). Retry or Cancel."
    }

    private func completeCancellation() {
        operationTask = nil
        isLoading = false
        errorMessage = nil
        previousVariant = nil
        candidateStored = false
        ownsDownload = false
        retryVariant = nil
        retrySuccess = nil
    }
}
