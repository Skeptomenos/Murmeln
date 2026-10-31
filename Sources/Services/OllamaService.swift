import Foundation

@MainActor
final class OllamaService: ObservableObject {
    static let shared = OllamaService()
    
    @Published var isOllamaRunning = false
    @Published var isPulling = false
    @Published var pullProgress: String = ""
    @Published var pullError: String?
    @Published var installedModels: [String] = []
    @Published var pullingModelName: String?
    
    static let recommendedModels = [
        "gemma2:2b",
        "phi3:mini",
        "qwen2.5:3b"
    ]
    
    private let session: URLSession
    private let baseURLProvider: @MainActor () -> String
    private var pullID: UUID?

    init(session: URLSession = .shared,
         baseURLProvider: @escaping @MainActor () -> String = { AppSettings.shared.ollamaBaseURL }) {
        self.session = session
        self.baseURLProvider = baseURLProvider
    }

    private var pullTask: Task<Bool, Never>?
    
    /// Returns the normalized Ollama base URL from settings (trimmed, no trailing slash)
    private var baseURL: String {
        baseURLProvider()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    func checkOllamaStatus() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            isOllamaRunning = false
            return
        }
        
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isOllamaRunning = true
                await refreshInstalledModels()
            } else {
                isOllamaRunning = false
            }
        } catch {
            isOllamaRunning = false
        }
    }
    
    func refreshInstalledModels() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        
        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            installedModels = response.models.map { $0.name }
        } catch {
            installedModels = []
        }
    }
    
    func pullModel(_ modelName: String) async -> Bool {
        pullTask?.cancel()
        let attempt = UUID()
        pullID = attempt
        isPulling = true
        pullingModelName = modelName
        pullProgress = "Starting download..."
        pullError = nil
        let requestedBaseURL = baseURL

        let workTask = Task { @MainActor [self] () -> Bool in
            defer {
                if pullID == attempt {
                    isPulling = false
                    pullingModelName = nil
                    pullProgress = ""
                    pullTask = nil
                }
            }
            do {
                try Task.checkCancellation()
                guard let url = URL(string: "\(requestedBaseURL)/api/pull") else {
                    throw PullFailure.invalidResponse
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["name": modelName])
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw PullFailure.invalidResponse }
                guard (200...299).contains(http.statusCode) else { throw PullFailure.http(http.statusCode) }
                var succeeded = false
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard pullID == attempt, baseURL == requestedBaseURL else { throw CancellationError() }
                    if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let record = try JSONDecoder().decode(PullRecord.self, from: Data(line.utf8))
                    if let error = record.error { throw PullFailure.server(error) }
                    guard let status = record.status else { throw PullFailure.invalidResponse }
                    succeeded = status == "success"
                    if let completed = record.completed, let total = record.total, total > 0 {
                        let percent = Int(min(max(Double(completed) / Double(total), 0), 1) * 100)
                        pullProgress = "\(status): \(percent)%"
                    } else {
                        pullProgress = status
                    }
                }
                try Task.checkCancellation()
                guard pullID == attempt, baseURL == requestedBaseURL else { throw CancellationError() }
                guard succeeded else { throw PullFailure.incomplete }
                await refreshInstalledModels()
                try Task.checkCancellation()
                return pullID == attempt && baseURL == requestedBaseURL
            } catch {
                if pullID == attempt && !Task.isCancelled && !(error is CancellationError) {
                    pullError = "Failed to pull model: \(error.localizedDescription)"
                }
                return false
            }
        }
        pullTask = workTask
        return await withTaskCancellationHandler {
            await workTask.value
        } onCancel: {
            workTask.cancel()
        }
    }

    private struct PullRecord: Decodable {
        let status: String?
        let error: String?
        let completed: Int64?
        let total: Int64?
    }

    private enum PullFailure: LocalizedError {
        case http(Int), server(String), invalidResponse, incomplete
        var errorDescription: String? {
            switch self {
            case .http(let code): "HTTP \(code)"
            case .server(let message): message
            case .invalidResponse: "Invalid download response."
            case .incomplete: "Download ended before success was confirmed."
            }
        }
    }

    func updateModel(_ modelName: String) async -> Bool {
        return await pullModel(modelName)
    }
    
    func isModelInstalled(_ modelName: String) -> Bool {
        func normalized(_ name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            // A registry's port is not a model tag; inspect only the last path component.
            return trimmed.split(separator: "/").last?.contains(":") == true ? trimmed : trimmed + ":latest"
        }
        let requested = normalized(modelName)
        return !requested.isEmpty && installedModels.contains { normalized($0) == requested }
    }
    
    func keepModelLoaded(_ modelName: String) async {
        guard let url = URL(string: "\(baseURL)/api/generate") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": modelName,
            "prompt": "",
            "keep_alive": -1
        ])
        
        _ = try? await session.data(for: request)
    }
}

struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
    let size: Int64?
    let digest: String?
}
