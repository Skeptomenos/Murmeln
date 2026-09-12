import Combine
import Foundation

enum CatalogDownloadActivity: Equatable {
    case idle
    case downloading(progress: Double)
    case downloaded
    case deleting
    case failed(String)
}

/// App-lifetime, model-keyed ownership for catalog asset operations. Settings
/// rows are transient views over this state: switching selection never cancels
/// or forgets an in-flight transfer, distinct model IDs may download in
/// parallel, and repeated download or deletion requests are deduplicated.
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
    private var deletions: [
        TranscriptionModelID: (generation: UInt64, task: Task<Void, Never>)
    ] = [:]
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
        guard deletions[modelID] == nil else { return }

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
                self.activities[modelID] = self.deletions[modelID] == nil ? .idle : .deleting
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

            // Preserve eager-ready behavior only when the model that finished
            // is still selected. A later selection transition loads it when
            // the user returns.
            if self.selectedModel() == modelID {
                do {
                    try await runtime.load(modelID)
                    try Task.checkCancellation()
                } catch {
                    // Assets are downloaded even when eager loading is
                    // cancelled or fails. The runtime publishes its own load
                    // state; this manager only releases operation ownership.
                    guard self.owns(generation, for: modelID) else { return }
                    self.transfers[modelID] = nil
                    return
                }
            }

            guard self.owns(generation, for: modelID) else { return }
            self.transfers[modelID] = nil
        }
        transfers[modelID] = Transfer(
            generation: generation,
            task: task,
            cancelRuntimeDownload: { runtime.cancelDownload(modelID) }
        )
    }

    func cancel(_ modelID: TranscriptionModelID) {
        // Keep the transfer owned until its runtime operation has returned.
        // Task cancellation alone does not prove that the cache writer stopped.
        guard let transfer = transfers[modelID] else { return }
        transfer.task.cancel()
        transfer.cancelRuntimeDownload()
        activities[modelID] = .idle
    }

    func delete(_ modelID: TranscriptionModelID, runtime: any TranscriptionRuntime) {
        guard deletions[modelID] == nil else { return }

        nextGeneration &+= 1
        let generation = nextGeneration
        activities[modelID] = .deleting

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let transfer = self.transfers[modelID] {
                // Deletion shares the model-cache ownership boundary with retry:
                // cancel and join the old transfer before removing its files.
                transfer.task.cancel()
                transfer.cancelRuntimeDownload()
                await transfer.task.value
            }
            guard self.ownsDeletion(generation, for: modelID) else { return }
            guard self.transfers[modelID] == nil else { return }
            do {
                try await runtime.delete(modelID)
            } catch is CancellationError {
                guard self.ownsDeletion(generation, for: modelID) else { return }
                self.activities[modelID] = .idle
                self.deletions[modelID] = nil
                return
            } catch {
                guard self.ownsDeletion(generation, for: modelID) else { return }
                self.activities[modelID] = .failed(error.localizedDescription)
                self.deletions[modelID] = nil
                return
            }

            guard self.ownsDeletion(generation, for: modelID) else { return }
            self.activities[modelID] = .idle
            self.deletions[modelID] = nil
        }
        deletions[modelID] = (generation: generation, task: task)
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

    private func ownsDeletion(_ generation: UInt64, for modelID: TranscriptionModelID) -> Bool {
        deletions[modelID]?.generation == generation
    }
}
