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
        let whisperKitFallbackModel = await MainActor.run { AppSettings.shared.whisperKitModel }

        switch provider {
        case .whisperKit:
            let service = await MainActor.run { WhisperKitService.shared }
            await MainActor.run {
                service.scanDownloadedModels()
            }
            let downloaded = await MainActor.run { service.downloadedModels }
            if downloaded.isEmpty {
                return [ModelInfo(id: whisperKitFallbackModel, name: formatWhisperKitModelName(whisperKitFallbackModel))]
            }
            return downloaded.map { variant in
                ModelInfo(id: variant, name: formatWhisperKitModelName(variant))
            }
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
        case .cohereMLX:
            // Cohere MLX has a fixed model — no discovery needed
            return [ModelInfo(id: CohereMLXService.modelID, name: "Cohere Transcribe 03-2026")]
        }
    }

    private func formatWhisperKitModelName(_ variant: String) -> String {
        variant
            .replacingOccurrences(of: "openai_whisper-", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
    
    private func fetchOpenAICompatibleModels(apiKey: String, baseURL: String, provider: Provider) async -> [ModelInfo] {
        let recommendedModels = getRefinementModels(for: provider)
        
        guard let url = URL(string: baseURL + "/models") else { 
            return recommendedModels 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if provider.requiresAPIKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return recommendedModels
            }
            
            let result = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            
            // For Ollama: show ALL installed models (no filtering)
            if provider == .ollama {
                let allModels = result.data
                    .map { ModelInfo(id: $0.id, name: formatRefinementModelName($0.id)) }
                    .sorted { $0.name < $1.name }
                return allModels.isEmpty ? recommendedModels : allModels
            }
            
            // For cloud providers: filter to recommended models only
            let refinementModelIds: Set<String>
            switch provider {
            case .openAI:
                refinementModelIds = ["gpt-4o-mini", "gpt-4o"]
            case .groq:
                refinementModelIds = ["llama-3.1-8b-instant", "gemma2-9b-it", "llama-3.3-70b-versatile"]
            default:
                refinementModelIds = []
            }
            
            let filteredModels = result.data
                .filter { refinementModelIds.contains($0.id.lowercased()) }
                .map { ModelInfo(id: $0.id, name: formatRefinementModelName($0.id)) }
                .sorted { $0.name < $1.name }
            
            return filteredModels.isEmpty ? recommendedModels : filteredModels
        } catch {
            return recommendedModels
        }
    }
    
    private func formatRefinementModelName(_ id: String) -> String {
        let lowerId = id.lowercased()
        if lowerId.contains("gemma2") && lowerId.contains("2b") {
            return "Gemma 2 2B (Fast, Recommended)"
        } else if lowerId.contains("gemma2") && lowerId.contains("9b") {
            return "Gemma 2 9B (Recommended)"
        } else if lowerId.contains("gemma2") {
            return "Gemma 2"
        } else if lowerId.contains("phi3") && lowerId.contains("mini") {
            return "Phi-3 Mini (3.8B)"
        } else if lowerId.contains("phi3") {
            return "Phi-3"
        } else if lowerId.contains("qwen2.5") && lowerId.contains("3b") {
            return "Qwen 2.5 3B"
        } else if lowerId.contains("qwen2.5") {
            return "Qwen 2.5"
        } else if lowerId.contains("llama3.2") && lowerId.contains("3b") {
            return "Llama 3.2 3B"
        } else if lowerId.contains("llama3.2") {
            return "Llama 3.2"
        } else if lowerId.contains("llama-3.1-8b") {
            return "Llama 3.1 8B (Fast)"
        } else if lowerId.contains("llama-3.3-70b") {
            return "Llama 3.3 70B"
        } else if lowerId.contains("gpt-4o-mini") {
            return "GPT-4o Mini (Recommended)"
        } else if lowerId.contains("gpt-4o") {
            return "GPT-4o"
        }
        return id
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
        guard let url = URL(string: "\(baseURL)/models") else {
            return [ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash")]
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
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
        let recommendedModels = getRefinementModels(for: .google)
        
        guard let url = URL(string: "\(baseURL)/models") else { 
            return recommendedModels 
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                return recommendedModels
            }
            
            let result = try JSONDecoder().decode(GoogleModelsResponse.self, from: data)
            
            let refinementModelIds: Set<String> = ["gemini-2.0-flash-exp", "gemini-2.0-flash", "gemini-1.5-flash"]
            
            let filteredModels = result.models
                .filter { model in
                    let id = model.name.replacingOccurrences(of: "models/", with: "")
                    return refinementModelIds.contains(id) && (model.supportedGenerationMethods?.contains("generateContent") ?? false)
                }
                .map { model in
                    let id = model.name.replacingOccurrences(of: "models/", with: "")
                    let name = id.contains("2.0-flash") ? "Gemini 2.0 Flash (Recommended)" : model.displayName
                    return ModelInfo(id: id, name: name)
                }
                .sorted { $0.name < $1.name }
            
            return filteredModels.isEmpty ? recommendedModels : filteredModels
        } catch {
            return recommendedModels
        }
    }
    
    private func getRefinementModels(for provider: Provider) -> [ModelInfo] {
        switch provider {
        case .openAI:
            return [
                ModelInfo(id: "gpt-4o-mini", name: "GPT-4o Mini (Recommended)")
            ]
        case .google:
            return [
                ModelInfo(id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash (Recommended)"),
                ModelInfo(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash")
            ]
        case .groq:
            return [
                ModelInfo(id: "llama-3.1-8b-instant", name: "Llama 3.1 8B (Fast)"),
                ModelInfo(id: "gemma2-9b-it", name: "Gemma 2 9B (Recommended)")
            ]
        case .ollama:
            return [
                ModelInfo(id: "gemma2:2b", name: "Gemma 2 2B (Recommended)"),
                ModelInfo(id: "phi3:mini", name: "Phi-3 Mini"),
                ModelInfo(id: "qwen2.5:3b", name: "Qwen 2.5 3B"),
                ModelInfo(id: "llama3.2:3b", name: "Llama 3.2 3B")
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
