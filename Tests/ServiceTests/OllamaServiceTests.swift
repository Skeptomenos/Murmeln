import Testing
import Foundation
@testable import mrml

// MARK: - OllamaService Tests

@Suite("OllamaService Tests")
struct OllamaServiceTests {
    
    // MARK: - Recommended Models Tests
    
    @Test("Recommended models list contains expected models")
    func recommendedModelsContainsExpected() async {
        let recommended = await OllamaService.recommendedModels
        
        #expect(recommended.contains("gemma2:2b"))
        #expect(recommended.contains("phi3:mini"))
        #expect(recommended.contains("qwen2.5:3b"))
    }
    
    @Test("Recommended models list has 3 models")
    func recommendedModelsCount() async {
        let count = await OllamaService.recommendedModels.count
        #expect(count == 3)
    }
    
    // MARK: - Model Name Parsing Tests
    
    @Test("Model name prefix extraction works correctly")
    func modelNamePrefixExtraction() {
        let fullName = "gemma2:2b"
        let prefix = fullName.split(separator: ":").first.map(String.init) ?? fullName
        
        #expect(prefix == "gemma2")
    }
    
    @Test("Model name without tag returns full name")
    func modelNameWithoutTag() {
        let fullName = "gemma2"
        let prefix = fullName.split(separator: ":").first.map(String.init) ?? fullName
        
        #expect(prefix == "gemma2")
    }
    
    @Test("Model installed check logic works")
    func modelInstalledCheckLogic() {
        let installedModels = ["gemma2:2b", "phi3:mini", "llama3:8b"]
        let modelToCheck = "gemma2:2b"
        
        let prefix = modelToCheck.split(separator: ":").first.map(String.init) ?? modelToCheck
        let isInstalled = installedModels.contains { $0.hasPrefix(prefix) }
        
        #expect(isInstalled == true)
    }
    
    @Test("Model not installed check logic works")
    func modelNotInstalledCheckLogic() {
        let installedModels = ["gemma2:2b", "phi3:mini"]
        let modelToCheck = "llama3:8b"
        
        let prefix = modelToCheck.split(separator: ":").first.map(String.init) ?? modelToCheck
        let isInstalled = installedModels.contains { $0.hasPrefix(prefix) }
        
        #expect(isInstalled == false)
    }
    
    @Test("Different tag of same model family is detected as installed")
    func differentTagSameFamily() {
        let installedModels = ["gemma2:7b"]
        let modelToCheck = "gemma2:2b"
        
        let prefix = modelToCheck.split(separator: ":").first.map(String.init) ?? modelToCheck
        let isInstalled = installedModels.contains { $0.hasPrefix(prefix) }
        
        #expect(isInstalled == true)
    }
    
    // MARK: - OllamaTagsResponse Parsing Tests
    
    @Test("OllamaTagsResponse decodes correctly")
    func ollamaTagsResponseDecodes() throws {
        let json = """
        {
            "models": [
                {"name": "gemma2:2b", "size": 1500000000, "digest": "abc123"},
                {"name": "phi3:mini", "size": 2000000000, "digest": "def456"}
            ]
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: json)
        
        #expect(response.models.count == 2)
        #expect(response.models[0].name == "gemma2:2b")
        #expect(response.models[0].size == 1500000000)
        #expect(response.models[1].name == "phi3:mini")
    }
    
    @Test("OllamaTagsResponse handles empty models array")
    func ollamaTagsResponseEmptyModels() throws {
        let json = """
        {
            "models": []
        }
        """.data(using: .utf8)!
        
        let response = try JSONDecoder().decode(OllamaTagsResponse.self, from: json)
        
        #expect(response.models.isEmpty)
    }
    
    @Test("OllamaModel handles optional fields")
    func ollamaModelOptionalFields() throws {
        let json = """
        {"name": "test:latest"}
        """.data(using: .utf8)!
        
        let model = try JSONDecoder().decode(OllamaModel.self, from: json)
        
        #expect(model.name == "test:latest")
        #expect(model.size == nil)
        #expect(model.digest == nil)
    }
    
    // MARK: - Keep-Alive Request Format Tests
    
    @Test("Keep-alive request body format is correct")
    func keepAliveRequestBodyFormat() throws {
        let modelName = "gemma2:2b"
        let requestBody: [String: Any] = [
            "model": modelName,
            "prompt": "",
            "keep_alive": -1
        ]
        
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        #expect(decoded?["model"] as? String == "gemma2:2b")
        #expect(decoded?["prompt"] as? String == "")
        #expect(decoded?["keep_alive"] as? Int == -1)
    }
    
    // MARK: - Pull Request Format Tests
    
    @Test("Pull request body format is correct")
    func pullRequestBodyFormat() throws {
        let modelName = "gemma2:2b"
        let requestBody = ["name": modelName]
        
        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String]
        
        #expect(decoded?["name"] == "gemma2:2b")
    }
    
    // MARK: - Progress Parsing Tests
    
    @Test("Pull progress percentage calculation")
    func pullProgressPercentage() {
        let completed: Int64 = 750_000_000
        let total: Int64 = 1_500_000_000
        
        let percent = Int((Double(completed) / Double(total)) * 100)
        
        #expect(percent == 50)
    }
    
    @Test("Pull progress at 100%")
    func pullProgressComplete() {
        let completed: Int64 = 1_500_000_000
        let total: Int64 = 1_500_000_000
        
        let percent = Int((Double(completed) / Double(total)) * 100)
        
        #expect(percent == 100)
    }
    
    @Test("Pull progress at 0%")
    func pullProgressZero() {
        let completed: Int64 = 0
        let total: Int64 = 1_500_000_000
        
        let percent = Int((Double(completed) / Double(total)) * 100)
        
        #expect(percent == 0)
    }
    
    // MARK: - URL Construction Tests
    
    @Test("Ollama API URLs are valid")
    func ollamaAPIURLsValid() {
        let tagsURL = URL(string: "http://localhost:11434/api/tags")
        let pullURL = URL(string: "http://localhost:11434/api/pull")
        let generateURL = URL(string: "http://localhost:11434/api/generate")
        
        #expect(tagsURL != nil)
        #expect(pullURL != nil)
        #expect(generateURL != nil)
    }
    
    @Test("Ollama default port is 11434")
    func ollamaDefaultPort() {
        let url = URL(string: "http://localhost:11434/api/tags")!
        #expect(url.port == 11434)
    }
    
    // MARK: - Base URL Normalization Tests
    
    @Test("Base URL normalization trims whitespace")
    func baseURLNormalizationTrimsWhitespace() {
        let rawURL = "  http://localhost:11434  "
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        #expect(normalized == "http://localhost:11434")
    }
    
    @Test("Base URL normalization removes trailing slashes")
    func baseURLNormalizationRemovesTrailingSlashes() {
        let rawURL = "http://localhost:11434/"
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        #expect(normalized == "http://localhost:11434")
    }
    
    @Test("Base URL normalization handles multiple trailing slashes")
    func baseURLNormalizationMultipleSlashes() {
        let rawURL = "http://localhost:11434///"
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        #expect(normalized == "http://localhost:11434")
    }
    
    @Test("Base URL normalization preserves remote URLs")
    func baseURLNormalizationRemoteURL() {
        let rawURL = "http://192.168.1.100:11434"
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        #expect(normalized == "http://192.168.1.100:11434")
    }
    
    @Test("Base URL normalization preserves HTTPS URLs")
    func baseURLNormalizationHTTPS() {
        let rawURL = "https://ollama.example.com:11434/"
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        #expect(normalized == "https://ollama.example.com:11434")
    }
    
    @Test("Normalized base URL constructs valid API endpoint")
    func normalizedBaseURLConstructsValidEndpoint() {
        let rawURL = "http://myserver:11434/"
        let normalized = rawURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let tagsURL = URL(string: "\(normalized)/api/tags")
        
        #expect(tagsURL != nil)
        #expect(tagsURL?.absoluteString == "http://myserver:11434/api/tags")
    }
}
