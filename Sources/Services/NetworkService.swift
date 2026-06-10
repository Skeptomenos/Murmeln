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
    /// Singleton instance. No @MainActor needed since the class is Sendable
    /// and all methods are thread-safe (stateless, uses only immutable URLSession).
    static let shared = NetworkService()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    private struct MultipartUploadPreparation: Sendable {
        let request: URLRequest
        let bodyFileURL: URL
    }
    
    // MARK: - Streaming Multipart Upload Helper
    
    /// Creates a temporary file containing multipart form data for streaming upload.
    /// This avoids loading the entire audio file into memory.
    /// - Parameters:
    ///   - audioURL: URL of the audio file to upload
    ///   - boundary: Multipart boundary string
    ///   - additionalFields: Additional form fields (e.g., ["model": "whisper-1"])
    /// - Returns: URL of the temporary multipart body file
    private func createMultipartBodyFile(
        audioURL: URL,
        boundary: String,
        additionalFields: [String: String] = [:]
    ) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("multipart_\(UUID().uuidString).tmp")
        
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: tempURL)
        
        defer {
            try? fileHandle.close()
        }
        
        // Write audio file part header
        var header = "--\(boundary)\r\n"
        header += "Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n"
        header += "Content-Type: audio/wav\r\n\r\n"
        fileHandle.write(header.data(using: .utf8)!)
        
        // Stream audio file content in chunks (64KB chunks)
        let audioHandle = try FileHandle(forReadingFrom: audioURL)
        defer {
            try? audioHandle.close()
        }
        
        let chunkSize = 64 * 1024  // 64KB chunks
        while true {
            let chunk = audioHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            fileHandle.write(chunk)
        }
        
        // Write audio file part footer
        fileHandle.write("\r\n".data(using: .utf8)!)
        
        // Write additional form fields
        for (name, value) in additionalFields {
            var fieldData = "--\(boundary)\r\n"
            fieldData += "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
            fieldData += value
            fieldData += "\r\n"
            fileHandle.write(fieldData.data(using: .utf8)!)
        }
        
        // Write closing boundary
        fileHandle.write("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return tempURL
    }
    
    /// Cleans up temporary multipart body file after upload
    private func cleanupMultipartBodyFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
    
    private func sanitizeErrorMessage(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "Unknown error"
        }
        
        // OpenAI/Groq/Google: {"error": {"message": "..."}}
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        
        if let message = json["message"] as? String {
            return message
        }
        
        if let error = json["error"] as? String {
            return error
        }
        
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
    
    /// Transcribes audio using OpenAI-compatible API with streaming file upload.
    /// Uses file-based multipart body to avoid loading entire audio into memory.
    func transcribeOpenAICompatible(audioURL: URL, apiKey: String, baseURL: String, model: String) async throws -> String {
        let preparation = try await Task.detached(priority: .userInitiated) { [self] in
            try prepareMultipartUpload(
                endpoint: baseURL + "/audio/transcriptions",
                authorizationHeader: "Bearer \(apiKey)",
                audioURL: audioURL,
                additionalFields: ["model": model]
            )
        }.value

        defer {
            cleanupMultipartBodyFile(preparation.bodyFileURL)
        }

        // Use file-based upload to stream the body without loading into memory
        let (data, response) = try await session.upload(for: preparation.request, fromFile: preparation.bodyFileURL)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
        }
        
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
    
    /// Transcribes audio using local Whisper server with streaming file upload.
    /// Uses file-based multipart body to avoid loading entire audio into memory.
    func transcribeLocalWhisper(audioURL: URL, baseURL: String) async throws -> String {
        let preparation = try await Task.detached(priority: .userInitiated) { [self] in
            try prepareMultipartUpload(
                endpoint: baseURL + "/inference",
                authorizationHeader: nil,
                audioURL: audioURL,
                additionalFields: [:]
            )
        }.value

        defer {
            cleanupMultipartBodyFile(preparation.bodyFileURL)
        }

        // Use file-based upload to stream the body without loading into memory
        let (data, response) = try await session.upload(for: preparation.request, fromFile: preparation.bodyFileURL)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
        }
        
        let result = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return result.text
    }
    
    private func transcribeAndRefineGPT4oAudio(audioURL: URL, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw NetworkError.invalidURL
        }

        let bodyData = try await Task.detached(priority: .userInitiated) {
            let audioData = try Data(contentsOf: audioURL)
            let base64Audio = audioData.base64EncodedString()

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
                                "format": "wav"
                            ]
                        ]
                    ]]
                ],
                "temperature": 0.0
            ]

            return try JSONSerialization.data(withJSONObject: body)
        }.value
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = bodyData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }
    
    private func transcribeAndRefineGeminiAudio(audioURL: URL, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent") else {
            throw NetworkError.invalidURL
        }

        let bodyData = try await Task.detached(priority: .userInitiated) {
            let audioData = try Data(contentsOf: audioURL)
            let base64Audio = audioData.base64EncodedString()

            let body: [String: Any] = [
                "systemInstruction": [
                    "parts": [
                        ["text": systemPrompt]
                    ]
                ],
                "contents": [
                    [
                        "role": "user",
                        "parts": [
                            [
                                "inline_data": [
                                    "mime_type": "audio/wav",
                                    "data": base64Audio
                                ]
                            ],
                            [
                                "text": "Transcribe and refine this audio."
                            ]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.0
                ]
            ]

            return try JSONSerialization.data(withJSONObject: body)
        }.value
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        request.httpBody = bodyData
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
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
            "temperature": 0.0
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
        }
        
        let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return result.choices.first?.message.content ?? ""
    }

    private func prepareMultipartUpload(
        endpoint: String,
        authorizationHeader: String?,
        audioURL: URL,
        additionalFields: [String: String]
    ) throws -> MultipartUploadPreparation {
        guard let url = URL(string: endpoint) else {
            throw NetworkError.invalidURL
        }

        let boundary = UUID().uuidString
        let bodyFileURL = try createMultipartBodyFile(
            audioURL: audioURL,
            boundary: boundary,
            additionalFields: additionalFields
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        return MultipartUploadPreparation(request: request, bodyFileURL: bodyFileURL)
    }
    
    private func refineGoogle(text: String, apiKey: String, baseURL: String, model: String, systemPrompt: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/models/\(model):generateContent") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": "\(systemPrompt)\n\n\(text)"]]]
            ],
            "generationConfig": [
                "temperature": 0.0
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.apiError(sanitizeErrorMessage(from: data))
        }
        
        let result = try JSONDecoder().decode(GoogleGenerateResponse.self, from: data)
        return result.candidates?.first?.content.parts.first?.text ?? ""
    }

    func transcribeCloudAudioInput(
        audioURL: URL,
        provider: TranscriptionProvider,
        apiKey: String,
        baseURL: String,
        model: String,
        systemPrompt: String
    ) async throws -> String {
        let defaultVerbatim = "You are a professional transcription service. Transcribe the audio exactly as heard, including all filler words, repetitions, and pauses. Do not summarize, refine, or correct grammar. Output ONLY the transcribed text, nothing else."
        let actualPrompt = systemPrompt.isEmpty ? defaultVerbatim : systemPrompt

        switch provider {
        case .gpt4oAudio:
            return try await transcribeAndRefineGPT4oAudio(
                audioURL: audioURL,
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                systemPrompt: actualPrompt
            )
        case .geminiAudio:
            return try await transcribeAndRefineGeminiAudio(
                audioURL: audioURL,
                apiKey: apiKey,
                baseURL: baseURL,
                model: model,
                systemPrompt: actualPrompt
            )
        default:
            throw NetworkError.apiError("Cloud audio-input transcription is not supported for \(provider.rawValue)")
        }
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
