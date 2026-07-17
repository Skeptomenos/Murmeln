import Foundation
import Testing
@testable import mrml

/// Slice 3: raw runtime failures must map to actionable user-facing states,
/// never a bare Python-style error string (the exact failure Phase 8 exists
/// to kill: raw dependency/setup errors escaping into the user-facing UI.
@Suite("Runtime Error Mapping Tests")
struct RuntimeErrorMappingTests {

    @Test("Model-not-installed error names the model and is actionable")
    func modelNotInstalledIsActionable() {
        let error = TranscriptionRuntimeError.modelNotInstalled(
            TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"))
        let message = error.errorDescription ?? ""
        #expect(message.contains("parakeet-tdt-0.6b-v3"))
        #expect(message.lowercased().contains("download"))
    }

    @Test("Runtime-not-ready error names the runtime")
    func runtimeNotReadyNamesRuntime() {
        let error = TranscriptionRuntimeError.runtimeNotReady(.fluidAudio)
        #expect(error.errorDescription?.contains("fluidaudio") == true)
    }

    @Test("Unsupported-model error names both model and runtime")
    func unsupportedModelNamesBoth() {
        let error = TranscriptionRuntimeError.unsupportedModel(
            TranscriptionModelID(rawValue: "granite-speech"), .fluidAudio)
        let message = error.errorDescription ?? ""
        #expect(message.contains("granite-speech"))
        #expect(message.contains("fluidaudio"))
    }

    @MainActor
    @Test("FluidAudioRuntime rejects catalog-unknown models with a typed error")
    func fluidAudioRejectsUnknownModel() async {
        let runtime = FluidAudioRuntime()
        await #expect(throws: TranscriptionRuntimeError.self) {
            try await runtime.load(.whisperKit)
        }
    }

    @MainActor
    @Test("FluidAudioRuntime transcribe before load is a typed not-ready error")
    func fluidAudioTranscribeBeforeLoad() async {
        let runtime = FluidAudioRuntime()
        await #expect(throws: TranscriptionRuntimeError.runtimeNotReady(.fluidAudio)) {
            _ = try await runtime.transcribe(
                audioURL: URL(fileURLWithPath: "/tmp/none.wav"),
                options: TranscriptionOptions())
        }
    }

    @MainActor
    @Test("FluidAudioRuntime isInstalled is false for unknown models")
    func fluidAudioIsInstalledUnknown() {
        let runtime = FluidAudioRuntime()
        #expect(runtime.isInstalled(TranscriptionModelID(rawValue: "does-not-exist")) == false)
    }

    @MainActor
    @Test(arguments: [RuntimeOperation.download, .load, .transcribe])
    func unexpectedInstalledModelFailurePreservesOperation(operation: RuntimeOperation) {
        let runtime = FluidAudioRuntime()
        let modelID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let underlying = NSError(
            domain: "com.apple.CoreML",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Failed to allocate model memory"]
        )

        let mapped = runtime.mapError(
            underlying,
            modelID: modelID,
            operation: operation,
            assetsInstalled: true
        )

        #expect(mapped == .runtimeFailure(
            .fluidAudio,
            operation,
            "Failed to allocate model memory"
        ))
        #expect(mapped.errorDescription?.contains(operation.rawValue) == true)
    }

    @Test("FluidAudio load and transcribe preserve task cancellation")
    func cancellationIsNotMappedToRuntimeFailure() {
        #expect(FluidAudioRuntime.shouldPreserveCancellation(CancellationError()))
        #expect(!FluidAudioRuntime.shouldPreserveCancellation(
            NSError(domain: "com.apple.CoreML", code: 9)
        ))
    }
}
