import Combine
import Foundation

/// Lifecycle state of a runtime with respect to one selected model.
enum RuntimeState: Equatable, Sendable {
    case notLoaded
    /// progress in 0...1; -1 when indeterminate.
    case downloading(progress: Double)
    case loading(TranscriptionModelID)
    case ready(TranscriptionModelID)
    case failed(String)
}

/// Per-request options resolved by the pipeline from settings + catalog
/// capabilities (a hint is passed only when the entry's languageMode
/// requires or accepts one).
struct TranscriptionOptions: Equatable, Sendable {
    /// ISO 639-1 code; nil = let the model auto-detect.
    let languageCode: String?

    init(languageCode: String? = nil) {
        self.languageCode = languageCode
    }
}

/// An inference engine that can install, load, and run catalog models.
/// Implementations: WhisperKitRuntime (Slice 2), FluidAudioRuntime (Slice 3),
/// later MLXAudioRuntime / AppleSpeechRuntime. The protocol must not assume
/// models come from HuggingFace or need downloading at all.
@MainActor
protocol TranscriptionRuntime: AnyObject, Sendable {
    var id: RuntimeID { get }
    var state: RuntimeState { get }

    /// Emits the new state on every transition. SwiftUI settings rows observe
    /// this so an async `load()`/`download()` completion actually repaints
    /// (Slice 5c/F1: a plain stored `state` never notified the view, leaving a
    /// permanent "Loading…" spinner). Publishes on the main actor.
    var stateChanged: AnyPublisher<RuntimeState, Never> { get }

    /// True when the model's assets are present locally (no download needed).
    func isInstalled(_ modelID: TranscriptionModelID) -> Bool

    /// True only when this exact catalog selection is resident and usable.
    /// Runtimes with a second identity layer (for example WhisperKit variants)
    /// override this to include that concrete identity.
    func isReady(_ modelID: TranscriptionModelID) -> Bool

    /// Fetch model assets. Reports coarse progress via the callback;
    /// implementations that need no download return immediately.
    func download(
        _ modelID: TranscriptionModelID,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws

    /// Cancel an explicit download for this model. Implementations with an
    /// inner task (for example WhisperKitService) must forward cancellation;
    /// implementations whose download is the caller task may be a no-op.
    func cancelDownload(_ modelID: TranscriptionModelID)

    /// Remove this model's installed assets and unload it if resident.
    /// Must not touch caches or engines belonging to other model IDs.
    func delete(_ modelID: TranscriptionModelID) async throws

    /// Load the model into memory / warm it. On success `state == .ready(modelID)`.
    /// Load-only: MUST NOT download. Throws `.modelNotInstalled` when the
    /// model's assets are absent (Slice 5c/P1.1 — downloading happens solely
    /// through `download(_:progress:)` so a first dictation can never silently
    /// pull multi-GB weights).
    func load(_ modelID: TranscriptionModelID) async throws

    /// Release the loaded model. `state` returns to `.notLoaded`.
    func unload() async

    /// Transcribe a complete audio file. Requires `state == .ready`.
    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String
}

extension TranscriptionRuntime {
    func isReady(_ modelID: TranscriptionModelID) -> Bool {
        state == .ready(modelID)
    }
}

/// Owns the memory lifecycle for a complete catalog/legacy selection change.
/// Keeping this transition outside the settings view prevents a local runtime
/// from remaining resident when the user returns to a cloud/server provider.
@MainActor
final class TranscriptionSelectionLifecycle {
    typealias LoadFailureHandler = @MainActor (TranscriptionModelID, Error) -> Void
    typealias MissingModelHandler = @MainActor (TranscriptionModelID) -> Void

    private let runtimeRegistry: TranscriptionRuntimeRegistry
    private let onLoadFailure: LoadFailureHandler
    private let onMissingModel: MissingModelHandler
    private var selectionTask: Task<Void, Never>?
    private var operationGeneration: UInt = 0

    init(
        runtimeRegistry: TranscriptionRuntimeRegistry,
        onLoadFailure: @escaping LoadFailureHandler = { _, _ in },
        onMissingModel: @escaping MissingModelHandler = { _ in }
    ) {
        self.runtimeRegistry = runtimeRegistry
        self.onLoadFailure = onLoadFailure
        self.onMissingModel = onMissingModel
    }

    /// Start launch warm-up through the same task owner used for later model
    /// changes. A selection submitted while this runs replaces it.
    func warm(_ selection: AppSettings.TranscriptionSelection) {
        replace(previous: nil, current: selection)
    }

    func apply(_ transition: AppSettings.TranscriptionSelectionTransition) {
        guard transition.previous != transition.current else { return }
        replace(previous: transition.previous, current: transition.current)
    }

    /// Cancel and join the complete task chain before the app exits. Joining is
    /// required because a runtime can finish an await after it observes
    /// cancellation; that late completion must be cleaned up before return.
    func cancel() async {
        operationGeneration &+= 1
        let cancellationGeneration = operationGeneration
        let task = selectionTask
        task?.cancel()
        await task?.value
        if operationGeneration == cancellationGeneration {
            selectionTask = nil
        }
    }

    /// Await the current owned operation. This is intentionally internal so
    /// deterministic lifecycle tests need no sleeps or polling for completion.
    func waitUntilIdle() async {
        await selectionTask?.value
    }

    private func replace(
        previous: AppSettings.TranscriptionSelection?,
        current: AppSettings.TranscriptionSelection
    ) {
        operationGeneration &+= 1
        let supersededTask = selectionTask
        supersededTask?.cancel()

        selectionTask = Task { @MainActor [weak self] in
            await supersededTask?.value
            guard let self, !Task.isCancelled else { return }
            await self.perform(previous: previous, current: current)
        }
    }

    private func perform(
        previous: AppSettings.TranscriptionSelection?,
        current: AppSettings.TranscriptionSelection
    ) async {
        var currentRuntime: (any TranscriptionRuntime)?

        do {
            try Task.checkCancellation()

            if case .catalog(let previousID) = previous {
                await runtimeRegistry.runtime(forModel: previousID)?.unload()
            }

            try Task.checkCancellation()
            guard case .catalog(let currentID) = current,
                  let runtime = runtimeRegistry.runtime(forModel: currentID)
            else { return }

            currentRuntime = runtime
            guard runtime.isInstalled(currentID) else {
                onMissingModel(currentID)
                return
            }

            try await runtime.load(currentID)
            try Task.checkCancellation()
        } catch is CancellationError {
            // A runtime also uses CancellationError when a newer external
            // owner invalidates this load generation. Only this lifecycle's
            // own task cancellation authorizes cleanup of the shared runtime.
            if Task.isCancelled {
                await currentRuntime?.unload()
            }
        } catch {
            // Runtime state carries the failure for the settings UI. AppDelegate
            // also records the localized description through its lifecycle log.
            if case .catalog(let currentID) = current {
                onLoadFailure(currentID, error)
            }
        }
    }
}

enum RuntimeOperation: String, Equatable, Sendable {
    case download
    case load
    case transcribe
}

enum TranscriptionRuntimeError: Error, LocalizedError, Equatable {
    case modelNotInstalled(TranscriptionModelID)
    case runtimeNotReady(RuntimeID)
    case unsupportedModel(TranscriptionModelID, RuntimeID)
    case runtimeFailure(RuntimeID, RuntimeOperation, String)

    var errorDescription: String? {
        switch self {
        case .modelNotInstalled(let id):
            return "Model '\(id.rawValue)' is not downloaded yet."
        case .runtimeNotReady(let runtime):
            return "\(runtime.rawValue) runtime is not ready. Load a model first."
        case .unsupportedModel(let id, let runtime):
            return "Model '\(id.rawValue)' is not served by the \(runtime.rawValue) runtime."
        case .runtimeFailure(let runtime, let operation, let message):
            return "\(runtime.rawValue) \(operation.rawValue) failed: \(message)"
        }
    }
}
