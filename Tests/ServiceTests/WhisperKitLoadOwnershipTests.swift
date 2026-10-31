import Foundation
import Testing
@preconcurrency import WhisperKit
@testable import mrml

@MainActor
private final class EngineLoadGate {
    var pending: [String: CheckedContinuation<Void, Never>] = [:]
    func hold(_ variant: String) async {
        await withCheckedContinuation { pending[variant] = $0 }
    }
    func release(_ variant: String) { pending.removeValue(forKey: variant)!.resume() }
    func worker() -> WhisperKitWorker {
        WhisperKitWorker { variant, _ in
            await self.hold(variant)
            return try await WhisperKit(WhisperKitConfig(prewarm: false, load: false, download: false))
        }
    }
}

@MainActor
@Suite("WhisperKit engine ownership")
struct WhisperKitLoadOwnershipTests {
    @Test("Either completion order keeps the newer engine resident", arguments: [false, true])
    func reversedCompletion(olderFinishesFirst: Bool) async throws {
        let gate = EngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let a = Task { try await service.loadModel("A") }
        #expect(await waitUntil { gate.pending["A"] != nil })
        let b = Task { try await service.loadModel("B") }
        #expect(await waitUntil { gate.pending["B"] != nil })
        if olderFinishesFirst {
            gate.release("A")
            await #expect(throws: CancellationError.self) { try await a.value }
            gate.release("B")
            try await b.value
        } else {
            gate.release("B")
            try await b.value
            gate.release("A")
            await #expect(throws: CancellationError.self) { try await a.value }
        }
        #expect(service.modelState == .ready && service.selectedModel == "B")
        #expect(await worker.isLoaded(variant: "B"))
        #expect(await worker.currentVariant == "B")
        await #expect(throws: CancellationError.self) {
            _ = try await worker.transcribe(audioPath: "unused", decodingOptions: DecodingOptions(), generation: 1)
        }
    }

    @Test("Unload and cancellation prevent late engine publication", arguments: [false, true])
    func invalidatedLoad(cancel: Bool) async throws {
        let gate = EngineLoadGate()
        let worker = gate.worker()
        let service = WhisperKitService(worker: worker)
        let load = Task { try await service.loadModel("A") }
        #expect(await waitUntil { gate.pending["A"] != nil })
        if cancel { load.cancel() } else { await service.unloadModel() }
        gate.release("A")
        await #expect(throws: CancellationError.self) { try await load.value }
        #expect(service.modelState == .unloaded && service.selectedModel.isEmpty)
        #expect(await worker.currentVariant == nil)
    }

    @Test("Late unload and failed superseded loads do not erase a new selection")
    func unloadThenReload() async throws {
        let gate = EngineLoadGate()
        let worker = gate.worker()
        var finishUnload: CheckedContinuation<Void, Never>?
        let service = WhisperKitService(worker: worker, modelUnloader: {
            await withCheckedContinuation { finishUnload = $0 }
        })
        let unload = Task { await service.unloadModel() }
        #expect(await waitUntil { finishUnload != nil })
        let load = Task { try await service.loadModel("B") }
        #expect(await waitUntil { gate.pending["B"] != nil })
        gate.release("B")
        try await load.value
        finishUnload!.resume()
        await unload.value
        #expect(service.modelState == .ready && service.selectedModel == "B")
        #expect(await worker.isLoaded(variant: "B"))
        await worker.unload(generation: 1)
        #expect(await worker.isLoaded(variant: "B"))
    }
}
