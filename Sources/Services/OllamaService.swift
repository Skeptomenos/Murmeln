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
    
    private var pullTask: Task<Bool, Never>?
    
    /// Returns the normalized Ollama base URL from settings (trimmed, no trailing slash)
    private var baseURL: String {
        AppSettings.shared.ollamaBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    func checkOllamaStatus() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            isOllamaRunning = false
            return
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
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
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            installedModels = response.models.map { $0.name }
        } catch {
            installedModels = []
        }
    }
    
    func pullModel(_ modelName: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/pull") else { return false }
        
        pullTask?.cancel()
        pullTask = nil
        
        isPulling = true
        pullingModelName = modelName
        pullProgress = "Starting download..."
        pullError = nil
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": modelName])
        
        let workTask = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            
            do {
                let (bytes, _) = try await URLSession.shared.bytes(for: request)
                
                for try await line in bytes.lines {
                    if Task.isCancelled {
                        self.isPulling = false
                        self.pullingModelName = nil
                        self.pullProgress = ""
                        return false
                    }
                    
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let status = json["status"] as? String {
                            if let completed = json["completed"] as? Int64,
                               let total = json["total"] as? Int64, total > 0 {
                                let percent = Int((Double(completed) / Double(total)) * 100)
                                self.pullProgress = "\(status): \(percent)%"
                            } else {
                                self.pullProgress = status
                            }
                        }
                    }
                }
                
                self.isPulling = false
                self.pullingModelName = nil
                self.pullProgress = ""
                await self.refreshInstalledModels()
                return true
            } catch {
                if Task.isCancelled {
                    self.isPulling = false
                    self.pullingModelName = nil
                    self.pullProgress = ""
                    return false
                }
                self.isPulling = false
                self.pullingModelName = nil
                self.pullProgress = ""
                self.pullError = "Failed to pull model: \(error.localizedDescription)"
                return false
            }
        }
        
        pullTask = workTask
        return await workTask.value
    }
    
    func updateModel(_ modelName: String) async -> Bool {
        return await pullModel(modelName)
    }
    
    func isModelInstalled(_ modelName: String) -> Bool {
        installedModels.contains { $0.hasPrefix(modelName.split(separator: ":").first.map(String.init) ?? modelName) }
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
        
        _ = try? await URLSession.shared.data(for: request)
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
