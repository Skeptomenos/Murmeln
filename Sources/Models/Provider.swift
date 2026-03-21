import Foundation

enum Provider: String, CaseIterable, Codable {
    case openAI = "OpenAI"
    case google = "Google AI"
    case groq = "Groq"
    case ollama = "Ollama (Local)"
    
    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .google: return "https://generativelanguage.googleapis.com/v1beta"
        case .groq: return "https://api.groq.com/openai/v1"
        case .ollama: return "http://localhost:11434/v1"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .ollama: return false
        default: return true
        }
    }
    
    var supportsWhisper: Bool {
        switch self {
        case .openAI, .groq: return true
        case .google, .ollama: return false
        }
    }
    
    var modelsEndpoint: String {
        switch self {
        case .openAI, .groq, .ollama: return "/models"
        case .google: return "/models"
        }
    }
}

enum TranscriptionProvider: String, CaseIterable, Codable {
    case openAIWhisper = "OpenAI Whisper"
    case groqWhisper = "Groq Whisper"
    case gpt4oAudio = "GPT-4o Audio"
    case geminiAudio = "Gemini 2.0 Flash"
    case localWhisper = "Local Whisper"
    
    var defaultBaseURL: String {
        switch self {
        case .openAIWhisper: return "https://api.openai.com/v1"
        case .groqWhisper: return "https://api.groq.com/openai/v1"
        case .gpt4oAudio: return "https://api.openai.com/v1"
        case .geminiAudio: return "https://generativelanguage.googleapis.com/v1beta"
        case .localWhisper: return "http://localhost:8080"
        }
    }
    
    var requiresAPIKey: Bool {
        switch self {
        case .localWhisper: return false
        default: return true
        }
    }
    
    var isNativeAudioModel: Bool {
        switch self {
        case .gpt4oAudio, .geminiAudio: return true
        default: return false
        }
    }
    
    var supportsRefinementInOneCall: Bool {
        switch self {
        case .gpt4oAudio, .geminiAudio: return true
        default: return false
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openAIWhisper: return "whisper-1"
        case .groqWhisper: return "whisper-large-v3-turbo"
        case .gpt4oAudio: return "gpt-4o-audio-preview"
        case .geminiAudio: return "gemini-2.0-flash-exp"
        case .localWhisper: return "default"
        }
    }
}
