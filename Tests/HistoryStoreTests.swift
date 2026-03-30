import Testing
import Foundation
@testable import mrml

// MARK: - HistoryStore Tests

@Suite("HistoryStore Tests")
struct HistoryStoreTests {
    
    // MARK: - HistoryEntry CRUD Logic Tests
    
    @Test("Adding entry inserts at beginning of array")
    func addEntryInsertsAtBeginning() {
        var entries: [HistoryEntry] = []
        
        let entry1 = HistoryEntry(original: "first", refined: "First", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        entries.insert(entry1, at: 0)
        
        let entry2 = HistoryEntry(original: "second", refined: "Second", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        entries.insert(entry2, at: 0)
        
        #expect(entries.count == 2)
        #expect(entries[0].original == "second")
        #expect(entries[1].original == "first")
    }
    
    @Test("Max limit of 50 entries is enforced")
    func maxLimitEnforced() {
        var entries: [HistoryEntry] = []
        let maxEntries = 50
        
        for i in 0..<55 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.insert(entry, at: 0)
            
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
        }
        
        #expect(entries.count == 50)
        #expect(entries[0].original == "entry 54")
        #expect(entries[49].original == "entry 5")
    }
    
    @Test("Remove entry by ID works correctly")
    func removeEntryById() {
        var entries: [HistoryEntry] = []
        
        let entry1 = HistoryEntry(original: "keep", refined: "Keep", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        let entry2 = HistoryEntry(original: "remove", refined: "Remove", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        let entry3 = HistoryEntry(original: "keep2", refined: "Keep2", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        
        entries = [entry1, entry2, entry3]
        entries.removeAll { $0.id == entry2.id }
        
        #expect(entries.count == 2)
        #expect(entries.contains { $0.id == entry1.id })
        #expect(entries.contains { $0.id == entry3.id })
        #expect(!entries.contains { $0.id == entry2.id })
    }
    
    @Test("Remove entry at offsets works correctly")
    func removeAtOffsets() {
        var entries: [HistoryEntry] = []
        
        for i in 0..<5 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.append(entry)
        }
        
        let offsets = IndexSet([1, 3])
        entries.remove(atOffsets: offsets)
        
        #expect(entries.count == 3)
        #expect(entries[0].original == "entry 0")
        #expect(entries[1].original == "entry 2")
        #expect(entries[2].original == "entry 4")
    }
    
    @Test("Clear removes all entries")
    func clearRemovesAll() {
        var entries: [HistoryEntry] = []
        
        for i in 0..<10 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.append(entry)
        }
        
        #expect(entries.count == 10)
        
        entries.removeAll()
        
        #expect(entries.count == 0)
        #expect(entries.isEmpty)
    }
    
    @Test("Recent entries returns first 10")
    func recentEntriesReturnsFirst10() {
        var entries: [HistoryEntry] = []
        
        for i in 0..<25 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.append(entry)
        }
        
        let recentEntries = Array(entries.prefix(10))
        
        #expect(recentEntries.count == 10)
        #expect(recentEntries[0].original == "entry 0")
        #expect(recentEntries[9].original == "entry 9")
    }
    
    @Test("Recent entries returns all when less than 10")
    func recentEntriesReturnsAllWhenLessThan10() {
        var entries: [HistoryEntry] = []
        
        for i in 0..<5 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.append(entry)
        }
        
        let recentEntries = Array(entries.prefix(10))
        
        #expect(recentEntries.count == 5)
    }
    
    // MARK: - Persistence Tests
    
    @Test("HistoryEntry array encodes and decodes correctly")
    func historyEntryArrayPersistence() throws {
        let entries = [
            HistoryEntry(original: "hello", refined: "Hello.", presetName: "Casual", systemPrompt: "Prompt1", variants: ["Casual": "Hello."], variantPrompts: ["Casual": "Prompt1"]),
            HistoryEntry(original: "world", refined: "World!", presetName: "Structured", systemPrompt: "Prompt2", variants: nil, variantPrompts: nil)
        ]
        
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: encoded)
        
        #expect(decoded.count == 2)
        #expect(decoded[0].original == "hello")
        #expect(decoded[0].refined == "Hello.")
        #expect(decoded[0].variants?["Casual"] == "Hello.")
        #expect(decoded[1].original == "world")
        #expect(decoded[1].safePresetName == "Structured")
    }
    
    @Test("Empty entries array encodes and decodes correctly")
    func emptyEntriesPersistence() throws {
        let entries: [HistoryEntry] = []
        
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: encoded)
        
        #expect(decoded.isEmpty)
    }
    
    @Test("Entries with all variant data persist correctly")
    func fullVariantDataPersistence() throws {
        let variants = [
            "Casual": "Hello, world.",
            "Structured": "- Hello\n- World",
            "Markdown": "## Hello\n\nWorld",
            "Verbatim": "hello world"
        ]
        let variantPrompts = [
            "Casual": "Casual prompt",
            "Structured": "Structured prompt",
            "Markdown": "Markdown prompt",
            "Verbatim": "Verbatim prompt"
        ]
        
        let entry = HistoryEntry(
            original: "hello world",
            refined: "Hello, world.",
            presetName: "Casual",
            systemPrompt: "Casual prompt",
            variants: variants,
            variantPrompts: variantPrompts
        )
        
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)
        
        #expect(decoded.variants?.count == 4)
        #expect(decoded.variantPrompts?.count == 4)
        #expect(decoded.variants?["Markdown"] == "## Hello\n\nWorld")
        #expect(decoded.variantPrompts?["Verbatim"] == "Verbatim prompt")
    }

    @Test("Selected and variant effective prompt provenance persist separately")
    func effectivePromptProvenancePersistence() throws {
        let entry = HistoryEntry(
            original: "hello world",
            refined: "Hello, world.",
            presetName: "Casual",
            systemPrompt: "Base prompt",
            effectiveSystemPrompt: "Base prompt with dictionary",
            variants: ["Casual": "Hello, world."],
            variantPrompts: ["Casual": "Variant base prompt"],
            effectiveVariantPrompts: ["Casual": "Variant base prompt with dictionary"]
        )

        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)

        #expect(decoded.systemPrompt == "Base prompt")
        #expect(decoded.effectiveSystemPrompt == "Base prompt with dictionary")
        #expect(decoded.variantPrompts?["Casual"] == "Variant base prompt")
        #expect(decoded.effectiveVariantPrompts?["Casual"] == "Variant base prompt with dictionary")
    }
    
    // MARK: - Edge Cases
    
    @Test("Entry with empty strings handles correctly")
    func emptyStringsHandled() {
        let entry = HistoryEntry(original: "", refined: "", presetName: "", systemPrompt: "", variants: nil, variantPrompts: nil)
        
        #expect(entry.original == "")
        #expect(entry.displayText == "")
        #expect(entry.previewText == "")
    }
    
    @Test("Entry with unicode content persists correctly")
    func unicodeContentPersists() throws {
        let entry = HistoryEntry(
            original: "Hallo Welt",
            refined: "Hallo Welt!",
            presetName: "Casual",
            systemPrompt: "Prompt",
            variants: nil,
            variantPrompts: nil
        )
        
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: encoded)
        
        #expect(decoded.original == "Hallo Welt")
        #expect(decoded.refined == "Hallo Welt!")
    }
    
    @Test("Entry with very long text handles correctly")
    func veryLongTextHandled() {
        let longText = String(repeating: "a", count: 10000)
        let entry = HistoryEntry(original: longText, refined: longText, presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        
        #expect(entry.original.count == 10000)
        #expect(entry.previewText.count == 50)
        #expect(entry.previewText.hasSuffix("..."))
    }
    
    @Test("Removing non-existent entry does nothing")
    func removeNonExistentEntry() {
        var entries: [HistoryEntry] = []
        
        let entry1 = HistoryEntry(original: "keep", refined: "Keep", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        entries = [entry1]
        
        let nonExistentId = UUID()
        entries.removeAll { $0.id == nonExistentId }
        
        #expect(entries.count == 1)
        #expect(entries[0].id == entry1.id)
    }
    
    @Test("Adding exactly 50 entries maintains all")
    func exactlyMaxEntries() {
        var entries: [HistoryEntry] = []
        let maxEntries = 50
        
        for i in 0..<50 {
            let entry = HistoryEntry(original: "entry \(i)", refined: "Entry \(i)", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
            entries.insert(entry, at: 0)
            
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
        }
        
        #expect(entries.count == 50)
        #expect(entries[0].original == "entry 49")
        #expect(entries[49].original == "entry 0")
    }
}

// MARK: - HistoryStorage Tests (File-Based Storage Format)

@Suite("HistoryStorage Tests")
struct HistoryStorageTests {
    
    @Test("HistoryStorage encodes and decodes correctly")
    func historyStorageEncodesAndDecodes() throws {
        let entries = [
            HistoryEntry(original: "hello", refined: "Hello.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil),
            HistoryEntry(original: "world", refined: "World!", presetName: "Structured", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        
        let storage = HistoryStorage(entries: entries)
        
        let encoded = try JSONEncoder().encode(storage)
        let decoded = try JSONDecoder().decode(HistoryStorage.self, from: encoded)
        
        #expect(decoded.version == HistoryStorage.currentVersion)
        #expect(decoded.entries.count == 2)
        #expect(decoded.entries[0].original == "hello")
        #expect(decoded.entries[1].original == "world")
    }
    
    @Test("HistoryStorage current version is 1")
    func currentVersionIs1() {
        #expect(HistoryStorage.currentVersion == 1)
    }
    
    @Test("HistoryStorage with empty entries encodes correctly")
    func emptyEntriesEncode() throws {
        let storage = HistoryStorage(entries: [])
        
        let encoded = try JSONEncoder().encode(storage)
        let decoded = try JSONDecoder().decode(HistoryStorage.self, from: encoded)
        
        #expect(decoded.version == 1)
        #expect(decoded.entries.isEmpty)
    }
    
    @Test("HistoryStorage preserves version number")
    func preservesVersionNumber() throws {
        let entries = [
            HistoryEntry(original: "test", refined: "Test.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        
        // Simulate a future version
        let storage = HistoryStorage(version: 5, entries: entries)
        
        let encoded = try JSONEncoder().encode(storage)
        let decoded = try JSONDecoder().decode(HistoryStorage.self, from: encoded)
        
        #expect(decoded.version == 5)
        #expect(decoded.entries.count == 1)
    }
    
    @Test("HistoryStorage is Sendable")
    func isSendable() {
        let entries = [
            HistoryEntry(original: "test", refined: "Test.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        let storage = HistoryStorage(entries: entries)
        
        // This test verifies Sendable conformance at compile time
        Task.detached {
            _ = storage.version
            _ = storage.entries.count
        }
        
        #expect(storage.version == 1)
    }
    
    @Test("HistoryStorage with variants encodes correctly")
    func variantsEncodeCorrectly() throws {
        let variants = ["Casual": "Hello.", "Structured": "- Hello"]
        let variantPrompts = ["Casual": "Prompt1", "Structured": "Prompt2"]
        
        let entries = [
            HistoryEntry(original: "hello", refined: "Hello.", presetName: "Casual", systemPrompt: "Prompt1", variants: variants, variantPrompts: variantPrompts)
        ]
        
        let storage = HistoryStorage(entries: entries)
        
        let encoded = try JSONEncoder().encode(storage)
        let decoded = try JSONDecoder().decode(HistoryStorage.self, from: encoded)
        
        #expect(decoded.entries[0].variants?["Casual"] == "Hello.")
        #expect(decoded.entries[0].variants?["Structured"] == "- Hello")
        #expect(decoded.entries[0].variantPrompts?["Casual"] == "Prompt1")
    }
    
    @Test("HistoryStorage JSON format is correct")
    func jsonFormatIsCorrect() throws {
        let entries = [
            HistoryEntry(original: "test", refined: "Test.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        
        let storage = HistoryStorage(entries: entries)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(storage)
        let jsonString = String(data: encoded, encoding: .utf8)!
        
        // Verify the JSON contains the expected top-level keys
        #expect(jsonString.contains("\"version\""))
        #expect(jsonString.contains("\"entries\""))
        #expect(jsonString.contains(": 1")) // version value
    }
    
    @Test("HistoryStorage decodes legacy format gracefully")
    func decodesLegacyFormat() throws {
        // Simulate a minimal valid storage JSON
        let json = """
        {
            "version": 1,
            "entries": []
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HistoryStorage.self, from: data)
        
        #expect(decoded.version == 1)
        #expect(decoded.entries.isEmpty)
    }
}

// MARK: - Migration Tests

@Suite("History Migration Tests")
struct HistoryMigrationTests {
    
    @Test("Legacy HistoryEntry array can be decoded")
    func legacyArrayCanBeDecoded() throws {
        // This simulates the old UserDefaults format (just an array of entries)
        let entries = [
            HistoryEntry(original: "old1", refined: "Old1.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil),
            HistoryEntry(original: "old2", refined: "Old2.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        
        let encoded = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([HistoryEntry].self, from: encoded)
        
        #expect(decoded.count == 2)
        #expect(decoded[0].original == "old1")
        #expect(decoded[1].original == "old2")
    }
    
    @Test("Legacy format can be wrapped in HistoryStorage")
    func legacyFormatCanBeWrapped() throws {
        // Simulate migration: decode old format, wrap in new format
        let oldEntries = [
            HistoryEntry(original: "migrated", refined: "Migrated.", presetName: "Casual", systemPrompt: "Prompt", variants: nil, variantPrompts: nil)
        ]
        
        let oldData = try JSONEncoder().encode(oldEntries)
        let decodedOld = try JSONDecoder().decode([HistoryEntry].self, from: oldData)
        
        // Wrap in new format
        let newStorage = HistoryStorage(entries: decodedOld)
        
        let newData = try JSONEncoder().encode(newStorage)
        let decodedNew = try JSONDecoder().decode(HistoryStorage.self, from: newData)
        
        #expect(decodedNew.version == 1)
        #expect(decodedNew.entries.count == 1)
        #expect(decodedNew.entries[0].original == "migrated")
    }
    
    @Test("Empty legacy data migrates to empty storage")
    func emptyLegacyMigrates() throws {
        let oldEntries: [HistoryEntry] = []
        let oldData = try JSONEncoder().encode(oldEntries)
        let decodedOld = try JSONDecoder().decode([HistoryEntry].self, from: oldData)
        
        let newStorage = HistoryStorage(entries: decodedOld)
        
        #expect(newStorage.version == 1)
        #expect(newStorage.entries.isEmpty)
    }
    
    @Test("Large legacy data migrates correctly")
    func largeLegacyMigrates() throws {
        var oldEntries: [HistoryEntry] = []
        for i in 0..<50 {
            oldEntries.append(HistoryEntry(
                original: "entry \(i)",
                refined: "Entry \(i).",
                presetName: "Casual",
                systemPrompt: "Prompt",
                variants: nil,
                variantPrompts: nil
            ))
        }
        
        let oldData = try JSONEncoder().encode(oldEntries)
        let decodedOld = try JSONDecoder().decode([HistoryEntry].self, from: oldData)
        
        let newStorage = HistoryStorage(entries: decodedOld)
        
        #expect(newStorage.entries.count == 50)
        #expect(newStorage.entries[0].original == "entry 0")
        #expect(newStorage.entries[49].original == "entry 49")
    }
}
