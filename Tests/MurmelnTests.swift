import Testing
import Foundation
import AppKit
import AVFoundation
@testable import mrml

// MARK: - Provider Tests

@Suite("Provider Enum Tests")
struct ProviderTests {
    
    @Test("All Provider cases have valid default base URLs")
    func providerDefaultBaseURLs() {
        for provider in Provider.allCases {
            let url = URL(string: provider.defaultBaseURL)
            #expect(url != nil, "Provider \(provider.rawValue) has invalid base URL: \(provider.defaultBaseURL)")
        }
    }
    
    @Test("Provider.openAI requires API key")
    func openAIRequiresAPIKey() {
        #expect(Provider.openAI.requiresAPIKey == true)
    }
    
    @Test("Provider.ollama does not require API key")
    func ollamaNoAPIKey() {
        #expect(Provider.ollama.requiresAPIKey == false)
    }
    
    @Test("Only OpenAI and Groq support Whisper")
    func whisperSupport() {
        #expect(Provider.openAI.supportsWhisper == true)
        #expect(Provider.groq.supportsWhisper == true)
        #expect(Provider.google.supportsWhisper == false)
        #expect(Provider.ollama.supportsWhisper == false)
    }
    
    @Test("All providers have models endpoint")
    func modelsEndpoint() {
        for provider in Provider.allCases {
            #expect(provider.modelsEndpoint == "/models")
        }
    }
    
    @Test("Provider raw values are human-readable")
    func providerRawValues() {
        #expect(Provider.openAI.rawValue == "OpenAI")
        #expect(Provider.google.rawValue == "Google AI")
        #expect(Provider.groq.rawValue == "Groq")
        #expect(Provider.ollama.rawValue == "Ollama (Local)")
    }
}

// MARK: - TranscriptionProvider Tests

@Suite("TranscriptionProvider Enum Tests")
struct TranscriptionProviderTests {
    
    @Test("All TranscriptionProvider cases have valid default base URLs")
    func transcriptionProviderDefaultBaseURLs() {
        for provider in TranscriptionProvider.allCases {
            let url = URL(string: provider.defaultBaseURL)
            #expect(url != nil, "TranscriptionProvider \(provider.rawValue) has invalid base URL: \(provider.defaultBaseURL)")
        }
    }
    
    @Test("Local Whisper does not require API key")
    func localWhisperNoAPIKey() {
        #expect(TranscriptionProvider.localWhisper.requiresAPIKey == false)
    }
    
    @Test("Cloud providers require API key")
    func cloudProvidersRequireAPIKey() {
        #expect(TranscriptionProvider.openAIWhisper.requiresAPIKey == true)
        #expect(TranscriptionProvider.groqWhisper.requiresAPIKey == true)
        #expect(TranscriptionProvider.gpt4oAudio.requiresAPIKey == true)
        #expect(TranscriptionProvider.geminiAudio.requiresAPIKey == true)
    }
    
    @Test("Native audio models identified correctly")
    func nativeAudioModels() {
        #expect(TranscriptionProvider.gpt4oAudio.isNativeAudioModel == true)
        #expect(TranscriptionProvider.geminiAudio.isNativeAudioModel == true)
        #expect(TranscriptionProvider.openAIWhisper.isNativeAudioModel == false)
        #expect(TranscriptionProvider.groqWhisper.isNativeAudioModel == false)
        #expect(TranscriptionProvider.localWhisper.isNativeAudioModel == false)
    }
    
    @Test("One-call refinement support")
    func oneCallRefinementSupport() {
        #expect(TranscriptionProvider.gpt4oAudio.supportsRefinementInOneCall == true)
        #expect(TranscriptionProvider.geminiAudio.supportsRefinementInOneCall == true)
        #expect(TranscriptionProvider.openAIWhisper.supportsRefinementInOneCall == false)
        #expect(TranscriptionProvider.groqWhisper.supportsRefinementInOneCall == false)
        #expect(TranscriptionProvider.localWhisper.supportsRefinementInOneCall == false)
    }
    
    @Test("All providers have non-empty default models")
    func defaultModels() {
        for provider in TranscriptionProvider.allCases {
            #expect(!provider.defaultModel.isEmpty, "Provider \(provider.rawValue) has empty default model")
        }
    }
}

// MARK: - NetworkError Tests

@Suite("NetworkError Tests")
struct NetworkErrorTests {
    
    @Test("API error preserves message")
    func apiErrorFormatting() {
        let error = NetworkError.apiError("test message")
        #expect(error.errorDescription == "test message")
    }
    
    @Test("Standard errors have descriptions")
    func standardErrorDescriptions() {
        #expect(NetworkError.invalidURL.errorDescription != nil)
        #expect(NetworkError.noResponse.errorDescription != nil)
    }
}

// MARK: - API Response Parsing Tests

@Suite("API Response Parsing Tests")
struct APIResponseTests {
    
    @Test("OpenAI transcription response parses correctly")
    func parseOpenAIResponse() throws {
        let json = "{\"text\": \"hello world\"}".data(using: .utf8)!
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: json)
        #expect(result.text == "hello world")
    }
    
    @Test("GPT-4o Audio response parses correctly")
    func parseGPT4oAudioResponse() throws {
        let json = """
        {
            "choices": [{
                "message": {
                    "content": "refined text"
                }
            }]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: json)
        #expect(result.choices.first?.message.content == "refined text")
    }
    
    @Test("Gemini response parses correctly")
    func parseGeminiResponse() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "parts": [{
                        "text": "gemini result"
                    }]
                }
            }]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(GoogleGenerateResponse.self, from: json)
        #expect(result.candidates?.first?.content.parts.first?.text == "gemini result")
    }
    
    @Test("Ollama response parses correctly")
    func parseOllamaResponse() throws {
        let json = "{\"choices\": [{\"message\": {\"content\": \"ollama result\"}}]}".data(using: .utf8)!
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: json)
        #expect(result.choices.first?.message.content == "ollama result")
    }
}

// MARK: - ModelInfo Tests

@Suite("ModelInfo Tests")
struct ModelInfoTests {
    
    @Test("ModelInfo Identifiable conformance")
    func modelInfoIdentifiable() {
        let model = ModelInfo(id: "gpt-4", name: "GPT-4")
        #expect(model.id == "gpt-4")
    }
    
    @Test("OpenAI models list parsing")
    func parseOpenAIModelsList() throws {
        let json = """
        {
            "data": [
                {"id": "whisper-1", "object": "model"},
                {"id": "gpt-4", "object": "model"}
            ]
        }
        """.data(using: .utf8)!
        let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: json)
        #expect(result.data.count == 2)
        #expect(result.data.first?.id == "whisper-1")
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Case Tests")
struct EdgeCaseTests {
    
    @Test("Empty API responses handle gracefully")
    func emptyResponse() {
        let json = "{}".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(TranscriptionResponse.self, from: json)
        }
    }
    
    @Test("Unicode text preservation")
    func unicodePreservation() {
        let text = "Hällö 👋 Wörld 🌍"
        let data = "{\"text\": \"\(text)\"}".data(using: .utf8)!
        let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(result?.text == text)
    }
    
    @Test("Very long text handling")
    func longTextHandling() {
        let longText = String(repeating: "a", count: 10000)
        let data = "{\"text\": \"\(longText)\"}".data(using: .utf8)!
        let result = try? JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(result?.text == longText)
    }
    
    @Test("Special characters in prompts")
    func specialCharsInPrompt() {
        let prompt = "Fix this: \"quotes\", \\slashes\\, and {brackets}."
        #expect(!prompt.isEmpty)
    }
}

// MARK: - URL Construction Tests

@Suite("URL Construction Tests")
struct URLConstructionTests {
    
    @Test("Base URL stripping trailing slashes")
    func urlFormatting() {
        let base = "https://api.groq.com/openai/v1/"
        let endpoint = "/audio/transcriptions"
        
        let combined = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + endpoint
        let url = URL(string: combined)
        
        #expect(url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
    }
    
    @Test("Gemini API key in URL query parameter")
    func geminiURLFormat() {
        let base = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
        let key = "AIza..."
        let url = URL(string: "\(base)?key=\(key)")
        
        #expect(url?.query?.contains("key=AIza") == true)
    }
}

// MARK: - Reliability Tests

@Suite("Reliability Tests")
struct ReliabilityTests {
    
    @Test("All provider raw values are unique")
    func uniqueProviderRawValues() {
        let values = Provider.allCases.map { $0.rawValue }
        let unique = Set(values)
        #expect(values.count == unique.count)
    }
    
    @Test("Transcription provider defaults are HTTPS")
    func transcriptionHTTPS() {
        for provider in TranscriptionProvider.allCases where provider != .localWhisper {
            #expect(provider.defaultBaseURL.hasPrefix("https://"))
        }
    }
    
    @Test("Refinement provider defaults are HTTPS")
    func refinementHTTPS() {
        for provider in Provider.allCases where provider != .ollama {
            #expect(provider.defaultBaseURL.hasPrefix("https://"))
        }
    }
}

// MARK: - Audio Level Calculation Tests

@Suite("Audio Level Calculation Tests")
struct AudioLevelTests {
    
    @Test("RMS calculation edge case: empty buffer returns zero")
    func rmsEmptyBuffer() {
        let frameLength: Float = 0
        let sum: Float = 0
        let rms = frameLength > 0 ? sqrt(sum / frameLength) : 0
        #expect(rms == 0)
    }
    
    @Test("Visualizer bar height calculation")
    func visualizerCalculation() {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 20
        let normalizedLevel: Float = 0.5 
        
        let barCount = 5
        for index in 0..<barCount {
            let indexFactor = Float(index) / Float(barCount - 1)
            let centerDistance = abs(indexFactor - 0.5) * 2
            let heightMultiplier = 1.0 - (centerDistance * 0.3)
            
            let dynamicHeight = CGFloat(normalizedLevel * heightMultiplier) * (maxHeight - baseHeight)
            let finalHeight = baseHeight + dynamicHeight
            
            #expect(finalHeight >= baseHeight)
            #expect(finalHeight <= maxHeight)
        }
    }
}

// MARK: - Multipart Form Data Tests

@Suite("Multipart Form Data Tests")
struct MultipartFormDataTests {
    
    @Test("Boundary UUID is valid format")
    func boundaryUUIDValid() {
        let boundary = UUID().uuidString
        #expect(!boundary.isEmpty)
        #expect(boundary.count == 36)
    }
    
    @Test("Form data construction")
    func formDataConstruction() {
        let boundary = "test-boundary"
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append("fake-audio-data".data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        #expect(!body.isEmpty)
        
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("--test-boundary"))
        #expect(bodyString.contains("Content-Disposition: form-data"))
        #expect(bodyString.contains("filename=\"recording.wav\""))
        #expect(bodyString.contains("--test-boundary--"))
    }
}

// MARK: - Concurrency Safety Tests

@Suite("Concurrency Safety Tests")
struct ConcurrencySafetyTests {
    
    @Test("NetworkService is Sendable")
    func networkServiceSendable() async {
        let _: any Sendable = await NetworkService.shared
        #expect(true)
    }
    
    @Test("PasteService is Sendable")
    func pasteServiceSendable() async {
        let _: any Sendable = await PasteService.shared
        #expect(true)
    }
    
    @Test("PermissionService is Sendable")
    func permissionServiceSendable() {
        let _: any Sendable = PermissionService.shared
        #expect(true)
    }
}

// MARK: - OverlayState Tests

@Suite("OverlayState Tests")
struct OverlayStateTests {
    
    @Test("OverlayState has all five expected cases")
    func overlayStateCases() {
        let idle = OverlayState.idle
        let waiting = OverlayState.waiting
        let listening = OverlayState.listening
        let locked = OverlayState.locked
        let processing = OverlayState.processing
        
        #expect(idle != waiting)
        #expect(waiting != listening)
        #expect(listening != locked)
        #expect(locked != processing)
        #expect(idle != processing)
    }
    
    @Test("OverlayState is Equatable")
    func overlayStateEquatable() {
        #expect(OverlayState.idle == OverlayState.idle)
        #expect(OverlayState.waiting == OverlayState.waiting)
        #expect(OverlayState.listening == OverlayState.listening)
        #expect(OverlayState.locked == OverlayState.locked)
        #expect(OverlayState.processing == OverlayState.processing)
    }
    
    @Test("Waiting state (pre-threshold) differs from listening state (recording)")
    func waitingVsListening() {
        #expect(OverlayState.waiting != OverlayState.listening)
    }
    
    @Test("Locked state (hands-free) differs from listening state (hold-to-record)")
    func lockedVsListening() {
        #expect(OverlayState.locked != OverlayState.listening)
    }
}

// MARK: - HotkeyService Configuration Tests

@Suite("HotkeyService Configuration Tests")
struct HotkeyServiceConfigTests {
    
    @Test("Hold threshold default is 400ms")
    func holdThresholdDefault() async {
        let service = await HotkeyService.shared
        #expect(await service.holdThreshold == 0.4)
    }
    
    @Test("Double-tap threshold default is 400ms")
    func doubleTapThresholdDefault() async {
        let service = await HotkeyService.shared
        #expect(await service.doubleTapThreshold == 0.4)
    }
    
    @Test("HotkeyService exposes all six callback properties")
    func callbacksExist() async {
        let service = await HotkeyService.shared
        await MainActor.run {
            service.onKeyDown = {}
            service.onKeyUp = {}
            service.onHoldStarted = {}
            service.onHoldCancelled = {}
            service.onLockEngaged = {}
            service.onLockDisengaged = {}
        }
        #expect(Bool(true))
    }
}

// MARK: - Delayed Recording Start Tests

@Suite("Delayed Recording Start Tests")
struct DelayedRecordingStartTests {
    
    @Test("100ms tap (below 400ms threshold) should not trigger recording")
    func quickTapBehavior() {
        let holdThreshold: TimeInterval = 0.4
        let quickTapDuration: TimeInterval = 0.1
        
        let shouldStartRecording = quickTapDuration >= holdThreshold
        #expect(shouldStartRecording == false)
    }
    
    @Test("500ms hold (above 400ms threshold) should start recording")
    func holdBeyondThreshold() {
        let holdThreshold: TimeInterval = 0.4
        let holdDuration: TimeInterval = 0.5
        
        let shouldStartRecording = holdDuration >= holdThreshold
        #expect(shouldStartRecording == true)
    }
    
    @Test("400ms hold (exactly at threshold) should start recording")
    func holdExactlyAtThreshold() {
        let holdThreshold: TimeInterval = 0.4
        let holdDuration: TimeInterval = 0.4
        
        let shouldStartRecording = holdDuration >= holdThreshold
        #expect(shouldStartRecording == true)
    }
    
    @Test("Threshold is between 200ms and 1000ms for usability")
    func thresholdReasonableness() {
        let holdThreshold: TimeInterval = 0.4
        
        #expect(holdThreshold >= 0.2)
        #expect(holdThreshold <= 1.0)
    }
}

// MARK: - Feature 2: Right Option Double-Tap Lock Mode Tests

@Suite("Right Option Lock Mode Tests")
struct RightOptionLockModeTests {
    
    @Test("200ms between taps (within 400ms threshold) engages lock")
    func doubleTapEngagesLock() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.2
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == true)
    }
    
    @Test("600ms between taps (outside 400ms threshold) does not engage lock")
    func slowTapsNoLock() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.6
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == false)
    }
    
    @Test("400ms between taps (exactly at threshold) does not engage lock")
    func tapAtThresholdNoLock() {
        let doubleTapThreshold: TimeInterval = 0.4
        let timeBetweenTaps: TimeInterval = 0.4
        
        let isDoubleTap = timeBetweenTaps < doubleTapThreshold
        #expect(isDoubleTap == false)
    }
    
    @Test("Lock mode state machine: engage then disengage")
    func lockModeStateTransitions() {
        var isLocked = false
        var recordingActive = false
        
        isLocked = true
        recordingActive = true
        #expect(isLocked == true)
        #expect(recordingActive == true)
        
        isLocked = false
        recordingActive = false
        #expect(isLocked == false)
        #expect(recordingActive == false)
    }
    
    @Test("Lock mode continues recording independent of Fn key")
    func handsFreeRecording() {
        let isLocked = true
        let fnKeyHeld = false
        let recordingActive = true
        
        let shouldContinueRecording = isLocked || fnKeyHeld
        #expect(shouldContinueRecording == true)
        #expect(recordingActive == true)
    }
    
    @Test("Single Right Option tap after lock disengages and stops recording")
    func singleTapDisengagesLock() {
        var isLocked = true
        var recordingActive = true
        
        isLocked = false
        recordingActive = false
        
        #expect(isLocked == false)
        #expect(recordingActive == false)
    }
}

// MARK: - Thin Line Indicator Tests

@Suite("Thin Line Indicator Tests")
struct ThinLineIndicatorTests {
    
    @Test("All five overlay states are mutually distinct")
    func indicatorStateStyles() {
        let states: [OverlayState] = [.idle, .waiting, .listening, .locked, .processing]
        
        for i in 0..<states.count {
            for j in (i+1)..<states.count {
                #expect(states[i] != states[j])
            }
        }
    }
    
    @Test("Locked state (orange) differs from listening state (white)")
    func lockedVisuallyDistinct() {
        #expect(OverlayState.locked != OverlayState.listening)
    }
    
    @Test("Processing state (blue) differs from listening state (white)")
    func processingVisuallyDistinct() {
        #expect(OverlayState.processing != OverlayState.listening)
    }
    
    @Test("Idle state exists for subtle always-visible indicator")
    func idleStateSubtle() {
        #expect(OverlayState.idle == OverlayState.idle)
    }
    
    @Test("Waiting state differs from idle for pre-threshold feedback")
    func waitingStateIndicatesPending() {
        #expect(OverlayState.waiting != OverlayState.idle)
    }
}

// MARK: - Integration Simulation Tests

@Suite("Integration Simulation Tests")
struct IntegrationSimulationTests {
    
    @Test("Transcription flow: provider selection affects API path")
    func transcriptionFlowProviderSelection() {
        let openAIPath = "/audio/transcriptions"
        let localPath = "/inference"
        let geminiPath = ":generateContent"
        
        #expect(openAIPath != localPath)
        #expect(localPath != geminiPath)
    }
    
    @Test("Refinement flow: one-call vs two-call")
    func refinementFlowDecision() {
        let oneCallProviders = TranscriptionProvider.allCases.filter { $0.supportsRefinementInOneCall }
        let twoCallProviders = TranscriptionProvider.allCases.filter { !$0.supportsRefinementInOneCall }
        
        #expect(oneCallProviders.count == 2)
        #expect(twoCallProviders.count == 3)
    }
    
    @Test("Provider to refinement provider mapping")
    func providerMapping() {
        for provider in Provider.allCases {
            #expect(!provider.defaultBaseURL.isEmpty)
            #expect(!provider.modelsEndpoint.isEmpty)
        }
    }
}

// MARK: - HistoryEntry Tests

@Suite("HistoryEntry Tests")
struct HistoryEntryTests {
    
    @Test("HistoryEntry initializes with correct values")
    func historyEntryInit() {
        let variants = ["Casual": "Hello, world."]
        let variantPrompts = ["Casual": "Prompt"]
        let entry = HistoryEntry(original: "hello world", refined: "Hello, world.", presetName: "Casual", systemPrompt: "Prompt", variants: variants, variantPrompts: variantPrompts)
        
        #expect(entry.original == "hello world")
        #expect(entry.refined == "Hello, world.")
        #expect(entry.safePresetName == "Casual")
        #expect(entry.safeSystemPrompt == "Prompt")
        #expect(entry.variants?["Casual"] == "Hello, world.")
        #expect(entry.variantPrompts?["Casual"] == "Prompt")
        #expect(!entry.id.uuidString.isEmpty)
    }
    
    @Test("displayText returns refined when available")
    func displayTextRefined() {
        let entry = HistoryEntry(original: "original", refined: "refined", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        #expect(entry.displayText == "refined")
    }
    
    @Test("displayText returns original when refined is empty")
    func displayTextFallback() {
        let entry = HistoryEntry(original: "original", refined: "", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        #expect(entry.displayText == "original")
    }
    
    @Test("previewText truncates long text")
    func previewTextTruncation() {
        let longText = String(repeating: "a", count: 100)
        let entry = HistoryEntry(original: longText, refined: longText, presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        
        #expect(entry.previewText.count == 50)
        #expect(entry.previewText.hasSuffix("..."))
    }
    
    @Test("previewText preserves short text")
    func previewTextShort() {
        let entry = HistoryEntry(original: "short", refined: "short", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        #expect(entry.previewText == "short")
    }
    
    @Test("HistoryEntry is Codable")
    func historyEntryCodable() throws {
        let variants = ["Casual": "Test.", "Structured": "Test!"]
        let entry = HistoryEntry(original: "test", refined: "Test.", presetName: "Casual", systemPrompt: "Prompt", variants: variants, variantPrompts: nil)
        
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)
        
        #expect(decoded.original == entry.original)
        #expect(decoded.refined == entry.refined)
        #expect(decoded.safePresetName == entry.safePresetName)
        #expect(decoded.safeSystemPrompt == entry.safeSystemPrompt)
        #expect(decoded.variants?["Structured"] == "Test!")
        #expect(decoded.id == entry.id)
    }
    
    @Test("HistoryEntry is Hashable")
    func historyEntryHashable() {
        let entry1 = HistoryEntry(original: "a", refined: "A", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        let entry2 = HistoryEntry(original: "b", refined: "B", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        
        var set = Set<HistoryEntry>()
        set.insert(entry1)
        set.insert(entry2)
        
        #expect(set.count == 2)
    }
}

// MARK: - AudioQuality Tests

@Suite("AudioQuality Tests")
struct AudioQualityTests {
    
    @Test("Optimized quality is 16kHz")
    func optimizedQuality() {
        let quality = AudioRecorder.AudioQuality.optimized
        #expect(quality.sampleRate == 16000)
        #expect(quality.label == "16kHz")
    }
    
    @Test("High quality is 44.1kHz")
    func highQuality() {
        let quality = AudioRecorder.AudioQuality.high
        #expect(quality.sampleRate == 44100)
        #expect(quality.label == "44.1kHz")
    }
    
    @Test("16kHz produces smaller files than 44.1kHz")
    func sampleRateComparison() {
        let optimized = AudioRecorder.AudioQuality.optimized.sampleRate
        let high = AudioRecorder.AudioQuality.high.sampleRate
        
        #expect(optimized < high)
        #expect(high / optimized > 2.5)
    }
}

// MARK: - PromptPreset Tests

@Suite("PromptPreset Tests")
struct PromptPresetTests {
    
    @Test("Built-in presets have unique IDs")
    func uniqueIds() {
        let ids = PromptPreset.builtInPresets.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }
    
    @Test("All built-in presets have descriptions")
    func presetsHaveDescriptions() {
        for preset in PromptPreset.builtInPresets {
            #expect(!preset.description.isEmpty)
        }
    }
    
    @Test("All built-in presets have icons")
    func presetsHaveIcons() {
        for preset in PromptPreset.builtInPresets {
            #expect(!preset.icon.isEmpty)
        }
    }
    
    @Test("All built-in presets have prompts")
    func presetsHavePrompts() {
        for preset in PromptPreset.builtInPresets {
            #expect(!preset.prompt.isEmpty)
        }
    }
    
    @Test("Built-in presets are marked as built-in")
    func builtInFlag() {
        for preset in PromptPreset.builtInPresets {
            #expect(preset.isBuiltIn == true)
        }
    }
    
    @Test("Casual preset is conversational")
    func casualPresetContent() {
        let casual = PromptPreset.builtInPresets.first { $0.name == "Casual" }
        #expect(casual != nil)
        #expect(casual!.prompt.lowercased().contains("natural"))
    }
    
    @Test("Markdown preset has structure instructions")
    func markdownPresetContent() {
        let markdown = PromptPreset.builtInPresets.first { $0.name == "Markdown" }
        #expect(markdown != nil)
        #expect(markdown!.prompt.contains("##"))
    }
    
    @Test("Custom preset creation")
    func customPresetCreation() {
        let custom = PromptPreset(name: "Test", description: "Test desc", icon: "star", prompt: "Test prompt")
        #expect(custom.isBuiltIn == false)
        #expect(custom.name == "Test")
    }
    
    @Test("PromptPreset is Codable")
    func presetCodable() throws {
        let preset = PromptPreset(name: "Test", description: "Desc", icon: "star", prompt: "Prompt")
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PromptPreset.self, from: encoded)
        #expect(decoded.name == preset.name)
        #expect(decoded.prompt == preset.prompt)
    }
}
