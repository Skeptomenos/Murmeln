import Combine
import Foundation

@MainActor
protocol WhisperKitModelManaging: AnyObject, Sendable {
    var modelStateChanged: AnyPublisher<WhisperKitService.ModelState, Never> { get }
    var downloadProgressChanged: AnyPublisher<Double, Never> { get }

    func isModelDownloaded(_ variant: String) -> Bool
    func downloadModel(_ variant: String) async throws -> URL
    func cancelDownload()
    func deleteModel(_ variant: String) async throws
    func unloadModel() async
}

extension WhisperKitService: WhisperKitModelManaging {
    var modelStateChanged: AnyPublisher<ModelState, Never> {
        $modelState.eraseToAnyPublisher()
    }

    var downloadProgressChanged: AnyPublisher<Double, Never> {
        // @Published replays the previous attempt's last value to each new
        // subscriber. The download itself immediately publishes a fresh zero,
        // so ignore only that cached replay and forward the new attempt.
        $downloadProgress.dropFirst().eraseToAnyPublisher()
    }
}

/// Slice 2: TranscriptionRuntime facade over the existing WhisperKitService
/// (wrapped, not modified). The catalog's `whisperkit` entry delegates the
/// concrete Whisper variant to the existing `whisperKitModel` setting, so
/// `load` resolves the variant at call time via `variantProvider`.
@MainActor
final class WhisperKitRuntime: TranscriptionRuntime {
    static let shared = WhisperKitRuntime()

    let id: RuntimeID = .whisperKit

    private let service: any WhisperKitTranscribing & WhisperKitModelManaging
    /// Resolves the concrete Whisper variant (e.g. "openai_whisper-small").
    private let variantProvider: () -> String
    private var stateObservation: AnyCancellable?
    private var loadedVariant: String?

    init(
        service: any WhisperKitTranscribing & WhisperKitModelManaging = WhisperKitService.shared,
        variantProvider: @escaping () -> String = { AppSettings.shared.whisperKitModel }
    ) {
        self.service = service
        self.variantProvider = variantProvider
        // Slice 5c/F1: re-emit the concrete service's @Published modelState as
        // our RuntimeState so catalog rows observing `stateChanged` repaint on
        // WhisperKit transitions the same way they do for FluidAudio.
        stateObservation = service.modelStateChanged
            .sink { [weak self] modelState in
                guard let self else { return }
                switch modelState {
                case .unloaded, .error:
                    loadedVariant = nil
                case .ready, .loading, .downloading:
                    break
                }
                stateSubject.send(runtimeState(from: modelState))
            }
    }

    private let stateSubject = PassthroughSubject<RuntimeState, Never>()
    var stateChanged: AnyPublisher<RuntimeState, Never> { stateSubject.eraseToAnyPublisher() }

    private func runtimeState(from modelState: WhisperKitService.ModelState) -> RuntimeState {
        switch modelState {
        case .ready:
            guard loadedVariant == variantProvider() else { return .notLoaded }
            return .ready(.whisperKit)
        case .loading, .downloading:
            return .loading(.whisperKit)
        case .unloaded:
            return .notLoaded
        case .error(let message):
            return .failed(message)
        }
    }

    var state: RuntimeState {
        runtimeState(from: service.modelState)
    }

    func isInstalled(_ modelID: TranscriptionModelID) -> Bool {
        // WhisperKitService owns variant download/scan; the runtime treats the
        // currently selected variant's readiness as installedness. Refined in
        // Slice 4 when the model manager UI generalizes.
        service.isModelDownloaded(variantProvider())
    }

    func isReady(_ modelID: TranscriptionModelID) -> Bool {
        guard modelID == .whisperKit,
              case .ready = service.modelState
        else { return false }
        return loadedVariant == variantProvider()
    }

    func download(
        _ modelID: TranscriptionModelID,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let variant = variantProvider()
        let progressObservation = service.downloadProgressChanged
            .sink { fraction in progress(fraction) }
        defer { progressObservation.cancel() }

        _ = try await service.downloadModel(variant)
        progress(1.0)
    }

    func cancelDownload(_ modelID: TranscriptionModelID) {
        guard modelID == .whisperKit else { return }
        service.cancelDownload()
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        guard modelID == .whisperKit else {
            throw TranscriptionRuntimeError.unsupportedModel(modelID, id)
        }
        let variant = variantProvider()
        try await service.deleteModel(variant)
        if loadedVariant == variant {
            loadedVariant = nil
            stateSubject.send(.notLoaded)
        }
    }

    func load(_ modelID: TranscriptionModelID) async throws {
        let variant = variantProvider()
        try await service.loadModel(variant)
        loadedVariant = variant
        stateSubject.send(state)
    }

    func unload() {
        loadedVariant = nil
        stateSubject.send(.notLoaded)
        Task { await service.unloadModel() }
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        let modelID = TranscriptionModelID.whisperKit
        guard isReady(modelID) else {
            throw TranscriptionRuntimeError.runtimeNotReady(id)
        }
        return try await service.transcribe(
            audioURL: audioURL,
            languageCode: options.languageCode
        )
    }
}
