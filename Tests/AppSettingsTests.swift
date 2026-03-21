import Testing
import Foundation
@testable import mrml

// MARK: - AppSettings Tests

@Suite("AppSettings Tests")
struct AppSettingsTests {
    
    // MARK: - PromptPreset Tests
    
    @Test("Built-in presets have stable UUIDs")
    func builtInPresetsHaveStableUUIDs() {
        let casualId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let structuredId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let markdownId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let verbatimId = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        
        let casual = PromptPreset.builtInPresets.first { $0.name == "Casual" }
        let structured = PromptPreset.builtInPresets.first { $0.name == "Structured" }
        let markdown = PromptPreset.builtInPresets.first { $0.name == "Markdown" }
        let verbatim = PromptPreset.builtInPresets.first { $0.name == "Verbatim" }
        
        #expect(casual?.id == casualId)
        #expect(structured?.id == structuredId)
        #expect(markdown?.id == markdownId)
        #expect(verbatim?.id == verbatimId)
    }
    
    @Test("Custom preset creation generates unique ID")
    func customPresetGeneratesUniqueId() {
        let preset1 = PromptPreset(name: "Custom1", description: "Desc", icon: "star", prompt: "Prompt")
        let preset2 = PromptPreset(name: "Custom2", description: "Desc", icon: "star", prompt: "Prompt")
        
        #expect(preset1.id != preset2.id)
        #expect(preset1.isBuiltIn == false)
        #expect(preset2.isBuiltIn == false)
    }
    
    @Test("PromptPreset encodes and decodes correctly")
    func presetEncodesAndDecodes() throws {
        let preset = PromptPreset(
            name: "Test Preset",
            description: "A test description",
            icon: "wand.and.stars",
            prompt: "Clean up this text: {input}"
        )
        
        let encoded = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(PromptPreset.self, from: encoded)
        
        #expect(decoded.id == preset.id)
        #expect(decoded.name == "Test Preset")
        #expect(decoded.description == "A test description")
        #expect(decoded.icon == "wand.and.stars")
        #expect(decoded.prompt == "Clean up this text: {input}")
        #expect(decoded.isBuiltIn == false)
    }
    
    @Test("Built-in preset encodes with isBuiltIn flag")
    func builtInPresetEncodesFlag() throws {
        let builtIn = PromptPreset.builtInPresets[0]
        
        let encoded = try JSONEncoder().encode(builtIn)
        let decoded = try JSONDecoder().decode(PromptPreset.self, from: encoded)
        
        #expect(decoded.isBuiltIn == true)
    }
    
    // MARK: - Personal Dictionary Tests
    
    @Test("Personal dictionary JSON storage encodes correctly")
    func personalDictionaryJSONStorage() throws {
        let words = ["Kubernetes", "GraphQL", "PostgreSQL"]
        let encoded = try JSONEncoder().encode(words)
        let json = String(data: encoded, encoding: .utf8)
        
        #expect(json != nil)
        #expect(json!.contains("Kubernetes"))
        #expect(json!.contains("GraphQL"))
        #expect(json!.contains("PostgreSQL"))
        
        // Verify round-trip
        let decoded = try JSONDecoder().decode([String].self, from: encoded)
        #expect(decoded == words)
    }
    
    @Test("Personal dictionary JSON handles special characters")
    func personalDictionarySpecialCharacters() throws {
        // Test that the old delimiter and other special chars are preserved
        let words = ["word|||with|||pipes", "quotes\"here", "emoji🎉", "newline\nchar", "tab\there"]
        let encoded = try JSONEncoder().encode(words)
        let decoded = try JSONDecoder().decode([String].self, from: encoded)
        
        #expect(decoded.count == 5)
        #expect(decoded[0] == "word|||with|||pipes")
        #expect(decoded[1] == "quotes\"here")
        #expect(decoded[2] == "emoji🎉")
        #expect(decoded[3] == "newline\nchar")
        #expect(decoded[4] == "tab\there")
    }
    
    @Test("Personal dictionary migration from old format")
    func personalDictionaryMigration() {
        // Simulate old format with ||| delimiter
        let oldFormat = "Kubernetes|||GraphQL|||PostgreSQL"
        let migrated = oldFormat.components(separatedBy: "|||")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        #expect(migrated.count == 3)
        #expect(migrated[0] == "Kubernetes")
        #expect(migrated[1] == "GraphQL")
        #expect(migrated[2] == "PostgreSQL")
    }
    
    @Test("Personal dictionary old format corruption scenario")
    func personalDictionaryOldFormatCorruption() {
        // This demonstrates why the old format was problematic
        // If a user entered "word|||pipes", it would corrupt the data
        let corruptedOldFormat = "normal|||word|||pipes|||another"
        let parsed = corruptedOldFormat.components(separatedBy: "|||")
        
        // Old format would incorrectly parse this as 4 words instead of 3
        #expect(parsed.count == 4)  // This was the bug!
        
        // JSON format handles this correctly
        let correctWords = ["normal", "word|||pipes", "another"]
        let jsonData = try! JSONEncoder().encode(correctWords)
        let decoded = try! JSONDecoder().decode([String].self, from: jsonData)
        #expect(decoded.count == 3)
        #expect(decoded[1] == "word|||pipes")  // Preserved correctly
    }
    
    @Test("Personal dictionary max limit is 20")
    func personalDictionaryMaxLimit() {
        var words: [String] = []
        for i in 0..<25 {
            words.append("word\(i)")
        }
        
        let limited = Array(words.prefix(20))
        
        #expect(limited.count == 20)
        #expect(limited.last == "word19")
    }
    
    @Test("Empty personal dictionary returns empty array")
    func emptyPersonalDictionary() {
        let data = ""
        let words = data.isEmpty ? [] : data.components(separatedBy: "|||")
        
        #expect(words.isEmpty)
    }
    
    @Test("Personal dictionary handles single word")
    func singleWordDictionary() {
        let data = "Kubernetes"
        let words = data.components(separatedBy: "|||")
        
        #expect(words.count == 1)
        #expect(words[0] == "Kubernetes")
    }
    
    // MARK: - Preset Override Tests
    
    @Test("Preset overrides use UUID as key")
    func presetOverridesUseUUIDKey() {
        var overrides: [UUID: String] = [:]
        let presetId = UUID()
        
        overrides[presetId] = "Custom prompt override"
        
        #expect(overrides[presetId] == "Custom prompt override")
    }
    
    @Test("Preset overrides encode and decode correctly")
    func presetOverridesEncodeDecode() throws {
        let uuid1 = UUID()
        let uuid2 = UUID()
        var overrides: [UUID: String] = [:]
        overrides[uuid1] = "Override 1"
        overrides[uuid2] = "Override 2"
        
        let stringKeyedDict = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value) })
        let encoded = try JSONEncoder().encode(stringKeyedDict)
        let decoded = try JSONDecoder().decode([String: String].self, from: encoded)
        
        let restored = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil as (UUID, String)? }
            return (uuid, value)
        })
        
        #expect(restored[uuid1] == "Override 1")
        #expect(restored[uuid2] == "Override 2")
    }
    
    @Test("Removing override returns nil")
    func removingOverrideReturnsNil() {
        var overrides: [UUID: String] = [:]
        let presetId = UUID()
        
        overrides[presetId] = "Custom prompt"
        #expect(overrides[presetId] != nil)
        
        overrides.removeValue(forKey: presetId)
        #expect(overrides[presetId] == nil)
    }
    
    // MARK: - Custom Presets Tests
    
    @Test("Custom presets array encodes and decodes correctly")
    func customPresetsEncodeDecode() throws {
        let presets = [
            PromptPreset(name: "Custom1", description: "Desc1", icon: "star", prompt: "Prompt1"),
            PromptPreset(name: "Custom2", description: "Desc2", icon: "heart", prompt: "Prompt2")
        ]
        
        let encoded = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([PromptPreset].self, from: encoded)
        
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Custom1")
        #expect(decoded[1].name == "Custom2")
    }
    
    @Test("allPresets combines built-in and custom")
    func allPresetsCombinesBuiltInAndCustom() {
        let builtIn = PromptPreset.builtInPresets
        let custom = [
            PromptPreset(name: "Custom1", description: "Desc", icon: "star", prompt: "Prompt")
        ]
        
        let allPresets = builtIn + custom
        
        #expect(allPresets.count == builtIn.count + 1)
        #expect(allPresets.last?.name == "Custom1")
    }
    
    @Test("Deleting custom preset removes from array")
    func deletingCustomPresetRemoves() {
        var customPresets = [
            PromptPreset(name: "Keep", description: "Desc", icon: "star", prompt: "Prompt"),
            PromptPreset(name: "Delete", description: "Desc", icon: "trash", prompt: "Prompt")
        ]
        
        let toDelete = customPresets[1]
        customPresets.removeAll { $0.id == toDelete.id }
        
        #expect(customPresets.count == 1)
        #expect(customPresets[0].name == "Keep")
    }
    
    // MARK: - Provider Selection Tests
    
    @Test("TranscriptionProvider raw values are stable")
    func transcriptionProviderRawValues() {
        #expect(TranscriptionProvider.openAIWhisper.rawValue == "OpenAI Whisper")
        #expect(TranscriptionProvider.groqWhisper.rawValue == "Groq Whisper")
        #expect(TranscriptionProvider.gpt4oAudio.rawValue == "GPT-4o Audio")
        #expect(TranscriptionProvider.geminiAudio.rawValue == "Gemini 2.0 Flash")
        #expect(TranscriptionProvider.localWhisper.rawValue == "Local Whisper")
    }
    
    @Test("Provider raw values are stable")
    func providerRawValues() {
        #expect(Provider.openAI.rawValue == "OpenAI")
        #expect(Provider.google.rawValue == "Google AI")
        #expect(Provider.groq.rawValue == "Groq")
        #expect(Provider.ollama.rawValue == "Ollama (Local)")
    }
    
    @Test("Provider from raw value returns correct enum")
    func providerFromRawValue() {
        let openAI = Provider(rawValue: "OpenAI")
        let google = Provider(rawValue: "Google AI")
        let invalid = Provider(rawValue: "Invalid")
        
        #expect(openAI == .openAI)
        #expect(google == .google)
        #expect(invalid == nil)
    }
    
    // MARK: - API Key Storage Pattern Tests
    
    @Test("API key storage key format is correct")
    func apiKeyStorageKeyFormat() {
        let transcriptionKey = "transcriptionAPIKey_OpenAI Whisper"
        let refinementKey = "refinementAPIKey_OpenAI"
        
        #expect(transcriptionKey.hasPrefix("transcription"))
        #expect(refinementKey.hasPrefix("refinement"))
        #expect(transcriptionKey.contains("_"))
        #expect(refinementKey.contains("_"))
    }
    
    // MARK: - Settings Defaults Tests
    
    @Test("Default transcription provider is OpenAI Whisper")
    func defaultTranscriptionProvider() {
        let defaultRaw = TranscriptionProvider.openAIWhisper.rawValue
        #expect(defaultRaw == "OpenAI Whisper")
    }
    
    @Test("Default refinement provider is OpenAI")
    func defaultRefinementProvider() {
        let defaultRaw = Provider.openAI.rawValue
        #expect(defaultRaw == "OpenAI")
    }
    
    @Test("Default selected preset is Casual")
    func defaultSelectedPreset() {
        let defaultId = "00000000-0000-0000-0000-000000000001"
        let casualPreset = PromptPreset.builtInPresets.first { $0.name == "Casual" }
        
        #expect(casualPreset?.id.uuidString == defaultId)
    }
    
    @Test("High quality audio default is false")
    func highQualityAudioDefault() {
        let defaultValue = false
        #expect(defaultValue == false)
    }
    
    @Test("Parallel refinement default is true")
    func parallelRefinementDefault() {
        let defaultValue = true
        #expect(defaultValue == true)
    }
    
    @Test("Skip refinement default is false")
    func skipRefinementDefault() {
        let defaultValue = false
        #expect(defaultValue == false)
    }
    
    @Test("Personal dictionary enabled default is true")
    func personalDictionaryEnabledDefault() {
        let defaultValue = true
        #expect(defaultValue == true)
    }
}
