import Combine
import Foundation

enum CatalogDownloadActivity: Equatable {
    case idle
    case downloading(progress: Double)
    case downloaded
    case deleting
    case failed(String)
}

/// App-lifetime, model-keyed ownership for catalog downloads. Settings rows
/// are transient views over this state: switching selection never cancels or
/// forgets an in-flight transfer, and distinct model IDs may download in
/// parallel. A repeated request for the same model is deduplicated.
@MainActor
final class CatalogDownloadManager: ObservableObject {
    static let shared = CatalogDownloadManager()

    private struct Transfer {
        let generation: UInt64
        let task: Task<Void, Never>
        let cancelRuntimeDownload: @MainActor () -> Void
    }

    @Published private var activities: [TranscriptionModelID: CatalogDownloadActivity] = [:]
    private var transfers: [TranscriptionModelID: Transfer] = [:]
    private var nextGeneration: UInt64 = 0
    private let selectedModel: @MainActor () -> TranscriptionModelID?

    init(selectedModel: @escaping @MainActor () -> TranscriptionModelID? = {
        AppSettings.shared.selectedModelID
    }) {
        self.selectedModel = selectedModel
    }

    func activity(for modelID: TranscriptionModelID) -> CatalogDownloadActivity {
        activities[modelID] ?? .idle
    }

    func start(_ modelID: TranscriptionModelID, runtime: any TranscriptionRuntime) {
        guard transfers[modelID] == nil else { return }
        guard activities[modelID] != .deleting else { return }

        nextGeneration &+= 1
        let generation = nextGeneration
        activities[modelID] = .downloading(progress: 0)

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await runtime.download(modelID) { progress in
                    self.acceptProgress(progress, for: modelID, generation: generation)
                }
                try Task.checkCancellation()
            } catch is CancellationError {
                guard self.owns(generation, for: modelID) else { return }
                self.activities[modelID] = .idle
                self.transfers[modelID] = nil
                return
            } catch {
                guard self.owns(generation, for: modelID) else { return }
                self.activities[modelID] = .failed(error.localizedDescription)
                self.transfers[modelID] = nil
                return
            }

            guard self.owns(generation, for: modelID) else { return }
            self.activities[modelID] = .downloaded
            self.transfers[modelID] = nil

            // Preserve eager-ready behavior only when the model that finished
            // is still selected. A later selection transition loads it when
            // the user returns.
            if self.selectedModel() == modelID {
                try? await runtime.load(modelID)
            }
        }
        transfers[modelID] = Transfer(
            generation: generation,
            task: task,
            cancelRuntimeDownload: { runtime.cancelDownload(modelID) }
        )
    }

    func cancel(_ modelID: TranscriptionModelID) {
        guard let transfer = transfers.removeValue(forKey: modelID) else { return }
        transfer.task.cancel()
        transfer.cancelRuntimeDownload()
        activities[modelID] = .idle
    }

    func delete(_ modelID: TranscriptionModelID, runtime: any TranscriptionRuntime) async {
        guard transfers[modelID] == nil else { return }
        activities[modelID] = .deleting
        do {
            try await runtime.delete(modelID)
            activities[modelID] = .idle
        } catch {
            activities[modelID] = .failed(error.localizedDescription)
        }
    }

    private func acceptProgress(
        _ progress: Double,
        for modelID: TranscriptionModelID,
        generation: UInt64
    ) {
        guard owns(generation, for: modelID) else { return }
        guard case .downloading(let current) = activities[modelID] else { return }
        let clamped = min(max(progress, 0), 1)
        activities[modelID] = .downloading(progress: max(current, clamped))
    }

    private func owns(_ generation: UInt64, for modelID: TranscriptionModelID) -> Bool {
        transfers[modelID]?.generation == generation
    }
}
