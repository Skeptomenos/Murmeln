import AVFoundation
import FluidAudio
import Foundation
import Synchronization
import Testing
@testable import mrml

@MainActor
@Suite("Audio preparation ownership")
struct AudioPreparationOwnershipTests {
    @Test("Unchanged trim returns the original; actual trim preserves input")
    func trimIdentity() async throws {
        for silentEdges in [false, true] {
            let input = try makePreparationWAV(seconds: 8, silenceEdges: silentEdges)
            defer { try? FileManager.default.removeItem(at: input) }
            let original = try Data(contentsOf: input)
            let result = try #require(await AudioRecorder.trimSilence(audioURL: input))
            defer { if result != input { try? FileManager.default.removeItem(at: result) } }
            #expect((result == input) == !silentEdges)
            #expect(try Data(contentsOf: input) == original)
            let frames = try AVAudioFile(forReading: result).length
            #expect(silentEdges ? (frames < 8 * 48_000 && frames >= 4 * 48_000) : frames == 8 * 48_000)
        }
    }

    @Test("Worker preserves the SDK's sample output")
    func sameSamples() async throws {
        let input = try makePreparationWAV(seconds: 5)
        defer { try? FileManager.default.removeItem(at: input) }
        let expected = try AudioConverter().resampleAudioFile(input)
        #expect(try await FluidAudioPreparationWorker.shared.prepare(input) == expected)
    }

    @Test("Cancelled preparation stays joined and rejects its result")
    func joinedCancellation() async throws {
        let started = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let worker = FluidAudioPreparationWorker { _ in
            #expect(!Thread.isMainThread)
            started.withLock { $0 = true }
            release.wait()
            return [0.25]
        }
        var returned = false
        let read = Task {
            defer { returned = true }
            return try await worker.prepare(URL(fileURLWithPath: "/unused"))
        }
        #expect(await waitUntil { started.withLock { $0 } })
        read.cancel()
        #expect(!returned)
        release.signal()
        await #expect(throws: CancellationError.self) { _ = try await read.value }
        #expect(returned)
    }

    @Test("Only current preparation can enter the SDK", arguments: [-1, 0, 1, 2])
    func supersededPreparation(action: Int) async throws {
        let first = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")
        let second = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let firstManager = AsrManager(config: .default)
        let secondManager = AsrManager(config: .default)
        let enteredSDK = Mutex(false)
        let subscriptions = Mutex(0)
        var observers: [Task<Void, Never>] = []
        for manager in [firstManager, secondManager] {
            let stream = await manager.transcriptionProgressStream
            observers.append(Task {
                do {
                    for try await _ in stream { subscriptions.withLock { $0 += 1 } }
                } catch {
                    enteredSDK.withLock { $0 = true }
                }
            })
        }
        defer { observers.forEach { $0.cancel() } }
        try #require(await waitUntil { subscriptions.withLock { $0 >= 2 } })
        let gate = PreparationGate()
        let runtime = FluidAudioRuntime(installationCheck: { _ in true },
            modelLoader: { model, _ in .parakeet(model == first ? firstManager : secondManager) },
            audioPreparation: { _ in await gate.hold() })
        try await runtime.load(first)
        let task = Task { try await runtime.transcribe(audioURL: URL(fileURLWithPath: "/unused"), options: .init()) }
        try #require(await waitUntil { gate.pending != nil })
        if action == 0 { await runtime.unload() }
        if action == 1 { try await runtime.load(second) }
        if action == 2 { task.cancel() }
        gate.pending!.resume(returning: Array(repeating: 0.25, count: 320_001))
        if action == -1 {
            await #expect(throws: TranscriptionRuntimeError.self) { _ = try await task.value }
            #expect(await waitUntil { enteredSDK.withLock { $0 } })
        } else {
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            try await Task.sleep(for: .milliseconds(25))
            #expect(!enteredSDK.withLock { $0 })
        }
        #expect(runtime.state == (action == 0 ? .notLoaded : .ready(action == 1 ? second : first)))
        observers.forEach { $0.cancel() }
        for observer in observers { await observer.value }
    }
}

@MainActor
private final class PreparationGate {
    var pending: CheckedContinuation<[Float], Never>?
    func hold() async -> [Float] {
        await withCheckedContinuation { pending = $0 }
    }
}
