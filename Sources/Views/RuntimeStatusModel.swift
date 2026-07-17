import Combine
import Foundation

/// Slice 5c/F1: bridges a runtime's `stateChanged` publisher into an
/// `@Published` property a SwiftUI row can observe. Without this the catalog
/// settings row read `runtime.state` once at render and never repainted on the
/// async `.loading→.ready` transition — the permanent "Loading…" spinner.
@MainActor
final class RuntimeStatusModel: ObservableObject {
    @Published private(set) var state: RuntimeState

    private var cancellable: AnyCancellable?

    init(runtime: any TranscriptionRuntime) {
        state = runtime.state
        cancellable = runtime.stateChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] newState in self?.state = newState }
    }
}
