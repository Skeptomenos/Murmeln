import Combine
import Foundation
import os
import Testing
@preconcurrency import WhisperKit
@testable import mrml

private final class SharedEngineLoadGate: Sendable {
    private struct State {
        var variants: [String] = []
        var pending: [CheckedContinuation<Void, Never>] = []
        var released = false
        var returnedAfterCancellation: [Bool] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let returned = DispatchSemaphore(value: 0)

    var variants: [String] { state.withLock { $0.variants } }
    var returnedAfterCancellation: [Bool] { state.withLock { $0.returnedAfterCancellation } }

    private func hold(_ variant: String) async {
        await withCheckedContinuation { continuation in
            let released = state.withLock { state in
                state.variants.append(variant)
                if state.released { return true }
                state.pending.append(continuation)
                return false
            }
            if released { continuation.resume() }
        }
    }

    func releaseAll(allowFuture: Bool = true) {
        let pending = state.withLock { state in
            state.released = allowFuture
            let pending = state.pending
            state.pending.removeAll()
            return pending
        }
        pending.forEach { $0.resume() }
    }

    func waitForReturn() -> DispatchTimeoutResult {
        returned.wait(timeout: .now() + 2)
    }

    func worker() -> WhisperKitWorker {
        WhisperKitWorker { variant, _ in
            let engine = try await WhisperKit(WhisperKitConfig(prewarm: false, load: false, download: false))
            await self.hold(variant)
            self.state.withLock { $0.returnedAfterCancellation.append(Task.isCancelled) }
            self.returned.signal()
            return engine
        }
    }
}

@MainActor
@Suite("WhisperKit shared loads")
struct WhisperKitSharedLoadTests {
    @Test("Direct service replacement changes runtime readiness to the actual variant")
    func directServiceReplacement() async throws {
        let gate = SharedEngineLoadGate()
        gate.releaseAll()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        var variant = "A"
        let runtime = WhisperKitRuntime(service: service, variantProvider: { variant })
        var states: [RuntimeState] = []
        let observation = runtime.stateChanged.sink { states.append($0) }
        defer { observation.cancel() }

        try await runtime.load(.whisperKit)
        #expect(runtime.isReady(.whisperKit))
        try await service.loadModel("B")

        #expect(service.modelState == .ready)
        #expect(service.selectedModel == "B")
        #expect(await worker.currentVariant == "B")
        #expect(!runtime.isReady(.whisperKit))
        #expect(runtime.state == .notLoaded)
        #expect(states.last == .notLoaded)
        variant = "B"
        #expect(runtime.isReady(.whisperKit))
        #expect(runtime.state == .ready(.whisperKit))
    }

    @Test("Picker and pipeline share the chosen variant in either caller order", arguments: [false, true], [false, true])
    func pickerOverlap(catalog: Bool, pickerFirst: Bool) async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let state = WhisperKitSelectionControllerTestState()
        state.persistedVariant = "A"
        let runtime = WhisperKitRuntime(service: service, variantProvider: { "B" })
        let registry = TranscriptionRuntimeRegistry(runtimes: [
            .whisperKit: runtime, .fluidAudio: MockRuntime(id: .fluidAudio)
        ])
        let initial = Task { try await service.loadModel("A") }
        try #require(await waitUntil { gate.variants == ["A"] })
        gate.releaseAll(allowFuture: false)
        try await initial.value
        let legacyLoad: (@MainActor (String) async throws -> Void)?
        if catalog {
            legacyLoad = nil
        } else {
            legacyLoad = { try await service.loadModel($0) }
        }
        let controller = WhisperKitSelectionController(
            runtimeRegistry: registry,
            currentSelection: { catalog ? .catalog(.whisperKit) : .legacy(.whisperKit) },
            currentVariant: { state.persistedVariant },
            storeVariant: { state.persistedVariant = $0 },
            isDownloaded: { _ in true },
            isDownloadActive: { false },
            downloadVariant: { _ in },
            loadVariant: legacyLoad,
            cancelDownload: {}
        )
        if pickerFirst {
            #expect(controller.submit("B") { state.dismissCount += 1 })
            try #require(await waitUntil { gate.variants == ["A", "B"] })
        }
        var pipelineStarted = false
        let pipeline = Task {
            pipelineStarted = true
            if catalog { try await runtime.load(.whisperKit) }
            else { try await service.loadModel("B") }
        }
        try #require(await waitUntil { pipelineStarted && gate.variants.count >= 2 })
        if !pickerFirst {
            #expect(controller.submit("B") { state.dismissCount += 1 })
            try #require(await waitUntil { state.persistedVariant == "B" })
        }
        gate.releaseAll()
        try await pipeline.value
        try #require(await waitUntil { !controller.isLoading })

        #expect(gate.variants == ["A", "B"])
        #expect(service.modelState == .ready && service.selectedModel == "B")
        #expect(await worker.currentVariant == "B")
        #expect(state.persistedVariant == "B")
        #expect(state.dismissCount == 1)
        #expect(controller.errorMessage == nil)
    }

    @Test("Cancelling either waiter preserves the other caller's load", arguments: [false, true])
    func cancelOneWaiter(cancelFirst: Bool) async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        var firstFinished = false
        let first = Task {
            defer { firstFinished = true }
            try await service.loadModel("B")
        }
        try #require(await waitUntil { gate.variants == ["B"] })
        var secondStarted = false
        var secondFinished = false
        let second = Task {
            secondStarted = true
            defer { secondFinished = true }
            try await service.loadModel("B")
        }
        try #require(await waitUntil { secondStarted })
        let cancelled = cancelFirst ? first : second
        let survivor = cancelFirst ? second : first
        cancelled.cancel()
        await Task.yield()
        #expect(!firstFinished && !secondFinished)
        gate.releaseAll()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try await survivor.value

        #expect(gate.variants == ["B"])
        #expect(gate.returnedAfterCancellation == [false])
        #expect(service.modelState == .ready && service.selectedModel == "B")
        #expect(await worker.currentVariant == "B")
    }

    @Test("Cancelling every waiter cancels construction before MainActor cleanup can run")
    func cancelEveryWaiter() async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let first = Task { try await service.loadModel("B") }
        try #require(await waitUntil { gate.variants == ["B"] })
        var secondStarted = false
        let second = Task {
            secondStarted = true
            try await service.loadModel("B")
        }
        try #require(await waitUntil { secondStarted })

        first.cancel()
        second.cancel()
        gate.releaseAll()
        #expect(gate.waitForReturn() == .success)
        #expect(gate.returnedAfterCancellation == [true])
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(gate.variants == ["B"])
        #expect(service.modelState == .unloaded && service.selectedModel.isEmpty)
        #expect(await worker.currentVariant == nil)
    }

    @Test("Cancellation before registration or during loading publication never starts construction", arguments: [false, true])
    func cancellationDuringRegistration(cancelOnLoading: Bool) async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        var load: Task<Void, Error>?
        let observation = service.$modelState.sink { state in
            if cancelOnLoading && state == .loading { load?.cancel() }
        }
        defer { observation.cancel() }
        load = Task { try await service.loadModel("B") }
        if !cancelOnLoading { load?.cancel() }
        let task = try #require(load)
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.variants.isEmpty)
        #expect(service.modelState == .unloaded)
        #expect(await worker.currentVariant == nil)
    }

    @Test("A new caller does not join a construction after its last waiter cancelled")
    func retryAfterLastWaiterCancelled() async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let first = Task { try await service.loadModel("B") }
        try #require(await waitUntil { gate.variants == ["B"] })
        first.cancel()
        let second = Task { try await service.loadModel("B") }
        try #require(await waitUntil { gate.variants == ["B", "B"] })
        gate.releaseAll()
        await #expect(throws: CancellationError.self) { try await first.value }
        try await second.value
        #expect(service.modelState == .ready && service.selectedModel == "B")
        #expect(await worker.currentVariant == "B")
    }

    @Test("Duplicate catalog loads both succeed with one construction")
    func duplicateCatalogLoads() async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let runtime = WhisperKitRuntime(service: service, variantProvider: { "B" })
        let first = Task { try await runtime.load(.whisperKit) }
        try #require(await waitUntil { gate.variants == ["B"] })
        var secondStarted = false
        let second = Task {
            secondStarted = true
            try await runtime.load(.whisperKit)
        }
        try #require(await waitUntil { secondStarted })
        gate.releaseAll()
        try await first.value
        try await second.value
        #expect(gate.variants == ["B"])
        #expect(runtime.isReady(.whisperKit))
        #expect(runtime.state == .ready(.whisperKit))
        #expect(await worker.currentVariant == "B")
    }

    @Test("Runtime unload invalidates every waiter of the shared load")
    func runtimeUnload() async throws {
        let gate = SharedEngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let runtime = WhisperKitRuntime(service: service, variantProvider: { "B" })
        let first = Task { try await runtime.load(.whisperKit) }
        try #require(await waitUntil { gate.variants == ["B"] })
        var secondStarted = false
        let second = Task {
            secondStarted = true
            try await runtime.load(.whisperKit)
        }
        try #require(await waitUntil { secondStarted })
        await runtime.unload()
        gate.releaseAll()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        #expect(runtime.state == .notLoaded)
        #expect(!runtime.isReady(.whisperKit))
        #expect(await worker.currentVariant == nil)
    }

}
