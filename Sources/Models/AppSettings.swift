import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    @AppStorage("transcriptionProvider") var transcriptionProviderRaw = TranscriptionProvider.openAIWhisper.rawValue
    @AppStorage("transcriptionAPIKey") var transcriptionAPIKey = ""
    @AppStorage("transcriptionBaseURL") var transcriptionBaseURL = "https://api.openai.com/v1"
    @AppStorage("transcriptionModel") var transcriptionModel = "whisper-1"
    
    @AppStorage("refinementProvider") var refinementProviderRaw = Provider.openAI.rawValue
    @AppStorage("refinementAPIKey") var refinementAPIKey = ""
    @AppStorage("refinementBaseURL") var refinementBaseURL = "https://api.openai.com/v1"
    @AppStorage("refinementModel") var refinementModel = "gpt-4o-mini"
    
    @AppStorage("systemPrompt") var systemPrompt = "You are a transcription refiner. Clean up the following speech-to-text input. Remove filler words, fix grammar, and structure it as clear, professional text or a concise command. Output ONLY the refined text."
    
    @AppStorage("highQualityAudio") var highQualityAudio = false
    
    var transcriptionProvider: TranscriptionProvider {
        get { TranscriptionProvider(rawValue: transcriptionProviderRaw) ?? .openAIWhisper }
        set {
            transcriptionProviderRaw = newValue.rawValue
            transcriptionBaseURL = newValue.defaultBaseURL
            transcriptionModel = newValue.defaultModel
        }
    }
    
    var refinementProvider: Provider {
        get { Provider(rawValue: refinementProviderRaw) ?? .openAI }
        set {
            refinementProviderRaw = newValue.rawValue
            refinementBaseURL = newValue.defaultBaseURL
        }
    }
    
    private init() {}
}
