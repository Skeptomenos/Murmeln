import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let timestamp: Date
    let original: String
    let refined: String
    
    init(original: String, refined: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.original = original
        self.refined = refined
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
}
