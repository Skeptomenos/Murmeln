import Foundation
import SwiftUI

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    
    private let storageKey = "transcriptionHistory"
    private let maxEntries = 50
    
    @Published private(set) var entries: [HistoryEntry] = []
    
    private init() {
        load()
    }
    
    func add(original: String, refined: String) {
        let entry = HistoryEntry(original: original, refined: refined)
        entries.insert(entry, at: 0)
        
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        
        save()
    }
    
    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        save()
    }
    
    func remove(entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func clear() {
        entries.removeAll()
        save()
    }
    
    var recentEntries: [HistoryEntry] {
        Array(entries.prefix(10))
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else {
            return
        }
        entries = decoded
    }
}
