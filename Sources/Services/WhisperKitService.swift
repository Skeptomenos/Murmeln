import Foundation
@preconcurrency import WhisperKit
import CoreML
import SwiftUI

private actor WhisperKitWorker {
    private var whisperKit: WhisperKit?
    private var loadedVariant: String?
    
    func loadModel(_ variant: String, modelsDirectory: URL) async throws {
        // WhisperKit downloads to: <downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/
        // We need to provide the full path to the model folder for loading
        let modelFolder = modelsDirectory
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(variant)
        
        // Verify the model folder exists
        guard FileManager.default.fileExists(atPath: modelFolder.path) else {
            throw WhisperKitService.ServiceError.modelNotFound(variant)
        }
        
        print("🎙️ Loading WhisperKit model from: \(modelFolder.path)")
        
        // Optimize compute units for speed
        // Neural Engine is fastest for the encoder, CPU+GPU for mel spectrogram
        let computeOptions = ModelComputeOptions(
            melCompute: .cpuAndGPU,
            audioEncoderCompute: .cpuAndNeuralEngine,
            textDecoderCompute: .cpuAndNeuralEngine,
            prefillCompute: .cpuAndGPU
        )
        
        let config = WhisperKitConfig(
            modelFolder: modelFolder.path,
            computeOptions: computeOptions,
            verbose: false,
            logLevel: .error,  // Reduce logging overhead
            prewarm: true,
            load: true,
            download: false
        )
        whisperKit = try await WhisperKit(config)
        loadedVariant = variant
        print("✅ WhisperKit model loaded successfully")
    }
    
    func unload() {
        whisperKit = nil
        loadedVariant = nil
        print("🔄 WhisperKit model unloaded")
    }
    
    func transcribe(audioPath: String, decodingOptions: DecodingOptions) async throws -> [TranscriptionResult] {
        guard let whisperKit else {
            throw WhisperKitService.ServiceError.modelNotLoaded
        }
        
        return try await whisperKit.transcribe(audioPath: audioPath, decodeOptions: decodingOptions)
    }

    func inspectVADChunkDiagnostics(audioPath: String, decodingOptions: DecodingOptions) async throws -> WhisperKitVADChunkDiagnostics? {
        guard let whisperKit else {
            throw WhisperKitService.ServiceError.modelNotLoaded
        }

        guard decodingOptions.chunkingStrategy == .vad else {
            return nil
        }

        let audioArray = try AudioProcessor.loadAudioAsFloatArray(
            fromPath: audioPath,
            channelMode: whisperKit.audioInputConfig.channelMode
        )
        let maxChunkLength = whisperKit.featureExtractor.windowSamples ?? Constants.defaultWindowSamples
        let chunker = VADAudioChunker(vad: whisperKit.voiceActivityDetector ?? EnergyVAD())
        let chunks = try await chunker.chunkAll(
            audioArray: audioArray,
            maxChunkLength: maxChunkLength,
            decodeOptions: decodingOptions
        )
        let audioDurationMs = Int((Double(audioArray.count) / Double(WhisperKit.sampleRate) * 1000).rounded())

        return WhisperKitService.summarizeVADChunks(
            chunks,
            audioDurationMs: audioDurationMs,
            maxChunkLengthSamples: maxChunkLength
        )
    }
    
    func isLoaded(variant: String) -> Bool {
        return whisperKit != nil && loadedVariant == variant
    }
    
    var currentVariant: String? {
        loadedVariant
    }
}

struct WhisperKitPreparedDecoding: Sendable {
    let options: DecodingOptions
    let requestShape: WhisperKitDecodeRequestShape
}

struct WhisperKitTranscriptionOutput: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
}

struct WhisperKitVADChunkBoundary: Sendable, Equatable {
    let startMs: Int
    let endMs: Int

    var durationMs: Int {
        max(0, endMs - startMs)
    }
}

struct WhisperKitVADChunkDiagnostics: Sendable, Equatable {
    let strategy: String
    let audioDurationMs: Int
    let maxChunkLengthMs: Int
    let chunkCount: Int
    let boundaries: [WhisperKitVADChunkBoundary]
    let boundariesTruncated: Bool
    let totalCoveredAudioMs: Int
    let leadingGapMs: Int
    let tailGapMs: Int
    let longestChunkMs: Int
    let shortestChunkMs: Int

    var diagnosticsMetadata: [String: String] {
        let chunkBoundariesValue = boundaries.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ";")

        return [
            "strategy": strategy,
            "audio_duration_ms": String(audioDurationMs),
            "max_chunk_length_ms": String(maxChunkLengthMs),
            "chunk_count": String(chunkCount),
            "chunk_boundaries_ms": chunkBoundariesValue,
            "chunk_boundaries_truncated": String(boundariesTruncated),
            "total_covered_audio_ms": String(totalCoveredAudioMs),
            "leading_gap_ms": String(leadingGapMs),
            "tail_gap_ms": String(tailGapMs),
            "longest_chunk_ms": String(longestChunkMs),
            "shortest_chunk_ms": String(shortestChunkMs)
        ]
    }
}

struct WhisperKitDecodedSegmentCoverageDiagnostics: Sendable, Equatable {
    let processedAudioDurationMs: Int
    let segmentCount: Int
    let nonEmptySegmentCount: Int
    let boundaries: [WhisperKitVADChunkBoundary]
    let boundariesTruncated: Bool
    let firstSegmentStartMs: Int?
    let lastSegmentStartMs: Int?
    let lastSegmentEndMs: Int?
    let maxSegmentEndMs: Int?
    let decodedTailGapMs: Int

    var diagnosticsMetadata: [String: String] {
        let segmentBoundariesValue = boundaries.map { "\($0.startMs)-\($0.endMs)" }.joined(separator: ";")

        return [
            "processed_audio_duration_ms": String(processedAudioDurationMs),
            "segment_count": String(segmentCount),
            "non_empty_segment_count": String(nonEmptySegmentCount),
            "segment_boundaries_ms": segmentBoundariesValue,
            "segment_boundaries_truncated": String(boundariesTruncated),
            "first_segment_start_ms": firstSegmentStartMs.map(String.init) ?? "nil",
            "last_segment_start_ms": lastSegmentStartMs.map(String.init) ?? "nil",
            "last_segment_end_ms": lastSegmentEndMs.map(String.init) ?? "nil",
            "max_segment_end_ms": maxSegmentEndMs.map(String.init) ?? "nil",
            "decoded_tail_gap_ms": String(decodedTailGapMs)
        ]
    }
}

@MainActor
final class WhisperKitService: ObservableObject {
    static let shared = WhisperKitService()
    
    // Model state
    @Published var modelState: ModelState = .unloaded
    @Published var availableModels: [String] = []
    @Published var downloadedModels: [String] = []
    @Published var selectedModel: String = "base"
    
    // Download progress
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadStatus: String = ""
    
    // Download task for cancellation
    private var downloadTask: Task<URL, Error>?
    private var downloadGeneration: UInt64 = 0
    private var loadGeneration: UInt64 = 0
    private let modelsDirectoryOverride: URL?
    
    // Worker actor
    private let worker = WhisperKitWorker()

    private static var captureDiagnosticsInspectionEnabled: Bool {
        AppIdentity.isDevelopmentBuild || ProcessInfo.processInfo.environment["MURMELN_CAPTURE_DIAGNOSTICS"] == "1"
    }
    
    enum ModelState: Equatable {
        case unloaded
        case downloading
        case loading
        case ready
        case error(String)
    }
    
    enum ServiceError: Error, LocalizedError, Equatable {
        case modelNotLoaded
        case modelNotFound(String)
        case transcriptionFailed
        case downloadCancelled
        
        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: return "Model not loaded"
            case .modelNotFound(let variant): return "Model '\(variant)' not found. Please download it first."
            case .transcriptionFailed: return "Transcription failed"
            case .downloadCancelled: return "Download cancelled"
            }
        }
    }
    
    private var modelsDirectory: URL {
        if let modelsDirectoryOverride {
            return modelsDirectoryOverride
        }
        let appSupportDir = AppIdentity.appSupportDirectoryURL
        let modelsDir = appSupportDir.appendingPathComponent("Models")
        
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        return modelsDir
    }
    
    init(modelsDirectory: URL? = nil) {
        modelsDirectoryOverride = modelsDirectory
        Task {
            scanDownloadedModels()
        }
    }

    @MainActor
    func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding {
        Self.prepareDecoding(settings: settings)
    }

    @MainActor
    func inspectVADChunkDiagnostics(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitVADChunkDiagnostics? {
        guard Self.captureDiagnosticsInspectionEnabled else {
            return nil
        }

        return try await worker.inspectVADChunkDiagnostics(
            audioPath: audioURL.path,
            decodingOptions: preparedDecoding.options
        )
    }

    @MainActor
    static func prepareDecoding(settings: PipelineSettingsSnapshot) -> WhisperKitPreparedDecoding {
        prepareDecoding(
            settings: settings,
            languageContext: resolveLanguageContext(settings.whisperKitLanguages)
        )
    }

    @MainActor
    static func prepareDecoding(
        settings: PipelineSettingsSnapshot,
        languageCode: String?
    ) -> WhisperKitPreparedDecoding {
        prepareDecoding(
            settings: settings,
            languageContext: (
                languageCode == nil ? .autoDetect : .explicit,
                languageCode
            )
        )
    }

    @MainActor
    private static func prepareDecoding(
        settings: PipelineSettingsSnapshot,
        languageContext: (TranscriptionLanguageMode, String?)
    ) -> WhisperKitPreparedDecoding {
        let rawSuppressTokens: [Int]
        var decodingOptions: DecodingOptions

        switch settings.whisperKitProfile {
        case .fast:
            rawSuppressTokens = [-1]
            decodingOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: 0,
                temperatureFallbackCount: 2,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                suppressBlank: true,
                supressTokens: rawSuppressTokens,
                noSpeechThreshold: 0.6,
                concurrentWorkerCount: 4,
                chunkingStrategy: ChunkingStrategy.none
            )
        case .balanced:
            rawSuppressTokens = [-1]
            decodingOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: 0,
                temperatureFallbackCount: 3,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                suppressBlank: true,
                supressTokens: rawSuppressTokens,
                noSpeechThreshold: 0.6,
                chunkingStrategy: ChunkingStrategy.none
            )
        case .accurate:
            rawSuppressTokens = [-1]
            decodingOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: 0,
                temperatureFallbackCount: 5,
                usePrefillPrompt: true,
                usePrefillCache: true,
                skipSpecialTokens: true,
                withoutTimestamps: false,
                suppressBlank: true,
                supressTokens: rawSuppressTokens,
                noSpeechThreshold: 0.6,
                chunkingStrategy: .vad
            )
        case .custom:
            rawSuppressTokens = []
            decodingOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: Float(settings.whisperKitTemperature),
                usePrefillPrompt: settings.whisperKitPromptPrefill,
                usePrefillCache: settings.whisperKitPromptPrefill,
                withoutTimestamps: !settings.whisperKitEnableTimestamps,
                supressTokens: rawSuppressTokens,
                chunkingStrategy: settings.whisperKitUseVAD ? .vad : ChunkingStrategy.none
            )
        }

        let normalization = normalizeSuppressTokens(rawSuppressTokens)
        decodingOptions.supressTokens = normalization.normalizedTokens

        let (languageMode, languageCode) = languageContext
        if let languageCode {
            decodingOptions.language = languageCode
            decodingOptions.detectLanguage = false
        } else {
            decodingOptions.language = nil
            decodingOptions.detectLanguage = true
        }

        let requestShape = WhisperKitDecodeRequestShape(
            profile: settings.whisperKitProfile.rawValue,
            languageMode: languageMode,
            languageCode: languageCode,
            declaredLanguages: settings.whisperKitLanguages.map(\.rawValue).sorted(),
            detectLanguage: decodingOptions.detectLanguage,
            usePrefillPrompt: decodingOptions.usePrefillPrompt,
            usePrefillCache: decodingOptions.usePrefillCache,
            withoutTimestamps: decodingOptions.withoutTimestamps,
            suppressBlank: decodingOptions.suppressBlank,
            suppressTokens: decodingOptions.supressTokens,
            droppedSuppressTokens: normalization.droppedTokens,
            temperature: Double(decodingOptions.temperature),
            temperatureFallbackCount: decodingOptions.temperatureFallbackCount,
            noSpeechThreshold: decodingOptions.noSpeechThreshold.map(Double.init),
            concurrentWorkerCount: decodingOptions.concurrentWorkerCount,
            chunkingStrategy: decodingOptions.chunkingStrategy?.rawValue ?? ChunkingStrategy.none.rawValue
        )

        return WhisperKitPreparedDecoding(options: decodingOptions, requestShape: requestShape)
    }

    private static func normalizeSuppressTokens(_ rawSuppressTokens: [Int]) -> (normalizedTokens: [Int], droppedTokens: [Int]) {
        var normalizedTokens: [Int] = []
        var droppedTokens: [Int] = []
        var seen = Set<Int>()

        for token in rawSuppressTokens {
            if token < 0 {
                droppedTokens.append(token)
                continue
            }

            if seen.insert(token).inserted {
                normalizedTokens.append(token)
            }
        }

        return (normalizedTokens, droppedTokens)
    }

    private static func resolveLanguageContext(_ languages: [WhisperKitLanguage]) -> (TranscriptionLanguageMode, String?) {
        if languages.count == 1, let language = languages.first {
            return (.explicit, language.code)
        }

        return (.autoDetect, nil)
    }

    nonisolated static func summarizeVADChunks(
        _ chunks: [AudioChunk],
        audioDurationMs: Int,
        maxChunkLengthSamples: Int,
        sampleRate: Int = WhisperKit.sampleRate,
        logBoundaryLimit: Int = 64
    ) -> WhisperKitVADChunkDiagnostics {
        let safeSampleRate = max(sampleRate, 1)
        let boundaries = chunks.map { chunk in
            let startMs = Int((Double(chunk.seekOffsetIndex) / Double(safeSampleRate) * 1000).rounded())
            let endFrame = chunk.seekOffsetIndex + chunk.audioSamples.count
            let endMs = Int((Double(endFrame) / Double(safeSampleRate) * 1000).rounded())
            return WhisperKitVADChunkBoundary(startMs: startMs, endMs: endMs)
        }

        let totalCoveredAudioMs = boundaries.reduce(0) { $0 + $1.durationMs }
        let leadingGapMs = boundaries.first?.startMs ?? audioDurationMs
        let lastChunkEndMs = boundaries.last?.endMs ?? 0
        let tailGapMs = max(0, audioDurationMs - lastChunkEndMs)
        let longestChunkMs = boundaries.map(\.durationMs).max() ?? 0
        let shortestChunkMs = boundaries.map(\.durationMs).min() ?? 0
        let boundaryLimit = max(logBoundaryLimit, 0)
        let loggedBoundaries = Array(boundaries.prefix(boundaryLimit))
        let maxChunkLengthMs = Int((Double(maxChunkLengthSamples) / Double(safeSampleRate) * 1000).rounded())

        return WhisperKitVADChunkDiagnostics(
            strategy: ChunkingStrategy.vad.rawValue,
            audioDurationMs: audioDurationMs,
            maxChunkLengthMs: maxChunkLengthMs,
            chunkCount: boundaries.count,
            boundaries: loggedBoundaries,
            boundariesTruncated: loggedBoundaries.count < boundaries.count,
            totalCoveredAudioMs: totalCoveredAudioMs,
            leadingGapMs: max(0, leadingGapMs),
            tailGapMs: tailGapMs,
            longestChunkMs: longestChunkMs,
            shortestChunkMs: shortestChunkMs
        )
    }
    
    // Fetch available models from HuggingFace
    func fetchAvailableModels() async {
        do {
            // We'll filter for standard OpenAI variants to keep it simple for now
            let models = try await WhisperKit.fetchAvailableModels(matching: ["openai_*"])
            self.availableModels = models.sorted()
        } catch {
            print("Failed to fetch models: \(error)")
            // Fallback list
            self.availableModels = [
                "openai_whisper-tiny",
                "openai_whisper-base",
                "openai_whisper-small",
                "openai_whisper-medium",
                "openai_whisper-large-v3"
            ]
        }
    }
    
    // Download a model with progress
    func downloadModel(_ variant: String) async throws -> URL {
        downloadGeneration &+= 1
        let generation = downloadGeneration
        modelState = .downloading
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download..."
        
        // Create cancellable task
        let task = Task<URL, Error> { [self] in
            // Use a Sendable closure that captures necessary MainActor state safely
            let progressCallback: @Sendable (Progress) -> Void = { progress in
                Task { @MainActor [weak self] in
                    guard let self, self.downloadGeneration == generation else { return }
                    self.downloadProgress = progress.fractionCompleted
                    self.downloadStatus = "\(Int(progress.fractionCompleted * 100))%"
                }
            }
            
            // Check for cancellation before starting
            try Task.checkCancellation()
            
            let modelFolder = try await WhisperKit.download(
                variant: variant,
                downloadBase: modelsDirectory,
                useBackgroundSession: false, // Use foreground session for cancellation support
                progressCallback: progressCallback
            )
            
            // Check for cancellation after download
            try Task.checkCancellation()
            
            return modelFolder
        }
        
        downloadTask = task
        
        do {
            let modelFolder = try await task.value
            guard generation == downloadGeneration else {
                throw ServiceError.downloadCancelled
            }
            
            // Mark as downloaded in AppSettings
            var current = AppSettings.shared.installedWhisperModels
            if !current.contains(variant) {
                current.append(variant)
                AppSettings.shared.installedWhisperModels = current
            }
            scanDownloadedModels()
            
            modelState = .unloaded // Ready to load
            isDownloading = false
            downloadTask = nil
            return modelFolder
        } catch {
            let cancelled = Task.isCancelled
                || error is CancellationError
                || (error as? ServiceError) == .downloadCancelled
            if generation == downloadGeneration {
                modelState = cancelled ? .unloaded : .error(error.localizedDescription)
                isDownloading = false
                downloadTask = nil
                if cancelled {
                    downloadStatus = "Download cancelled"
                }
            }
            if cancelled {
                throw ServiceError.downloadCancelled
            }
            throw error
        }
    }
    
    /// Cancel the current download
    func cancelDownload() {
        guard let downloadTask else { return }
        downloadGeneration &+= 1
        downloadTask.cancel()
        self.downloadTask = nil
        isDownloading = false
        downloadStatus = "Cancelled"
        modelState = .unloaded
    }

    /// Delete one concrete WhisperKit variant and reconcile the persisted
    /// installed-model index. Production and Dev identities resolve separate
    /// `modelsDirectory` roots through AppIdentity.
    func deleteModel(_ variant: String) async throws {
        if selectedModel == variant {
            await unloadModel()
        }

        let modelFolder = modelsDirectory
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            .appendingPathComponent(variant)
        if FileManager.default.fileExists(atPath: modelFolder.path) {
            try FileManager.default.removeItem(at: modelFolder)
        }

        AppSettings.shared.installedWhisperModels.removeAll { $0 == variant }
        scanDownloadedModels()
    }
    
    /// Unload the current model to free memory
    func unloadModel() async {
        loadGeneration &+= 1
        await worker.unload()
        modelState = .unloaded
        selectedModel = ""
        print("🔄 Model unloaded")
    }
    
    // Load model for transcription
    func loadModel(_ variant: String) async throws {
        // Check if already loaded
        if modelState == .ready && selectedModel == variant {
            return
        }
        
        // Unload previous model first if switching
        if modelState == .ready && selectedModel != variant {
            await unloadModel()
        }

        loadGeneration &+= 1
        let generation = loadGeneration
        
        modelState = .loading
        selectedModel = variant
        
        do {
            try await worker.loadModel(variant, modelsDirectory: modelsDirectory)
            guard generation == loadGeneration else {
                if modelState != .ready {
                    await worker.unload()
                }
                return
            }
            modelState = .ready
        } catch {
            if generation == loadGeneration {
                modelState = .error(error.localizedDescription)
            }
            throw error
        }
    }
    
    // Transcribe audio file
    func transcribe(audioURL: URL) async throws -> String {
        let preparedDecoding = prepareDecoding(settings: AppSettings.shared.pipelineSettingsSnapshot())
        return try await transcribe(audioURL: audioURL, preparedDecoding: preparedDecoding)
    }

    func transcribe(audioURL: URL, languageCode: String?) async throws -> String {
        let preparedDecoding = Self.prepareDecoding(
            settings: AppSettings.shared.pipelineSettingsSnapshot(),
            languageCode: languageCode
        )
        return try await transcribe(audioURL: audioURL, preparedDecoding: preparedDecoding)
    }

    func transcribe(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> String {
        let output = try await transcribeOutput(audioURL: audioURL, preparedDecoding: preparedDecoding)
        return output.text
    }

    func transcribeOutput(audioURL: URL, preparedDecoding: WhisperKitPreparedDecoding) async throws -> WhisperKitTranscriptionOutput {
        guard modelState == .ready else {
            throw ServiceError.modelNotLoaded
        }

        let results = try await worker.transcribe(audioPath: audioURL.path, decodingOptions: preparedDecoding.options)
        let segments = results.flatMap(\.segments)
        let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperKitTranscriptionOutput(text: text, segments: segments)
    }

    nonisolated static func summarizeDecodedSegmentCoverage(
        _ segments: [TranscriptionSegment],
        processedAudioDurationMs: Int,
        logBoundaryLimit: Int = 64
    ) -> WhisperKitDecodedSegmentCoverageDiagnostics {
        let nonEmptySegments = segments.filter { $0.end > $0.start }
        let boundaries = nonEmptySegments.map { segment in
            WhisperKitVADChunkBoundary(
                startMs: Int((Double(segment.start) * 1000).rounded()),
                endMs: Int((Double(segment.end) * 1000).rounded())
            )
        }
        let boundaryLimit = max(logBoundaryLimit, 0)
        let loggedBoundaries = Array(boundaries.prefix(boundaryLimit))
        let firstBoundary = boundaries.first
        let lastBoundary = boundaries.last
        let maxSegmentEndMs = boundaries.map(\.endMs).max()
        let decodedTailGapMs = max(0, processedAudioDurationMs - (maxSegmentEndMs ?? 0))

        return WhisperKitDecodedSegmentCoverageDiagnostics(
            processedAudioDurationMs: processedAudioDurationMs,
            segmentCount: segments.count,
            nonEmptySegmentCount: nonEmptySegments.count,
            boundaries: loggedBoundaries,
            boundariesTruncated: loggedBoundaries.count < boundaries.count,
            firstSegmentStartMs: firstBoundary?.startMs,
            lastSegmentStartMs: lastBoundary?.startMs,
            lastSegmentEndMs: lastBoundary?.endMs,
            maxSegmentEndMs: maxSegmentEndMs,
            decodedTailGapMs: decodedTailGapMs
        )
    }
    
    // Check what models are already downloaded
    func scanDownloadedModels() {
        self.downloadedModels = AppSettings.shared.installedWhisperModels
    }
    
    func isModelDownloaded(_ variant: String) -> Bool {
        return downloadedModels.contains(variant)
    }
}
