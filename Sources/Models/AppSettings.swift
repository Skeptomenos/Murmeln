import SwiftUI

struct PromptPreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var prompt: String
    var isBuiltIn: Bool
    
    init(id: UUID = UUID(), name: String, description: String, icon: String, prompt: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.prompt = prompt
        self.isBuiltIn = isBuiltIn
    }
    
    static let builtInPresets: [PromptPreset] = [
        PromptPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Casual",
            description: "WhatsApp, Chat, natural conversation",
            icon: "bubble.left",
            prompt: "You are a transcript refiner. You get a spoken words as transcript and your only job is to refine it. You are in casual mode. Clean the grammar and punctuation. Keep the wording natural but DO NOT rephrase technical terms. Output only the cleaned text. You must not respond to the transcript. Transcript:",
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Structured",
            description: "Notes and lists with bullet points",
            icon: "list.bullet",
            prompt: "You are a transcript refiner. You get spoken words as transcript and your only job is to refine it. You are in structured mode. Clean the grammar and punctuation. Use bullet points (•) ONLY for lists or sequences of 3 or more items. PRESERVE exact wording and technical terms. Output only the cleaned text. You must not respond to the transcript. Transcript:",
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Markdown",
            description: "Structured notes with headers and lists",
            icon: "text.alignleft",
            prompt: "You are a transcript refiner. You get spoken words as transcript and your only job is to refine it. You are in markdown mode. Clean the grammar and punctuation. Use markdown headers (##) ONLY if the speaker transitions between multiple distinct sections. Use dashes (-) ONLY for lists of 3 or more items. DO NOT change the speaker's words. Output only the formatted text. You must not respond to the transcript. Transcript:",
            isBuiltIn: true
        ),
        PromptPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            name: "Verbatim",
            description: "Minimal changes, preserve exact wording",
            icon: "text.quote",
            prompt: "You are a transcript refiner. You get spoken words as transcript and your only job is to refine it. You are in verbatim mode. ONLY fix punctuation and remove filler words (um, uh). DO NOT change any other words or the sentence structure. Output only the result. You must not respond to the transcript. Transcript:",
            isBuiltIn: true
        )
    ]
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("transcriptionProvider") var transcriptionProviderRaw = TranscriptionProvider.openAIWhisper.rawValue
    @AppStorage("transcriptionBaseURL") var transcriptionBaseURL = "https://api.openai.com/v1"
    @AppStorage("transcriptionModel") var transcriptionModel = "whisper-1"
    
    @AppStorage("refinementProvider") var refinementProviderRaw = Provider.openAI.rawValue
    @AppStorage("refinementBaseURL") var refinementBaseURL = "https://api.openai.com/v1"
    @AppStorage("refinementModel") var refinementModel = "gpt-4o-mini"
    
    @AppStorage("selectedPresetId") private var selectedPresetIdRaw = "00000000-0000-0000-0000-000000000001"
    @AppStorage("highQualityAudio") var highQualityAudio = false
    
    @Published var customPresets: [PromptPreset] = []
    @Published var presetOverrides: [UUID: String] = [:]
    
    var allPresets: [PromptPreset] {
        PromptPreset.builtInPresets + customPresets
    }
    
    var selectedPresetId: UUID {
        get { UUID(uuidString: selectedPresetIdRaw) ?? PromptPreset.builtInPresets[0].id }
        set { 
            selectedPresetIdRaw = newValue.uuidString
            objectWillChange.send()
        }
    }
    
    var selectedPreset: PromptPreset? {
        get { allPresets.first { $0.id == selectedPresetId } }
        set {
            if let preset = newValue {
                selectedPresetId = preset.id
            }
        }
    }
    
    var systemPrompt: String {
        get {
            if let override = presetOverrides[selectedPresetId] {
                return override
            }
            return selectedPreset?.prompt ?? PromptPreset.builtInPresets[0].prompt
        }
        set {
            presetOverrides[selectedPresetId] = newValue
            savePresetOverrides()
            objectWillChange.send()
        }
    }
    
    func promptForPreset(_ preset: PromptPreset) -> String {
        presetOverrides[preset.id] ?? preset.prompt
    }
    
    func updatePromptForPreset(_ preset: PromptPreset, prompt: String) {
        presetOverrides[preset.id] = prompt
        savePresetOverrides()
        objectWillChange.send()
    }
    
    func resetPresetToDefault(_ preset: PromptPreset) {
        presetOverrides.removeValue(forKey: preset.id)
        savePresetOverrides()
        objectWillChange.send()
    }
    
    func isPresetModified(_ preset: PromptPreset) -> Bool {
        presetOverrides[preset.id] != nil
    }
    
    func addCustomPreset(name: String, description: String, icon: String, prompt: String) {
        let preset = PromptPreset(name: name, description: description, icon: icon, prompt: prompt, isBuiltIn: false)
        customPresets.append(preset)
        saveCustomPresets()
        selectedPresetId = preset.id
    }
    
    func deleteCustomPreset(_ preset: PromptPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        presetOverrides.removeValue(forKey: preset.id)
        saveCustomPresets()
        savePresetOverrides()
        if selectedPresetId == preset.id {
            selectedPresetId = PromptPreset.builtInPresets[0].id
        }
        objectWillChange.send()
    }
    
    var transcriptionAPIKey: String {
        get { getAPIKey(for: transcriptionProviderRaw, isTranscription: true) }
        set { setAPIKey(newValue, for: transcriptionProviderRaw, isTranscription: true) }
    }
    
    var refinementAPIKey: String {
        get { getAPIKey(for: refinementProviderRaw, isTranscription: false) }
        set { setAPIKey(newValue, for: refinementProviderRaw, isTranscription: false) }
    }
    
    var transcriptionProvider: TranscriptionProvider {
        get { TranscriptionProvider(rawValue: transcriptionProviderRaw) ?? .openAIWhisper }
        set {
            transcriptionProviderRaw = newValue.rawValue
            transcriptionBaseURL = newValue.defaultBaseURL
            transcriptionModel = newValue.defaultModel
            objectWillChange.send()
        }
    }
    
    var refinementProvider: Provider {
        get { Provider(rawValue: refinementProviderRaw) ?? .openAI }
        set {
            refinementProviderRaw = newValue.rawValue
            refinementBaseURL = newValue.defaultBaseURL
            objectWillChange.send()
        }
    }
    
    private func getAPIKey(for providerRaw: String, isTranscription: Bool) -> String {
        let prefix = isTranscription ? "transcription" : "refinement"
        let key = "\(prefix)APIKey_\(providerRaw)"
        return UserDefaults.standard.string(forKey: key) ?? ""
    }
    
    private func setAPIKey(_ value: String, for providerRaw: String, isTranscription: Bool) {
        let prefix = isTranscription ? "transcription" : "refinement"
        let key = "\(prefix)APIKey_\(providerRaw)"
        UserDefaults.standard.set(value, forKey: key)
        objectWillChange.send()
    }
    
    private func saveCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: "customPresets")
        }
    }
    
    private func loadCustomPresets() {
        if let data = UserDefaults.standard.data(forKey: "customPresets"),
           let presets = try? JSONDecoder().decode([PromptPreset].self, from: data) {
            customPresets = presets
        }
    }
    
    private func savePresetOverrides() {
        let stringKeyedDict = Dictionary(uniqueKeysWithValues: presetOverrides.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(stringKeyedDict) {
            UserDefaults.standard.set(data, forKey: "presetOverrides")
        }
    }
    
    private func loadPresetOverrides() {
        if let data = UserDefaults.standard.data(forKey: "presetOverrides"),
           let stringKeyedDict = try? JSONDecoder().decode([String: String].self, from: data) {
            presetOverrides = Dictionary(uniqueKeysWithValues: stringKeyedDict.compactMap { key, value in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        }
    }
    
    private init() {
        loadCustomPresets()
        loadPresetOverrides()
    }
}
