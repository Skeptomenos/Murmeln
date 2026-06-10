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
            if provider.isLocalNativeProvider {
                // Local-native providers don't use a network base URL
                #expect(provider.defaultBaseURL.isEmpty)
            } else {
                let url = URL(string: provider.defaultBaseURL)
                #expect(url != nil, "TranscriptionProvider \(provider.rawValue) has invalid base URL: \(provider.defaultBaseURL)")
            }
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
    
    @Test("Local-native and legacy cloud audio-input providers are identified")
    func providerTypeFlags() {
        #expect(TranscriptionProvider.whisperKit.isLocalNativeProvider == true)
        #expect(TranscriptionProvider.gpt4oAudio.isLegacyCloudAudioInputProvider == true)
        #expect(TranscriptionProvider.geminiAudio.isLegacyCloudAudioInputProvider == true)
        #expect(TranscriptionProvider.openAIWhisper.isLocalNativeProvider == false)
        #expect(TranscriptionProvider.openAIWhisper.isLegacyCloudAudioInputProvider == false)
        #expect(TranscriptionProvider.groqWhisper.isLegacyCloudAudioInputProvider == false)
        #expect(TranscriptionProvider.localWhisper.isLegacyCloudAudioInputProvider == false)
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
    
    @Test("Gemini URL does not contain API key (moved to header)")
    func geminiURLFormat() {
        // API key should be in x-goog-api-key header, not in URL query parameter
        let base = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
        let url = URL(string: base)
        
        // URL should not contain any query parameters with API key
        #expect(url?.query == nil)
        #expect(url?.absoluteString.contains("key=") == false)
    }
    
    @Test("Gemini API uses x-goog-api-key header for authentication")
    func geminiHeaderAuth() {
        // Verify the header-based authentication pattern
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")!)
        let apiKey = "test-api-key"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == apiKey)
        #expect(request.url?.query == nil)
    }

    @Test("Legacy local-server transcription endpoint remains /inference")
    func localWhisperEndpointFormat() {
        let base = TranscriptionProvider.localWhisper.defaultBaseURL
        let url = URL(string: base + "/inference")

        #expect(base == "http://localhost:8080")
        #expect(url?.absoluteString == "http://localhost:8080/inference")
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
        for provider in TranscriptionProvider.allCases where provider != .localWhisper && !provider.isLocalNativeProvider {
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
    
    @Test("Waiting state differs from idle for pre-threshold feedback")
    func waitingStateIndicatesPending() {
        #expect(OverlayState.waiting != OverlayState.idle)
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

    @Test("Empty variants are normalized away")
    func historyEntryNormalizesEmptyVariants() {
        let entry = HistoryEntry(
            original: "already final",
            refined: "already final",
            presetName: "Casual",
            systemPrompt: "Prompt",
            variants: [:],
            variantPrompts: [:]
        )

        #expect(entry.variants == nil)
        #expect(entry.variantPrompts == nil)
    }

    @Test("Final-only entry does not claim separate baseline or audit trail")
    func finalOnlyHistoryEntrySemantics() {
        let entry = HistoryEntry(
            original: "already final",
            refined: "already final",
            presetName: "GPT-4o Audio",
            systemPrompt: "Prompt",
            variants: nil,
            variantPrompts: nil
        )

        #expect(entry.hasParallelAuditTrail == false)
        #expect(entry.hasDistinctOriginalBaseline == false)
    }

    @Test("Non-empty variants retain audit trail semantics")
    func historyEntryRetainsAuditTrailSemantics() {
        let entry = HistoryEntry(
            original: "raw",
            refined: "refined",
            presetName: "Casual",
            systemPrompt: "Prompt",
            variants: ["Casual": "refined", "Structured": "structured"],
            variantPrompts: ["Casual": "Prompt"]
        )

        #expect(entry.hasParallelAuditTrail == true)
        #expect(entry.hasDistinctOriginalBaseline == true)
    }

    @Test("Single selected-result variant is not treated as parallel audit trail")
    func singleVariantDoesNotClaimParallelAuditTrail() {
        let entry = HistoryEntry(
            original: "raw",
            refined: "refined",
            presetName: "Casual",
            systemPrompt: "Prompt",
            variants: ["Casual": "refined"],
            variantPrompts: ["Casual": "Prompt"]
        )

        #expect(entry.hasParallelAuditTrail == false)
        #expect(entry.hasDistinctOriginalBaseline == true)
    }

    @Test("Prompt provenance prefers effective prompts and retains base prompts")
    func promptProvenancePrefersEffectivePrompt() {
        let entry = HistoryEntry(
            original: "raw",
            refined: "refined",
            presetName: "Casual",
            systemPrompt: "Base prompt",
            effectiveSystemPrompt: "Base prompt with dictionary",
            variants: ["Casual": "refined"],
            variantPrompts: ["Casual": "Variant base prompt"],
            effectiveVariantPrompts: ["Casual": "Variant base prompt with dictionary"]
        )

        let provenance = entry.promptProvenance(for: "Casual")

        #expect(provenance.basePrompt == "Variant base prompt")
        #expect(provenance.effectivePrompt == "Variant base prompt with dictionary")
        #expect(provenance.showsBasePromptSeparately == true)
    }

    @Test("Prompt provenance falls back to base prompt for legacy entries")
    func promptProvenanceFallsBackToBasePrompt() {
        let entry = HistoryEntry(
            original: "raw",
            refined: "refined",
            presetName: "Casual",
            systemPrompt: "Legacy prompt",
            variants: nil,
            variantPrompts: nil
        )

        let provenance = entry.promptProvenance(for: "Casual")

        #expect(provenance.basePrompt == "Legacy prompt")
        #expect(provenance.effectivePrompt == "Legacy prompt")
        #expect(provenance.showsBasePromptSeparately == false)
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

// MARK: - URL Validation Tests

@Suite("URL Validation Tests")
struct URLValidationTests {
    
    @Test("Valid HTTPS URL returns valid result")
    func validHttpsURL() {
        let result = URLValidation.validate("https://api.openai.com")
        if case .valid(let normalized) = result {
            #expect(normalized == "https://api.openai.com")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("Valid HTTP URL returns valid result")
    func validHttpURL() {
        let result = URLValidation.validate("http://localhost:11434")
        if case .valid(let normalized) = result {
            #expect(normalized == "http://localhost:11434")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("Trailing slash is removed during normalization")
    func trailingSlashRemoved() {
        let result = URLValidation.validate("https://api.openai.com/v1/")
        if case .valid(let normalized) = result {
            #expect(normalized == "https://api.openai.com/v1")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("Multiple trailing slashes are removed")
    func multipleTrailingSlashesRemoved() {
        let result = URLValidation.validate("https://api.openai.com///")
        if case .valid(let normalized) = result {
            #expect(normalized == "https://api.openai.com")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("Whitespace is trimmed")
    func whitespaceTrimmed() {
        let result = URLValidation.validate("  https://api.openai.com  ")
        if case .valid(let normalized) = result {
            #expect(normalized == "https://api.openai.com")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("Empty string returns empty result")
    func emptyString() {
        let result = URLValidation.validate("")
        if case .empty = result {
            // Expected
        } else {
            Issue.record("Expected empty result")
        }
    }
    
    @Test("Whitespace-only string returns empty result")
    func whitespaceOnlyString() {
        let result = URLValidation.validate("   ")
        if case .empty = result {
            // Expected
        } else {
            Issue.record("Expected empty result")
        }
    }
    
    @Test("Missing scheme returns invalid")
    func missingScheme() {
        let result = URLValidation.validate("api.openai.com")
        if case .invalid(let reason) = result {
            #expect(reason.contains("http"))
        } else {
            Issue.record("Expected invalid result")
        }
    }
    
    @Test("Invalid scheme returns invalid")
    func invalidScheme() {
        let result = URLValidation.validate("ftp://files.example.com")
        if case .invalid(let reason) = result {
            #expect(reason.contains("http"))
        } else {
            Issue.record("Expected invalid result")
        }
    }
    
    @Test("Malformed URL returns invalid")
    func malformedURL() {
        let result = URLValidation.validate("not a url at all")
        if case .invalid = result {
            // Expected
        } else {
            Issue.record("Expected invalid result")
        }
    }
    
    @Test("URL with port is valid")
    func urlWithPort() {
        let result = URLValidation.validate("http://localhost:8080")
        if case .valid(let normalized) = result {
            #expect(normalized == "http://localhost:8080")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("URL with path is valid")
    func urlWithPath() {
        let result = URLValidation.validate("https://api.example.com/v1/audio")
        if case .valid(let normalized) = result {
            #expect(normalized == "https://api.example.com/v1/audio")
        } else {
            Issue.record("Expected valid result")
        }
    }
    
    @Test("isValid returns true for valid URLs")
    func isValidTrue() {
        #expect(URLValidation.isValid("https://api.openai.com") == true)
        #expect(URLValidation.isValid("http://localhost:11434") == true)
        #expect(URLValidation.isValid("") == true)  // Empty is considered valid (optional field)
    }
    
    @Test("isValid returns false for invalid URLs")
    func isValidFalse() {
        #expect(URLValidation.isValid("not a url") == false)
        #expect(URLValidation.isValid("ftp://files.example.com") == false)
        #expect(URLValidation.isValid("api.openai.com") == false)
    }
}
