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
    func unload()

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
    typealias RuntimeResolver = @MainActor (TranscriptionModelID) -> (any TranscriptionRuntime)?

    private let runtimeForModel: RuntimeResolver

    init(runtimeForModel: @escaping RuntimeResolver) {
        self.runtimeForModel = runtimeForModel
    }

    func apply(_ transition: AppSettings.TranscriptionSelectionTransition) async {
        guard transition.previous != transition.current else { return }

        if case .catalog(let previousID) = transition.previous {
            runtimeForModel(previousID)?.unload()
        }

        guard case .catalog(let currentID) = transition.current,
              let runtime = runtimeForModel(currentID),
              runtime.isInstalled(currentID)
        else { return }

        do {
            try await runtime.load(currentID)
        } catch {
            // Runtime state carries the failure for the settings UI. AppDelegate
            // logs the localized description through its normal lifecycle path.
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
