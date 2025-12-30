import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noResponse
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noResponse: return "No response from server"
        case .apiError(let msg): return msg
        }
    }
}

final class NetworkService: Sendable {
    @MainActor static let shared = NetworkService()
    
    func transcribeAndRefine(
        audioURL: URL,
        provider: TranscriptionProvider,
        apiKey: String,
        baseURL: String,
        model: String,
        systemPrompt: String
    ) async throws -> String {
        switch provider {
        case .openAIWhisper, .groqWhisper:
            return try await transcribeOpenAICompatible(audioURL: audioURL, apiKey: apiKey, baseURL: baseURL, model: model)
        case .localWhisper:
            return try await transcribeLocalWhisper(audioURL: audioURL, baseURL: baseURL)
        case .gpt4oAudio:
            return try await transcribeAndRefineGPT4oAudio(audioURL: audioURL, apiKey: apiKey, baseURL: baseURL, model: model, systemPrompt: systemPrompt)
        case .geminiAudio:
            return try await transcribeAndRefineGeminiAudio(audioURL: audioURL, apiKey: apiKey, baseURL: baseURL, model: model, systemPrompt: systemPrompt)
        }
    }
    
    private func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        guard let url = URL(string: baseURL + "/audio/transcriptions") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let audioData = try Data(contentsOf: audioURL)
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append(model.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
    
    private func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        guard let url = URL(string: baseURL + "/inference") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let audioData = try Data(contentsOf: audioURL)
        var body = Data()
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
    
    private func transcribeAndRefineGPT4oAudio(audioURL: URL, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw NetworkError.invalidURL
        }
        
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "modalities": ["text"],
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    [
                        "type": "input_audio",
                        "input_audio": [
                            "data": base64Audio,
                            "format": "aac"
                        ]
                    ]
                ]]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
    
    private func transcribeAndRefineGeminiAudio(audioURL: URL, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)") else {
            throw NetworkError.invalidURL
        }
        
        let audioData = try Data(contentsOf: audioURL)
        let base64Audio = audioData.base64EncodedString()
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "role": "user",
                    "parts": [
                        [
                            "inline_data": [
                                "mime_type": "audio/m4a",
                                "data": base64Audio
                            ]
                        ],
                        [
                            "text": systemPrompt
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.3
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(GoogleGenerateResponse.self, from: data)
        return result.candidates?.first?.content.parts.first?.text ?? ""
    }
    
    func refine(
        text: String,
        provider: Provider,
        apiKey: String,
        baseURL: String,
        model: String,
        systemPrompt: String
    ) async throws -> String {
        switch provider {
        case .openAI, .groq, .ollama:
            return try await refineOpenAICompatible(text: text, apiKey: apiKey, baseURL: baseURL, model: model, systemPrompt: systemPrompt, requiresAuth: provider.requiresAPIKey)
        case .google:
            return try await refineGoogle(text: text, apiKey: apiKey, baseURL: baseURL, model: model, systemPrompt: systemPrompt)
        }
    }
    
    private func refineOpenAICompatible(text: String, apiKey: String, baseURL: String, model: String, systemPrompt: String, requiresAuth: Bool) async throws -> String {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if requiresAuth {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "temperature": 0.3
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
    
    private func refineGoogle(text: String, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "\(systemPrompt)\n\n\(text)"]]]
            ],
            "generationConfig": [
                "temperature": 0.3
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.apiError(errorMsg)
        }
        
        let result = try JSONDecoder().decode(GoogleGenerateResponse.self, from: data)
        return result.candidates?.first?.content.parts.first?.text ?? ""
    }
}

struct TranscriptionResponse: Codable {
    let text: String
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
    }
    
    struct Message: Codable {
        let content: String
    }
}

struct GoogleGenerateResponse: Codable {
    let candidates: [Candidate]?
    
    struct Candidate: Codable {
        let content: Content
    }
    
    struct Content: Codable {
        let parts: [Part]
    }
    
    struct Part: Codable {
        let text: String
    }
}
