import Foundation
import SwiftUI
import os.log

// MARK: - Storage Format

/// Versioned storage format for history persistence
struct HistoryStorage: Codable, Sendable {
    let version: Int
    let entries: [HistoryEntry]
    
    static let currentVersion = 1
    
    init(version: Int = currentVersion, entries: [HistoryEntry]) {
        self.version = version
        self.entries = entries
    }
}

// MARK: - Logger (module-level for Sendable access)

private let historyLogger = Logger(subsystem: AppIdentity.loggerSubsystem, category: "HistoryStore")

// MARK: - HistoryStore

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    
    private let legacyStorageKey = "transcriptionHistory"
    private let maxEntries = 50
    
    @Published private(set) var entries: [HistoryEntry] = []
    
    /// File URL for history storage in Application Support
    private let fileURL: URL = {
        let murmelnDir = AppIdentity.appSupportDirectoryURL
        return murmelnDir.appendingPathComponent("history.json")
    }()
    
    private init() {
        migrateFromUserDefaultsIfNeeded()
        loadFromFile()
    }
    
    // MARK: - Public API
    
    func add(
        original: String, 
        refined: String, 
        presetName: String, 
        systemPrompt: String, 
        effectiveSystemPrompt: String? = nil,
        variants: [String: String]? = nil,
        variantPrompts: [String: String]? = nil,
        effectiveVariantPrompts: [String: String]? = nil
    ) {
        let entry = HistoryEntry(
            original: original, 
            refined: refined, 
            presetName: presetName, 
            systemPrompt: systemPrompt, 
            effectiveSystemPrompt: effectiveSystemPrompt,
            variants: variants,
            variantPrompts: variantPrompts,
            effectiveVariantPrompts: effectiveVariantPrompts
        )
        entries.insert(entry, at: 0)
        
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        
        saveToFile()
    }
    
    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        saveToFile()
    }
    
    func remove(entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        saveToFile()
    }
    
    func clear() {
        entries.removeAll()
        saveToFile()
    }
    
    var recentEntries: [HistoryEntry] {
        Array(entries.prefix(10))
    }
    
    // MARK: - File-Based Storage
    
    /// Save entries to file asynchronously with atomic write
    private func saveToFile() {
        let entriesToSave = entries
        let url = fileURL
        
        Task.detached(priority: .utility) {
            let storage = HistoryStorage(entries: entriesToSave)
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(storage)
                
                // Atomic write: write to temp file, then rename
                let tempURL = url.deletingLastPathComponent().appendingPathComponent("history.json.tmp")
                try data.write(to: tempURL, options: [.atomic])
                
                // Remove existing file if present, then rename temp to final
                let fileManager = FileManager.default
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
                try fileManager.moveItem(at: tempURL, to: url)
                
                #if DEBUG
                historyLogger.debug("History saved: \(entriesToSave.count) entries")
                #endif
            } catch {
                historyLogger.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    /// Load entries from file synchronously (called once at init)
    private func loadFromFile() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            historyLogger.debug("No history file found, starting fresh")
            #endif
            return
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let storage = try JSONDecoder().decode(HistoryStorage.self, from: data)
            
            // Handle version migrations here if needed in the future
            if storage.version > HistoryStorage.currentVersion {
                historyLogger.warning("History file version \(storage.version) is newer than supported \(HistoryStorage.currentVersion)")
            }
            
            entries = storage.entries
            #if DEBUG
            historyLogger.debug("History loaded: \(self.entries.count) entries (version \(storage.version))")
            #endif
        } catch {
            historyLogger.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
            // Don't crash - just start with empty history
            entries = []
        }
    }
    
    // MARK: - Migration
    
    /// One-time migration from UserDefaults to file-based storage
    private func migrateFromUserDefaultsIfNeeded() {
        guard let oldData = UserDefaults.standard.data(forKey: legacyStorageKey) else {
            return // No legacy data to migrate
        }
        
        do {
            let oldEntries = try JSONDecoder().decode([HistoryEntry].self, from: oldData)
            
            // Only migrate if we don't already have a file
            guard !FileManager.default.fileExists(atPath: fileURL.path) else {
                // File exists, just clean up UserDefaults
                UserDefaults.standard.removeObject(forKey: legacyStorageKey)
                historyLogger.info("Cleaned up legacy UserDefaults key (file already exists)")
                return
            }
            
            // Write migrated data to file
            let storage = HistoryStorage(entries: oldEntries)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(storage)
            try data.write(to: fileURL, options: [.atomic])
            
            // Clean up UserDefaults after successful migration
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            
            historyLogger.info("Migrated \(oldEntries.count) history entries from UserDefaults to file")
        } catch {
            historyLogger.error("Failed to migrate history from UserDefaults: \(error.localizedDescription, privacy: .public)")
            // Don't remove UserDefaults data if migration failed - user can try again
        }
    }
}
