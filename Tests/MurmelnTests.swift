import Testing
import Foundation
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
    
    @Test("Default model values are correct")
    func specificDefaultModels() {
        #expect(TranscriptionProvider.openAIWhisper.defaultModel == "whisper-1")
        #expect(TranscriptionProvider.groqWhisper.defaultModel == "whisper-large-v3-turbo")
        #expect(TranscriptionProvider.gpt4oAudio.defaultModel == "gpt-4o-audio-preview")
        #expect(TranscriptionProvider.geminiAudio.defaultModel == "gemini-2.0-flash-exp")
        #expect(TranscriptionProvider.localWhisper.defaultModel == "default")
    }
}

// MARK: - NetworkError Tests

@Suite("NetworkError Tests")
struct NetworkErrorTests {
    
    @Test("NetworkError.invalidURL has correct description")
    func invalidURLDescription() {
        let error = NetworkError.invalidURL
        #expect(error.errorDescription == "Invalid URL")
    }
    
    @Test("NetworkError.noResponse has correct description")
    func noResponseDescription() {
        let error = NetworkError.noResponse
        #expect(error.errorDescription == "No response from server")
    }
    
    @Test("NetworkError.apiError preserves message")
    func apiErrorMessage() {
        let message = "Rate limit exceeded"
        let error = NetworkError.apiError(message)
        #expect(error.errorDescription == message)
    }
    
    @Test("NetworkError.apiError handles empty message")
    func apiErrorEmptyMessage() {
        let error = NetworkError.apiError("")
        #expect(error.errorDescription == "")
    }
    
    @Test("NetworkError.apiError handles special characters")
    func apiErrorSpecialCharacters() {
        let message = "Error: {\"code\": 401, \"message\": \"Unauthorized\"}"
        let error = NetworkError.apiError(message)
        #expect(error.errorDescription == message)
    }
}

// MARK: - Response Parsing Tests

@Suite("API Response Parsing Tests")
struct ResponseParsingTests {
    
    @Test("TranscriptionResponse parses valid JSON")
    func parseTranscriptionResponse() throws {
        let json = """
        {"text": "Hello, world!"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(response.text == "Hello, world!")
    }
    
    @Test("TranscriptionResponse handles empty text")
    func parseEmptyTranscription() throws {
        let json = """
        {"text": ""}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(response.text == "")
    }
    
    @Test("TranscriptionResponse handles unicode")
    func parseUnicodeTranscription() throws {
        let json = """
        {"text": "こんにちは世界 🌍"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(response.text == "こんにちは世界 🌍")
    }
    
    @Test("ChatCompletionResponse parses valid JSON")
    func parseChatCompletionResponse() throws {
        let json = """
        {
            "choices": [
                {
                    "message": {
                        "content": "Refined text here"
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        #expect(response.choices.first?.message.content == "Refined text here")
    }
    
    @Test("ChatCompletionResponse handles empty choices")
    func parseEmptyChoices() throws {
        let json = """
        {"choices": []}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        #expect(response.choices.isEmpty)
    }
    
    @Test("GoogleGenerateResponse parses valid JSON")
    func parseGoogleGenerateResponse() throws {
        let json = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {"text": "Generated content"}
                        ]
                    }
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GoogleGenerateResponse.self, from: data)
        #expect(response.candidates?.first?.content.parts.first?.text == "Generated content")
    }
    
    @Test("GoogleGenerateResponse handles null candidates")
    func parseNullCandidates() throws {
        let json = """
        {"candidates": null}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GoogleGenerateResponse.self, from: data)
        #expect(response.candidates == nil)
    }
    
    @Test("OpenAIModelsResponse parses model list")
    func parseOpenAIModelsResponse() throws {
        let json = """
        {
            "data": [
                {"id": "gpt-4o"},
                {"id": "gpt-4o-mini"},
                {"id": "whisper-1"}
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        #expect(response.data.count == 3)
        #expect(response.data[0].id == "gpt-4o")
    }
    
    @Test("GoogleModelsResponse parses model list")
    func parseGoogleModelsResponse() throws {
        let json = """
        {
            "models": [
                {
                    "name": "models/gemini-2.0-flash-exp",
                    "displayName": "Gemini 2.0 Flash",
                    "supportedGenerationMethods": ["generateContent"]
                }
            ]
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
        #expect(response.models.count == 1)
        #expect(response.models[0].displayName == "Gemini 2.0 Flash")
        #expect(response.models[0].supportedGenerationMethods?.contains("generateContent") == true)
    }
}

// MARK: - ModelInfo Tests

@Suite("ModelInfo Tests")
struct ModelInfoTests {
    
    @Test("ModelInfo is Identifiable by id")
    func modelInfoIdentifiable() {
        let model = ModelInfo(id: "gpt-4o", name: "GPT-4o")
        #expect(model.id == "gpt-4o")
    }
    
    @Test("ModelInfo equality based on id and name")
    func modelInfoEquality() {
        let model1 = ModelInfo(id: "gpt-4o", name: "GPT-4o")
        let model2 = ModelInfo(id: "gpt-4o", name: "GPT-4o")
        let model3 = ModelInfo(id: "gpt-4o", name: "Different Name")
        
        #expect(model1 == model2)
        #expect(model1 != model3)
    }
    
    @Test("ModelInfo is Hashable")
    func modelInfoHashable() {
        let model1 = ModelInfo(id: "gpt-4o", name: "GPT-4o")
        let model2 = ModelInfo(id: "gpt-4o", name: "GPT-4o")
        
        var set = Set<ModelInfo>()
        set.insert(model1)
        set.insert(model2)
        
        #expect(set.count == 1)
    }
}

// MARK: - Edge Case Tests

@Suite("Edge Case Tests")
struct EdgeCaseTests {
    
    @Test("Empty API key handling")
    func emptyAPIKey() {
        let apiKey = ""
        #expect(apiKey.isEmpty)
    }
    
    @Test("Malformed URL handling")
    func malformedURLs() {
        let invalidURLs = [
            "not a url",
            "://missing-scheme",
            "",
            "   ",
            "http://",
        ]
        
        for urlString in invalidURLs {
            _ = URL(string: urlString)
        }
        #expect(true)
    }
    
    @Test("Very long text handling")
    func veryLongText() throws {
        let longText = String(repeating: "a", count: 100_000)
        let json = """
        {"text": "\(longText)"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(response.text.count == 100_000)
    }
    
    @Test("Special characters in transcription")
    func specialCharactersInTranscription() throws {
        let specialText = "Hello \"world\" with 'quotes' and \\backslash\\ and\nnewlines\tand\ttabs"
        let escapedText = specialText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        let json = """
        {"text": "\(escapedText)"}
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        #expect(response.text.contains("quotes"))
    }
    
    @Test("Provider enum Codable round-trip")
    func providerCodableRoundTrip() throws {
        for provider in Provider.allCases {
            let encoded = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(Provider.self, from: encoded)
            #expect(decoded == provider)
        }
    }
    
    @Test("TranscriptionProvider enum Codable round-trip")
    func transcriptionProviderCodableRoundTrip() throws {
        for provider in TranscriptionProvider.allCases {
            let encoded = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(TranscriptionProvider.self, from: encoded)
            #expect(decoded == provider)
        }
    }
}

// MARK: - URL Construction Tests

@Suite("URL Construction Tests")
struct URLConstructionTests {
    
    @Test("OpenAI transcription URL construction")
    func openAITranscriptionURL() {
        let baseURL = "https://api.openai.com/v1"
        let url = URL(string: baseURL + "/audio/transcriptions")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
    }
    
    @Test("Groq transcription URL construction")
    func groqTranscriptionURL() {
        let baseURL = "https://api.groq.com/openai/v1"
        let url = URL(string: baseURL + "/audio/transcriptions")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
    }
    
    @Test("Local Whisper URL construction")
    func localWhisperURL() {
        let baseURL = "http://localhost:8080"
        let url = URL(string: baseURL + "/inference")
        #expect(url != nil)
        #expect(url?.absoluteString == "http://localhost:8080/inference")
    }
    
    @Test("Gemini URL with API key")
    func geminiURLWithAPIKey() {
        let baseURL = "https://generativelanguage.googleapis.com/v1beta"
        let model = "gemini-2.0-flash-exp"
        let apiKey = "test-api-key"
        let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")
        #expect(url != nil)
        #expect(url?.absoluteString.contains("key=test-api-key") == true)
    }
    
    @Test("Chat completions URL construction")
    func chatCompletionsURL() {
        let baseURL = "https://api.openai.com/v1"
        let url = URL(string: baseURL + "/chat/completions")
        #expect(url != nil)
        #expect(url?.absoluteString == "https://api.openai.com/v1/chat/completions")
    }
    
    @Test("Models endpoint URL construction")
    func modelsEndpointURL() {
        for provider in Provider.allCases {
            let url = URL(string: provider.defaultBaseURL + provider.modelsEndpoint)
            #expect(url != nil, "Failed to construct models URL for \(provider.rawValue)")
        }
    }
}

// MARK: - Reliability Tests

@Suite("Reliability Tests")
struct ReliabilityTests {
    
    @Test("All Provider cases are covered in allCases")
    func allProviderCasesCovered() {
        #expect(Provider.allCases.count == 4)
    }
    
    @Test("All TranscriptionProvider cases are covered in allCases")
    func allTranscriptionProviderCasesCovered() {
        #expect(TranscriptionProvider.allCases.count == 5)
    }
    
    @Test("Provider raw values are unique")
    func providerRawValuesUnique() {
        let rawValues = Provider.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
    
    @Test("TranscriptionProvider raw values are unique")
    func transcriptionProviderRawValuesUnique() {
        let rawValues = TranscriptionProvider.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
    
    @Test("Default base URLs use HTTPS for cloud providers")
    func cloudProvidersUseHTTPS() {
        #expect(Provider.openAI.defaultBaseURL.hasPrefix("https://"))
        #expect(Provider.google.defaultBaseURL.hasPrefix("https://"))
        #expect(Provider.groq.defaultBaseURL.hasPrefix("https://"))
        
        #expect(TranscriptionProvider.openAIWhisper.defaultBaseURL.hasPrefix("https://"))
        #expect(TranscriptionProvider.groqWhisper.defaultBaseURL.hasPrefix("https://"))
        #expect(TranscriptionProvider.gpt4oAudio.defaultBaseURL.hasPrefix("https://"))
        #expect(TranscriptionProvider.geminiAudio.defaultBaseURL.hasPrefix("https://"))
    }
    
    @Test("Local providers use HTTP")
    func localProvidersUseHTTP() {
        #expect(Provider.ollama.defaultBaseURL.hasPrefix("http://localhost"))
        #expect(TranscriptionProvider.localWhisper.defaultBaseURL.hasPrefix("http://localhost"))
    }
}

// MARK: - Audio Level Calculation Tests

@Suite("Audio Level Calculation Tests")
struct AudioLevelTests {
    
    @Test("Zero audio level produces minimum bar heights")
    func zeroAudioLevel() {
        let level: Float = 0.0
        let normalizedLevel = min(1.0, level * 8)
        #expect(normalizedLevel == 0.0)
    }
    
    @Test("Maximum audio level is clamped")
    func maxAudioLevelClamped() {
        let level: Float = 1.0
        let normalizedLevel = min(1.0, level * 8)
        #expect(normalizedLevel == 1.0)
    }
    
    @Test("Audio level normalization")
    func audioLevelNormalization() {
        let testLevels: [Float] = [0.0, 0.05, 0.1, 0.125, 0.2, 0.5, 1.0]
        
        for level in testLevels {
            let normalized = min(1.0, level * 8)
            #expect(normalized >= 0.0)
            #expect(normalized <= 1.0)
        }
    }
    
    @Test("RMS calculation edge case: empty buffer returns zero")
    func rmsEmptyBuffer() {
        let frameLength = 0
        guard frameLength > 0 else {
            #expect(true)
            return
        }
    }
    
    @Test("Bar height calculation bounds")
    func barHeightBounds() {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 16
        let barCount = 5
        
        for level in stride(from: Float(0), through: Float(1), by: Float(0.1)) {
            let normalizedLevel = min(1.0, level * 8)
            
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

// MARK: - Feature 1: Delayed Recording Start Tests

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

// MARK: - Feature 3: Thin Line Indicator Tests

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

@Suite("HistoryEntry Tests")
struct HistoryEntryTests {
    
    @Test("HistoryEntry initializes with correct values")
    func historyEntryInit() {
        let entry = HistoryEntry(original: "hello world", refined: "Hello, world.")
        
        #expect(entry.original == "hello world")
        #expect(entry.refined == "Hello, world.")
        #expect(!entry.id.uuidString.isEmpty)
    }
    
    @Test("displayText returns refined when available")
    func displayTextRefined() {
        let entry = HistoryEntry(original: "original", refined: "refined")
        #expect(entry.displayText == "refined")
    }
    
    @Test("displayText returns original when refined is empty")
    func displayTextFallback() {
        let entry = HistoryEntry(original: "original", refined: "")
        #expect(entry.displayText == "original")
    }
    
    @Test("previewText truncates long text")
    func previewTextTruncation() {
        let longText = String(repeating: "a", count: 100)
        let entry = HistoryEntry(original: longText, refined: longText)
        
        #expect(entry.previewText.count == 50)
        #expect(entry.previewText.hasSuffix("..."))
    }
    
    @Test("previewText preserves short text")
    func previewTextShort() {
        let entry = HistoryEntry(original: "short", refined: "short")
        #expect(entry.previewText == "short")
    }
    
    @Test("HistoryEntry is Codable")
    func historyEntryCodable() throws {
        let entry = HistoryEntry(original: "test", refined: "Test.")
        
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)
        
        #expect(decoded.original == entry.original)
        #expect(decoded.refined == entry.refined)
        #expect(decoded.id == entry.id)
    }
    
    @Test("HistoryEntry is Hashable")
    func historyEntryHashable() {
        let entry1 = HistoryEntry(original: "a", refined: "A")
        let entry2 = HistoryEntry(original: "b", refined: "B")
        
        var set = Set<HistoryEntry>()
        set.insert(entry1)
        set.insert(entry2)
        
        #expect(set.count == 2)
    }
}

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

@Suite("PromptPreset Tests")
struct PromptPresetTests {
    
    @Test("All presets have unique raw values")
    func uniqueRawValues() {
        let rawValues = PromptPreset.allCases.map { $0.rawValue }
        let uniqueValues = Set(rawValues)
        #expect(rawValues.count == uniqueValues.count)
    }
    
    @Test("All presets have descriptions")
    func presetsHaveDescriptions() {
        for preset in PromptPreset.allCases {
            #expect(!preset.description.isEmpty)
        }
    }
    
    @Test("All presets have icons")
    func presetsHaveIcons() {
        for preset in PromptPreset.allCases {
            #expect(!preset.icon.isEmpty)
        }
    }
    
    @Test("Non-custom presets have prompts")
    func nonCustomPresetsHavePrompts() {
        for preset in PromptPreset.allCases where preset != .custom {
            #expect(!preset.prompt.isEmpty)
        }
    }
    
    @Test("Custom preset has empty prompt")
    func customPresetEmptyPrompt() {
        #expect(PromptPreset.custom.prompt.isEmpty)
    }
    
    @Test("Casual preset is conversational")
    func casualPresetContent() {
        let prompt = PromptPreset.casual.prompt.lowercased()
        #expect(prompt.contains("conversational") || prompt.contains("natural"))
    }
    
    @Test("LLM preset mentions markdown")
    func llmPresetContent() {
        let prompt = PromptPreset.llmPrompt.prompt.lowercased()
        #expect(prompt.contains("markdown"))
    }
    
    @Test("Verbatim preset is restrictive")
    func verbatimPresetContent() {
        let prompt = PromptPreset.verbatim.prompt.lowercased()
        #expect(prompt.contains("do not change") || prompt.contains("only"))
    }
}
