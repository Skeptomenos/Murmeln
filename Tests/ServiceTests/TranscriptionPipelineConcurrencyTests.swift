import Testing
import Foundation
import Combine
import FluidAudio
@preconcurrency import WhisperKit
@testable import mrml

@Suite("Transcription Pipeline Concurrency Tests")
struct TranscriptionPipelineConcurrencyTests {
    @Test("Legacy multipart path does not force main-thread execution")
    func legacyMultipartPathDoesNotForceMainThreadExecution() async throws {
        let network = ThreadCapturingLegacyTranscriptionNetworking()
        let whisper = await MainActor.run { ConcurrencyTestWhisperKitService() }
        let service = await MainActor.run {
            TranscriptionPipelineService(network: network, whisperKitService: whisper)
        }

        let settings = PipelineSettingsSnapshot(
            transcriptionProvider: .openAIWhisper,
            transcriptionAPIKey: "transcription-key",
            transcriptionBaseURL: "https://example.test/v1",
            transcriptionModel: "whisper-1",
            whisperKitModel: "openai_whisper-small",
            refinementProvider: .openAI,
            refinementAPIKey: "refinement-key",
            refinementBaseURL: "https://example.test/v1",
            refinementModel: "gpt-4o-mini",
            skipRefinement: true,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: [.english]
        )

        _ = try await Task.detached(priority: .userInitiated) {
            try await service.executeTranscription(
                request: TranscriptionRequest(
                    captureID: "capture-1",
                    audioURL: URL(fileURLWithPath: "/tmp/fake.wav"),
                    audioDurationMs: 1_200,
                    baselinePrompt: "",
                    settings: settings
                )
            )
        }.value

        let invocationWasOnMainThread = await MainActor.run {
            network.invocationWasOnMainThread
        }
        #expect(invocationWasOnMainThread == false)
    }
}

private final class ThreadCapturingLegacyTranscriptionNetworking: LegacyTranscriptionNetworking, @unchecked Sendable {
    var invocationWasOnMainThread = false

    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "multipart transcript"
    }

    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "local"
    }

    func transcribeCloudAudioInput(audioURL: URL, provider: TranscriptionProvider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "one call"
    }

    func refine(text: String, provider: Provider, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        invocationWasOnMainThread = pthread_main_np() != 0
        return "refined"
    }
}

@MainActor
private final class ConcurrencyTestWhisperKitService: WhisperKitTranscribing {
    var modelState: WhisperKitService.ModelState = .ready
    var selectedModel: String = "openai_whisper-small"

    func loadModel(_ variant: String) async throws {}
    func transcribe(audioURL: URL, expectedVariant: String) async throws -> String { "whisper" }
    func transcribe(audioURL: URL, expectedVariant: String, languageCode: String?) async throws -> String { "whisper" }
}


@MainActor
@Suite("Expected model admission", .serialized)
struct ExpectedModelAdmissionTests {
    @Test("Whisper pipeline admits only its requested concrete variant",
          arguments: [false, true], AdmissionChange.allCases)
    fileprivate func whisperAdmission(warm: Bool, change: AdmissionChange) async throws {
        let requested = "openai_whisper-small"
        let replacement = "openai_whisper-large-v3_turbo"
        let probe = WhisperAdmissionProbe()
        let worker = WhisperKitWorker { variant, _ in
            try await AdmissionProbeWhisperKit(variant: variant, probe: probe)
        }
        let service = WhisperKitService(
            modelsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("admission-\(UUID().uuidString)"),
            worker: worker
        )
        if warm { try await service.loadModel(requested) }
        let gate = AdmissionBoundaryGate()
        let forwarding = GatedWhisperAdmissionService(service: service, gate: gate)
        let pipeline = TranscriptionPipelineService(
            network: ThreadCapturingLegacyTranscriptionNetworking(),
            whisperKitService: forwarding,
            runtimeRegistry: TranscriptionRuntimeRegistry(runtimes: [
                .fluidAudio: MockRuntime(id: .fluidAudio),
                .whisperKit: MockRuntime(id: .whisperKit)
            ])
        )
        let request = admissionRequest(model: requested, whisperVariant: requested)
        let transcription = Task { try await pipeline.executeTranscription(request: request) }
        await gate.waitUntilReached()
        #expect(service.selectedModel == requested)
        #expect(service.modelState == .ready)
        #expect(await worker.currentVariant == requested)
        if change == .replaced { try await service.loadModel(replacement) }
        if change == .cancelled { transcription.cancel() }
        gate.open()
        let result = await transcription.result
        print("ADMISSION whisper warm=\(warm) change=\(change) sdk=\(probe.variants) result=\(describe(result))")
        if change == .unchanged {
            let output = try result.get()
            #expect(output.text == requested)
            #expect(output.runContext.model == requested)
            #expect(output.runContext.warmState == (warm ? .warmReady : .coldLoad))
            #expect(probe.variants == [requested])
        } else {
            #expect(probe.variants.isEmpty, "A superseded or cancelled request must not enter the SDK")
            #expect(isCancellation(result), "The original request must terminate as cancellation")
        }
        #expect(service.modelState == .ready)
        #expect(service.selectedModel == (change == .replaced ? replacement : requested))
        #expect(await worker.currentVariant == (change == .replaced ? replacement : requested))
    }


    @Test("FluidAudio pipeline admits only its requested catalog model",
          arguments: [false, true], AdmissionChange.allCases)
    fileprivate func fluidAdmission(warm: Bool, change: AdmissionChange) async throws {
        let requested = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")
        let replacement = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let managerA = AsrManager(config: .default)
        let managerB = AsrManager(config: .default)
        let streamA = await managerA.transcriptionProgressStream
        let streamB = await managerB.transcriptionProgressStream
        var progressA = streamA.makeAsyncIterator()
        var progressB = streamB.makeAsyncIterator()
        #expect(try await progressA.next() == 0)
        #expect(try await progressB.next() == 0)
        let preparation = AdmissionAudioPreparation()
        let runtime = FluidAudioRuntime(
            installationCheck: { $0 == requested || $0 == replacement },
            modelLoader: { model, _ in
                .parakeet(model == requested ? managerA : managerB)
            },
            audioPreparation: { _ in await preparation.prepare() }
        )
        if warm { try await runtime.load(requested) }
        let gate = AdmissionBoundaryGate()
        let forwarding = GatedRuntimeAdmission(runtime: runtime, gate: gate)
        let pipeline = TranscriptionPipelineService(
            network: ThreadCapturingLegacyTranscriptionNetworking(),
            whisperKitService: ConcurrencyTestWhisperKitService(),
            runtimeRegistry: TranscriptionRuntimeRegistry(runtimes: [
                .fluidAudio: forwarding, .whisperKit: MockRuntime(id: .whisperKit)
            ])
        )
        let request = admissionRequest(model: requested.rawValue, whisperVariant: "openai_whisper-small", catalog: true)
        let transcription = Task { try await pipeline.executeTranscription(request: request) }
        await gate.waitUntilReached()
        #expect(runtime.isReady(requested))
        if change == .replaced { try await runtime.load(replacement) }
        if change == .cancelled { transcription.cancel() }
        gate.open()
        let result = await transcription.result
        var sdkFailure: String?
        if case .failure(let error) = result,
           case .runtimeFailure = error as? TranscriptionRuntimeError {
            do {
                // The initial zero was consumed above. Only the actual SDK
                // transcription failure can terminate this stream with an error.
                if change == .replaced {
                    _ = try await progressB.next()
                } else {
                    _ = try await progressA.next()
                }
                Issue.record("The actual AsrManager did not report its failure")
            } catch {
                sdkFailure = String(describing: error)
                #expect(sdkFailure == "notInitialized")
            }
        }
        let prepared = await preparation.calls
        print("ADMISSION fluid warm=\(warm) change=\(change) prepared=\(prepared) sdk=\(sdkFailure ?? "none") result=\(describe(result))")
        if change == .unchanged {
            #expect(prepared == 1)
            #expect(sdkFailure == "notInitialized", "The positive control must enter the real SDK")
        } else {
            #expect(prepared == 0, "Reject a superseded or cancelled request before audio preparation")
            #expect(sdkFailure == nil, "A rejected request must not enter the SDK")
            #expect(isCancellation(result))
        }
        #expect(runtime.isReady(change == .replaced ? replacement : requested))
    }

    @Test("Generic Whisper freezes the concrete variant across catalog admission",
          arguments: [false, true], AdmissionChange.allCases)
    fileprivate func genericWhisperAdmission(warm: Bool, change: AdmissionChange) async throws {
        for provider in [TranscriptionProvider.whisperKit, .openAIWhisper, .groqWhisper] {
            try await assertGenericWhisperAdmission(warm: warm, provider: provider, change: change)
        }
    }

    @Test("Generic Whisper admission uses the request even when the picker changes",
          arguments: [false, true])
    func genericWhisperPickerChanges(warm: Bool) async throws {
        try await assertGenericWhisperAdmission(
            warm: warm, provider: .openAIWhisper, change: .unchanged, changePickerOnly: true)
    }

    private func assertGenericWhisperAdmission(
        warm: Bool, provider: TranscriptionProvider, change: AdmissionChange,
        changePickerOnly: Bool = false
    ) async throws {
        let requested = "openai_whisper-small"
        let replacement = "openai_whisper-large-v3_turbo"
        var pickerVariant = requested
        let probe = WhisperAdmissionProbe()
        let worker = WhisperKitWorker { variant, _ in
            try await AdmissionProbeWhisperKit(variant: variant, probe: probe)
        }
        let service = WhisperKitService(
            modelsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("admission-\(UUID().uuidString)"),
            worker: worker
        )
        let runtime = WhisperKitRuntime(service: service, variantProvider: { pickerVariant })
        if warm { try await runtime.load(.whisperKit) }
        let gate = AdmissionBoundaryGate()
        let forwarding = GatedRuntimeAdmission(runtime: runtime, gate: gate)
        let pipeline = TranscriptionPipelineService(
            network: ThreadCapturingLegacyTranscriptionNetworking(),
            whisperKitService: service,
            runtimeRegistry: TranscriptionRuntimeRegistry(runtimes: [
                .fluidAudio: MockRuntime(id: .fluidAudio), .whisperKit: forwarding
            ])
        )
        let request = admissionRequest(
            model: requested, whisperVariant: requested, catalog: true, provider: provider,
            catalogModel: TranscriptionModelID.whisperKit.rawValue)
        let transcription = Task { try await pipeline.executeTranscription(request: request) }
        await gate.waitUntilReached()
        #expect(service.selectedModel == requested)
        #expect(await worker.currentVariant == requested)
        if change == .replaced {
            pickerVariant = replacement
            try await runtime.load(.whisperKit)
        }
        if changePickerOnly { pickerVariant = replacement }
        if change == .cancelled { transcription.cancel() }
        gate.open()
        let result = await transcription.result
        print("ADMISSION generic-whisper warm=\(warm) provider=\(provider) change=\(change) pickerOnly=\(changePickerOnly) sdk=\(probe.variants) result=\(describe(result))")
        if change == .unchanged {
            let output = try result.get()
            #expect(output.text == requested)
            #expect(output.runContext.model == TranscriptionModelID.whisperKit.rawValue)
            #expect(output.runContext.warmState == (warm ? .warmReady : .coldLoad))
            #expect(probe.variants == [requested])
        } else {
            #expect(probe.variants.isEmpty)
            #expect(isCancellation(result))
        }
        let resident = change == .replaced ? replacement : requested
        #expect(service.modelState == .ready)
        #expect(service.selectedModel == resident)
        #expect(await worker.currentVariant == resident)
        #expect(pickerVariant == (change == .replaced || changePickerOnly ? replacement : requested))
    }

    @Test("Whisper worker checks variant, generation, and cancellation before SDK entry",
          arguments: WorkerAdmissionChange.allCases)
    fileprivate func whisperWorkerAdmission(change: WorkerAdmissionChange) async throws {
        let requested = "openai_whisper-small"
        let resident = change == .wrongVariant ? "openai_whisper-large-v3_turbo" : requested
        let probe = WhisperAdmissionProbe()
        let worker = WhisperKitWorker { variant, _ in
            try await AdmissionProbeWhisperKit(variant: variant, probe: probe)
        }
        try await worker.loadModel(resident, modelsDirectory: URL(fileURLWithPath: "/unused"), generation: 2)
        let gate = AdmissionBoundaryGate()
        let task = Task {
            await gate.pause()
            return try await worker.transcribe(
                audioPath: "/unused/admission.wav", expectedVariant: requested,
                decodingOptions: DecodingOptions(), generation: change == .staleGeneration ? 1 : 2)
        }
        await gate.waitUntilReached()
        if change == .cancelled { task.cancel() }
        gate.open()
        let result = await task.result
        if change == .unchanged {
            #expect(try result.get().map(\.text) == [requested])
            #expect(probe.variants == [requested])
        } else {
            #expect(isCancellation(result))
            #expect(probe.variants.isEmpty)
        }
        #expect(await worker.currentVariant == resident)
    }

    @Test("Whisper VAD worker rejects stale admission before file conversion",
          arguments: WorkerAdmissionChange.allCases)
    fileprivate func whisperVADWorkerAdmission(change: WorkerAdmissionChange) async throws {
        let requested = "openai_whisper-small"
        let resident = change == .wrongVariant ? "openai_whisper-large-v3_turbo" : requested
        let probe = WhisperAdmissionProbe()
        let worker = WhisperKitWorker { variant, _ in
            try await AdmissionProbeWhisperKit(variant: variant, probe: probe)
        }
        try await worker.loadModel(resident, modelsDirectory: URL(fileURLWithPath: "/unused"), generation: 2)
        let gate = AdmissionBoundaryGate()
        let task = Task {
            await gate.pause()
            return try await worker.inspectVADChunkDiagnostics(
                audioPath: "/unused/admission.wav", expectedVariant: requested,
                decodingOptions: DecodingOptions(chunkingStrategy: .vad),
                generation: change == .staleGeneration ? 1 : 2)
        }
        await gate.waitUntilReached()
        if change == .cancelled { task.cancel() }
        gate.open()
        let result = await task.result
        if change == .unchanged {
            guard case .failure(let error) = result else {
                Issue.record("The admitted VAD control should try to read the missing file")
                return
            }
            #expect(!(error is CancellationError))
        } else {
            #expect(isCancellation(result))
        }
        #expect(probe.variants.isEmpty)
        #expect(await worker.currentVariant == resident)
    }

    @Test("Whisper diagnostic cancellation stops the pipeline before decode")
    func diagnosticCancellationStopsDecode() async {
        let service = CancellingDiagnosticWhisperService()
        let pipeline = TranscriptionPipelineService(
            network: ThreadCapturingLegacyTranscriptionNetworking(),
            whisperKitService: service)
        let request = admissionRequest(
            model: service.selectedModel, whisperVariant: service.selectedModel)
        await #expect(throws: CancellationError.self) {
            _ = try await pipeline.executeTranscription(request: request)
        }
        #expect(service.inspectedVariants == [request.settings.whisperKitModel])
        #expect(service.transcriptionCalls == 0)
    }

    private func admissionRequest(
        model: String, whisperVariant: String, catalog: Bool = false, provider: TranscriptionProvider = .whisperKit,
        catalogModel: String? = nil
    ) -> TranscriptionRequest {
        TranscriptionRequest(
            captureID: "admission-\(UUID().uuidString)",
            audioURL: URL(fileURLWithPath: "/unused/admission.wav"),
            audioDurationMs: 16_000,
            baselinePrompt: "",
            settings: PipelineSettingsSnapshot(
                transcriptionProvider: provider,
                transcriptionAPIKey: "",
                transcriptionBaseURL: "",
                transcriptionModel: provider == .whisperKit ? model : "legacy-cloud-model",
                whisperKitModel: whisperVariant,
                selectedCatalogModelID: catalog ? (catalogModel ?? model) : "",
                refinementProvider: .openAI,
                refinementAPIKey: "",
                refinementBaseURL: "",
                refinementModel: "",
                skipRefinement: true,
                parallelRefinementEnabled: false,
                whisperKitProfile: .balanced,
                whisperKitTemperature: 0,
                whisperKitPromptPrefill: false,
                whisperKitEnableTimestamps: false,
                whisperKitUseVAD: false,
                whisperKitLanguages: [.english]
            )
        )
    }

    private func isCancellation<T>(_ result: Result<T, Error>) -> Bool {
        if case .failure(let error) = result { return error is CancellationError }
        return false
    }

    private func describe(_ result: Result<TranscriptionExecutionResult, Error>) -> String {
        switch result {
        case .success(let output): "success(text=\(output.text), requested=\(output.runContext.model))"
        case .failure(let error): String(describing: error)
        }
    }
}

private enum AdmissionChange: String, CaseIterable, Sendable {
    case unchanged, replaced, cancelled
}


private enum WorkerAdmissionChange: CaseIterable, Sendable {
    case unchanged, wrongVariant, staleGeneration, cancelled
}

@MainActor
private final class CancellingDiagnosticWhisperService: WhisperKitTranscribing {
    let modelState = WhisperKitService.ModelState.ready
    let selectedModel = "openai_whisper-small"
    var inspectedVariants: [String] = []
    var transcriptionCalls = 0

    func loadModel(_ variant: String) async throws {}
    func transcribe(audioURL: URL, expectedVariant: String) async throws -> String {
        transcriptionCalls += 1
        return "unexpected decode"
    }
    func transcribe(audioURL: URL, expectedVariant: String, languageCode: String?) async throws -> String {
        try await transcribe(audioURL: audioURL, expectedVariant: expectedVariant)
    }
    func inspectVADChunkDiagnostics(
        audioURL: URL, expectedVariant: String, preparedDecoding: WhisperKitPreparedDecoding
    ) async throws -> WhisperKitVADChunkDiagnostics? {
        inspectedVariants.append(expectedVariant)
        throw CancellationError()
    }
}

private actor AdmissionAudioPreparation {
    var calls = 0
    func prepare() -> [Float] {
        calls += 1
        return Array(repeating: 0, count: 240_001)
    }
}

@MainActor
private final class GatedRuntimeAdmission: TranscriptionRuntime {
    let runtime: any TranscriptionRuntime
    let gate: AdmissionBoundaryGate
    init(runtime: any TranscriptionRuntime, gate: AdmissionBoundaryGate) {
        self.runtime = runtime
        self.gate = gate
    }
    var id: RuntimeID { runtime.id }
    var state: RuntimeState { runtime.state }
    var stateChanged: AnyPublisher<RuntimeState, Never> { runtime.stateChanged }
    func isInstalled(_ modelID: TranscriptionModelID) -> Bool { runtime.isInstalled(modelID) }
    func isReady(_ modelID: TranscriptionModelID) -> Bool { runtime.isReady(modelID) }
    func load(_ modelID: TranscriptionModelID) async throws { try await runtime.load(modelID) }
    func unload() async { await runtime.unload() }
    func download(
        _ modelID: TranscriptionModelID, progress: @escaping @MainActor (Double) -> Void
    ) async throws { try await runtime.download(modelID, progress: progress) }
    func cancelDownload(_ modelID: TranscriptionModelID) { runtime.cancelDownload(modelID) }
    func delete(_ modelID: TranscriptionModelID) async throws { try await runtime.delete(modelID) }
    func transcribe(audioURL: URL, expectedModel: TranscriptionModelIdentity, options: TranscriptionOptions) async throws -> String {
        await gate.pause()
        return try await runtime.transcribe(audioURL: audioURL, expectedModel: expectedModel, options: options)
    }
}


@MainActor
private final class AdmissionBoundaryGate {
    private var reached = false
    private var entry: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            release = continuation
            reached = true
            entry?.resume()
            entry = nil
        }
    }

    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { entry = $0 }
    }

    func open() {
        release?.resume()
        release = nil
    }
}

@MainActor
private final class WhisperAdmissionProbe {
    var variants: [String] = []
    func record(_ variant: String) { variants.append(variant) }
}

private final class AdmissionProbeWhisperKit: WhisperKit, @unchecked Sendable {
    private let variant: String
    private let probe: WhisperAdmissionProbe

    init(variant: String, probe: WhisperAdmissionProbe) async throws {
        self.variant = variant
        self.probe = probe
        try await super.init(WhisperKitConfig(prewarm: false, load: false, download: false))
    }

    override func transcribe(
        audioPath: String,
        decodeOptions: DecodingOptions? = nil,
        callback: TranscriptionCallback = nil
    ) async throws -> [TranscriptionResult] {
        await probe.record(variant)
        return [TranscriptionResult(text: variant, segments: [], language: "en", timings: TranscriptionTimings())]
    }
}

@MainActor
private final class GatedWhisperAdmissionService: WhisperKitTranscribing {
    let service: WhisperKitService
    let gate: AdmissionBoundaryGate
    init(service: WhisperKitService, gate: AdmissionBoundaryGate) {
        self.service = service
        self.gate = gate
    }
    var modelState: WhisperKitService.ModelState { service.modelState }
    var selectedModel: String { service.selectedModel }
    func loadModel(_ variant: String) async throws { try await service.loadModel(variant) }
    func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding {
        service.prepareDecoding(settings: settings)
    }
    func transcribe(audioURL: URL, expectedVariant: String) async throws -> String {
        try await service.transcribe(audioURL: audioURL, expectedVariant: expectedVariant)
    }
    func transcribe(audioURL: URL, expectedVariant: String, languageCode: String?) async throws -> String {
        try await service.transcribe(audioURL: audioURL, expectedVariant: expectedVariant, languageCode: languageCode)
    }
    func transcribeOutput(
        audioURL: URL, expectedVariant: String, preparedDecoding: WhisperKitPreparedDecoding
    ) async throws -> WhisperKitTranscriptionOutput {
        await gate.pause()
        return try await service.transcribeOutput(audioURL: audioURL, expectedVariant: expectedVariant, preparedDecoding: preparedDecoding)
    }
    func inspectVADChunkDiagnostics(
        audioURL: URL, expectedVariant: String, preparedDecoding: WhisperKitPreparedDecoding
    ) async throws -> WhisperKitVADChunkDiagnostics? {
        try await service.inspectVADChunkDiagnostics(audioURL: audioURL, expectedVariant: expectedVariant, preparedDecoding: preparedDecoding)
    }
}
