import Foundation

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

actor ModelDiscoveryService {
    static let shared = ModelDiscoveryService()
    
    func fetchModels(provider: Provider, apiKey: String, baseURL: String) async -> [ModelInfo] {
        switch provider {
        case .openAI, .groq, .ollama:
            return await fetchOpenAICompatibleModels(apiKey: apiKey, baseURL: baseURL, provider: provider)
        case .google:
            return await fetchGoogleModels(apiKey: apiKey, baseURL: baseURL)
        }
    }
    
    func fetchTranscriptionModels(provider: TranscriptionProvider, apiKey: String, baseURL: String) async -> [ModelInfo] {
        switch provider {
        case .openAIWhisper:
            return [ModelInfo(id: "whisper-1", name: "Whisper v1")]
        case .groqWhisper:
            return [
                ModelInfo(id: "whisper-large-v3", name: "Whisper Large v3"),
                ModelInfo(id: "whisper-large-v3-turbo", name: "Whisper Large v3 Turbo")
            ]
        case .gpt4oAudio:
            return await fetchGPT4oAudioModels(apiKey: apiKey, baseURL: baseURL)
        case .geminiAudio:
            return await fetchGeminiAudioModels(apiKey: apiKey, baseURL: baseURL)
        case .localWhisper:
            return [ModelInfo(id: "default", name: "Local Whisper")]
        }
    }
    
    private func fetchOpenAICompatibleModels(apiKey: String, baseURL: String, provider: Provider) async -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/models") else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if provider.requiresAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return getDefaultModels(for: provider)
            }
            
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            
            let chatModels = result.data
                .filter { model in
                    let id = model.id.lowercased()
                    return id.contains("gpt") || id.contains("llama") || id.contains("mistral") || 
                           id.contains("phi") || id.contains("gemma") || id.contains("qwen") ||
                           id.contains("claude") || id.contains("deepseek")
                }
                .map { ModelInfo(id: $0.id, name: $0.id) }
                .sorted { $0.name < $1.name }
            
            return chatModels.isEmpty ? getDefaultModels(for: provider) : chatModels
        } catch {
            return getDefaultModels(for: provider)
        }
    }
    
    private func fetchGPT4oAudioModels(apiKey: String, baseURL: String) async -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/models") else {
            return [ModelInfo(id: "gpt-4o-audio-preview", name: "GPT-4o Audio Preview")]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return [ModelInfo(id: "gpt-4o-audio-preview", name: "GPT-4o Audio Preview")]
            }
            
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            
            let audioModels = result.data
                .filter { $0.id.contains("audio") || $0.id.contains("gpt-4o") }
                .map { ModelInfo(id: $0.id, name: $0.id) }
                .sorted { $0.name < $1.name }
            
            return audioModels.isEmpty ? [ModelInfo(id: "gpt-4o-audio-preview", name: "GPT-4o Audio Preview")] : audioModels
        } catch {
            return [ModelInfo(id: "gpt-4o-audio-preview", name: "GPT-4o Audio Preview")]
        }
    }
    
    private func fetchGeminiAudioModels(apiKey: String, baseURL: String) async -> [ModelInfo] {
        guard let url = URL(string: "\(baseURL)/models?key=\(apiKey)") else {
            return [ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash")]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return [ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash")]
            }
            
            let result = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
            
            let audioModels = result.models
                .filter { ($0.supportedGenerationMethods?.contains("generateContent") ?? false) && $0.name.contains("gemini-2") }
                .map { ModelInfo(id: $0.name.replacingOccurrences(of: "models/", with: ""), name: $0.displayName) }
                .sorted { $0.name < $1.name }
            
            return audioModels.isEmpty ? [ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash")] : audioModels
        } catch {
            return [ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash")]
        }
    }
    
    private func fetchGoogleModels(apiKey: String, baseURL: String) async -> [ModelInfo] {
        guard let url = URL(string: "\(baseURL)/models?key=\(apiKey)") else { 
            return getDefaultModels(for: .google) 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return getDefaultModels(for: .google)
            }
            
            let result = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
            
            let chatModels = result.models
                .filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
                .map { ModelInfo(id: $0.name.replacingOccurrences(of: "models/", with: ""), name: $0.displayName) }
                .sorted { $0.name < $1.name }
            
            return chatModels.isEmpty ? getDefaultModels(for: .google) : chatModels
        } catch {
            return getDefaultModels(for: .google)
        }
    }
    
    private func getDefaultModels(for provider: Provider) -> [ModelInfo] {
        switch provider {
        case .openAI:
            return [
                ModelInfo(id: "gpt-4o-mini", name: "GPT-4o Mini"),
                ModelInfo(id: "gpt-4o", name: "GPT-4o"),
                ModelInfo(id: "gpt-4-turbo", name: "GPT-4 Turbo"),
                ModelInfo(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo")
            ]
        case .google:
            return [
                ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash"),
                ModelInfo(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash"),
                ModelInfo(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro")
            ]
        case .groq:
            return [
                ModelInfo(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B"),
                ModelInfo(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B"),
                ModelInfo(id: "mixtral-8x7b-32768", name: "Mixtral 8x7B")
            ]
        case .ollama:
            return [
                ModelInfo(id: "llama3.2", name: "Llama 3.2"),
                ModelInfo(id: "phi3", name: "Phi-3"),
                ModelInfo(id: "mistral", name: "Mistral")
            ]
        }
    }
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
    
    struct OpenAIModel: Codable {
        let id: String
    }
}

struct GoogleModelsResponse: Codable {
    let models: [GoogleModel]
    
    struct GoogleModel: Codable {
        let name: String
        let displayName: String
        let supportedGenerationMethods: [String]?
    }
}
