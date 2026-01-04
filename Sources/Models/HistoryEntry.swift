import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let original: String
    let refined: String
    let presetName: String?
    let systemPrompt: String?
    
    init(original: String, refined: String, presetName: String, systemPrompt: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.original = original
        self.refined = refined
        self.presetName = presetName
        self.systemPrompt = systemPrompt
    }
    
    var safePresetName: String {
        presetName ?? "Unknown"
    }
    
    var safeSystemPrompt: String {
        systemPrompt ?? "Prompt not saved for this entry."
    }
    
    var displayText: String {
        refined.isEmpty ? original : refined
    }
    
    var previewText: String {
        let text = displayText
        if text.count <= 50 {
            return text
        }
        return String(text.prefix(47)) + "..."
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var menuPreview: String {
        let text = displayText.replacingOccurrences(of: "\n", with: " ")
        let maxLength = 60
        if text.count <= maxLength {
            return "\(formattedTime) · \(text)"
        }
        return "\(formattedTime) · \(String(text.prefix(maxLength - 3)))..."
    }
}
