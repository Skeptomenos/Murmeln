import SwiftUI

enum PromptPreset: String, CaseIterable, Identifiable {
    case casual = "Casual"
    case structured = "Structured"
    case llmPrompt = "LLM Prompt"
    case verbatim = "Verbatim"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var description: String {
        switch self {
        case .casual: return "WhatsApp, Chat, natural conversation"
        case .structured: return "Notes, lists, documentation"
        case .llmPrompt: return "AI prompts with markdown formatting"
        case .verbatim: return "Minimal changes, preserve exact wording"
        case .custom: return "Your own prompt"
        }
    }
    
    var icon: String {
        switch self {
        case .casual: return "bubble.left"
        case .structured: return "list.bullet"
        case .llmPrompt: return "cpu"
        case .verbatim: return "text.quote"
        case .custom: return "pencil"
        }
    }
    
    var prompt: String {
        switch self {
        case .casual:
            return "Fix grammar and filler words. Keep it conversational and natural. Output only the cleaned text."
        case .structured:
            return "Clean up this dictation. Fix grammar and punctuation. Format lists as bullet points or numbered lists. Keep the speaker's meaning. Output only the result."
        case .llmPrompt:
            return "Structure this as a clear AI prompt. Use markdown (headers, lists, code blocks) where appropriate. Be precise and unambiguous. Output only the result."
        case .verbatim:
            return "Remove filler words (um, uh, like, you know). Fix punctuation only. Do not change wording. Output only the result."
        case .custom:
            return ""
        }
    }
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
    
    @AppStorage("promptPreset") var promptPresetRaw = PromptPreset.casual.rawValue
    @AppStorage("customPrompt") var customPrompt = "You are a transcription refiner. Clean up the following speech-to-text input. Remove filler words, fix grammar, and structure it as clear, professional text or a concise command. Output ONLY the refined text."
    
    @AppStorage("highQualityAudio") var highQualityAudio = false
    
    var promptPreset: PromptPreset {
        get { PromptPreset(rawValue: promptPresetRaw) ?? .casual }
        set {
            promptPresetRaw = newValue.rawValue
            objectWillChange.send()
        }
    }
    
    var systemPrompt: String {
        get {
            if promptPreset == .custom {
                return customPrompt
            }
            return promptPreset.prompt
        }
        set {
            customPrompt = newValue
            if promptPreset != .custom {
                promptPreset = .custom
            }
            objectWillChange.send()
        }
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
    
    private init() {}
}
