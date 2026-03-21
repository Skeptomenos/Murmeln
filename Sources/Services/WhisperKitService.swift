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
    
    func isLoaded(variant: String) -> Bool {
        return whisperKit != nil && loadedVariant == variant
    }
    
    var currentVariant: String? {
        loadedVariant
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
    
    // Worker actor
    private let worker = WhisperKitWorker()
    
    enum ModelState: Equatable {
        case unloaded
        case downloading
        case loading
        case ready
        case error(String)
    }
    
    enum ServiceError: Error, LocalizedError {
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
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportDir = paths[0].appendingPathComponent("Murmeln")
        let modelsDir = appSupportDir.appendingPathComponent("Models")
        
        if !FileManager.default.fileExists(atPath: modelsDir.path) {
            try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }
        
        return modelsDir
    }
    
    init() {
        Task {
            scanDownloadedModels()
        }
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
        modelState = .downloading
        isDownloading = true
        downloadProgress = 0
        downloadStatus = "Starting download..."
        
        // Create cancellable task
        let task = Task<URL, Error> {
            // Use a Sendable closure that captures necessary MainActor state safely
            let progressCallback: @Sendable (Progress) -> Void = { progress in
                Task { @MainActor in
                    WhisperKitService.shared.downloadProgress = progress.fractionCompleted
                    WhisperKitService.shared.downloadStatus = "\(Int(progress.fractionCompleted * 100))%"
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
        } catch is CancellationError {
            modelState = .unloaded
            isDownloading = false
            downloadTask = nil
            downloadStatus = "Download cancelled"
            throw ServiceError.downloadCancelled
        } catch {
            modelState = .error(error.localizedDescription)
            isDownloading = false
            downloadTask = nil
            throw error
        }
    }
    
    /// Cancel the current download
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadStatus = "Cancelled"
        modelState = .unloaded
    }
    
    /// Unload the current model to free memory
    func unloadModel() async {
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
        
        modelState = .loading
        selectedModel = variant
        
        do {
            try await worker.loadModel(variant, modelsDirectory: modelsDirectory)
            modelState = .ready
        } catch {
            modelState = .error(error.localizedDescription)
            throw error
        }
    }
    
    // Transcribe audio file
    func transcribe(audioURL: URL) async throws -> String {
        guard modelState == .ready else {
            throw ServiceError.modelNotLoaded
        }
        
        let settings = AppSettings.shared
        var decodingOptions: DecodingOptions
        
        // Base configuration based on profile
        switch settings.whisperKitProfile {
        case .fast:
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
                supressTokens: [-1],
                noSpeechThreshold: 0.6,
                concurrentWorkerCount: 4,
                chunkingStrategy: .none
            )
        case .balanced:
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
                supressTokens: [-1],
                noSpeechThreshold: 0.6,
                chunkingStrategy: .none
            )
        case .accurate:
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
                supressTokens: [-1],
                noSpeechThreshold: 0.6,
                chunkingStrategy: .vad
            )
        case .custom:
            decodingOptions = DecodingOptions(
                verbose: false,
                task: .transcribe,
                temperature: Float(settings.whisperKitTemperature),
                usePrefillPrompt: settings.whisperKitPromptPrefill,
                usePrefillCache: settings.whisperKitPromptPrefill,
                withoutTimestamps: !settings.whisperKitEnableTimestamps,
                chunkingStrategy: settings.whisperKitUseVAD ? .vad : .none
            )
        }
        
        // Apply language override
        let selectedLanguages = settings.whisperKitLanguages
        if selectedLanguages.count == 1, let lang = selectedLanguages.first {
            decodingOptions.language = lang.code
            decodingOptions.detectLanguage = false
        } else {
            // 0 or >1 languages -> Auto detect
            decodingOptions.language = nil
            decodingOptions.detectLanguage = true
        }
        
        let results = try await worker.transcribe(audioPath: audioURL.path, decodingOptions: decodingOptions)
        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Check what models are already downloaded
    func scanDownloadedModels() {
        self.downloadedModels = AppSettings.shared.installedWhisperModels
    }
    
    func isModelDownloaded(_ variant: String) -> Bool {
        return downloadedModels.contains(variant)
    }
}
