import Combine
import Foundation
@testable import mrml

/// Scriptable TranscriptionRuntime for adapter tests (Slice 2+). Records
/// every call; behavior is configured per test via the `on*` closures.
@MainActor
final class MockRuntime: TranscriptionRuntime {
    let id: RuntimeID
    private(set) var state: RuntimeState = .notLoaded {
        didSet {
            observedStates.append(state)
            stateSubject.send(state)
        }
    }

    private let stateSubject = PassthroughSubject<RuntimeState, Never>()
    var stateChanged: AnyPublisher<RuntimeState, Never> { stateSubject.eraseToAnyPublisher() }

    /// Every state the runtime passed through (for observation assertions).
    private(set) var observedStates: [RuntimeState] = []

    private(set) var downloadCalls: [TranscriptionModelID] = []
    private(set) var cancelDownloadCalls: [TranscriptionModelID] = []
    private(set) var deleteCalls: [TranscriptionModelID] = []
    private(set) var loadCalls: [TranscriptionModelID] = []
    private(set) var unloadCalls = 0
    private(set) var transcribeCalls: [(audioURL: URL, options: TranscriptionOptions)] = []

    var installedModels: Set<TranscriptionModelID> = []
    var onTranscribe: ((URL, TranscriptionOptions) throws -> String) = { _, _ in "mock transcript" }
    var onLoad: ((TranscriptionModelID) throws -> Void)?
    var onDownload: ((TranscriptionModelID) throws -> Void)?

    init(id: RuntimeID = .fluidAudio) {
        self.id = id
    }

    func isInstalled(_ modelID: TranscriptionModelID) -> Bool {
        installedModels.contains(modelID)
    }

    func download(
        _ modelID: TranscriptionModelID,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        downloadCalls.append(modelID)
        state = .downloading(progress: 0)
        try onDownload?(modelID)
        progress(1.0)
        installedModels.insert(modelID)
        state = .notLoaded
    }

    func cancelDownload(_ modelID: TranscriptionModelID) {
        cancelDownloadCalls.append(modelID)
    }

    func delete(_ modelID: TranscriptionModelID) async throws {
        deleteCalls.append(modelID)
        installedModels.remove(modelID)
        if case .ready(let loadedID) = state, loadedID == modelID {
            state = .notLoaded
        }
    }

    func load(_ modelID: TranscriptionModelID) async throws {
        loadCalls.append(modelID)
        state = .loading(modelID)
        if let onLoad {
            do {
                try onLoad(modelID)
            } catch {
                state = .failed(error.localizedDescription)
                throw error
            }
        }
        guard installedModels.contains(modelID) else {
            state = .failed("not installed")
            throw TranscriptionRuntimeError.modelNotInstalled(modelID)
        }
        state = .ready(modelID)
    }

    func unload() {
        unloadCalls += 1
        state = .notLoaded
    }

    func transcribe(audioURL: URL, options: TranscriptionOptions) async throws -> String {
        transcribeCalls.append((audioURL, options))
        guard case .ready = state else {
            throw TranscriptionRuntimeError.runtimeNotReady(id)
        }
        return try onTranscribe(audioURL, options)
    }
}
