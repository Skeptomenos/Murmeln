import Foundation
import SwiftUI

/// History is the only result store. Reserve capacity before accepting capture.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    static let capacity = 50
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var saveState: HistorySaveState = .saved
    @Published private(set) var capacityBlocked = false
    @Published private(set) var loadFailed = false
    @Published var mutationsSuspended = false
    var protectedRecoveryID: UUID?
    var onEntriesChanged: (@MainActor () -> Void)?

    private struct Reservation { let victim: UUID? }
    private var reservations: [UUID: Reservation] = [:]
    private var persistedEntries: [HistoryEntry] = []
    private var scheduledRevision = 0
    private var acknowledgedRevision = 0
    private let persistence: HistoryPersistence
    private let fileURL: URL
    private let legacyDefaults: UserDefaults
    private let legacyStorageKey = "transcriptionHistory"

    init(
        fileURL: URL = AppIdentity.appSupportDirectoryURL.appendingPathComponent("history.json"),
        legacyDefaults: UserDefaults = .standard,
        persistence: HistoryPersistence? = nil
    ) {
        self.fileURL = fileURL
        self.legacyDefaults = legacyDefaults
        self.persistence = persistence ?? HistoryPersistence(fileURL: fileURL)
        load()
    }

    var recentEntries: [HistoryEntry] { Array(entries.prefix(10)) }
    var hasUnpersistedChanges: Bool { loadFailed || entries != persistedEntries || saveState != .saved }
    var hasPendingDeletion: Bool {
        let currentIDs = Set(entries.map(\.id))
        return persistedEntries.contains { !currentIDs.contains($0.id) }
    }
    func entry(id: UUID) -> HistoryEntry? { entries.first { $0.id == id } }
    func isSaved(_ id: UUID) -> Bool {
        guard let current = entry(id: id) else { return false }
        return persistedEntries.contains(current)
    }

    func reserveCapacity() -> UUID? {
        guard !mutationsSuspended else { return nil }
        guard !loadFailed else { capacityBlocked = true; return nil }
        let freeReservations = reservations.values.filter { reservation in
            guard let victim = reservation.victim else { return true }
            return entry(id: victim) == nil
        }.count
        let victim: UUID?
        if entries.count + freeReservations < Self.capacity {
            victim = nil
        } else {
            let reservedIDs = Set(reservations.values.compactMap(\.victim))
            guard let candidate = entries.last(where: {
                $0.id != protectedRecoveryID && !reservedIDs.contains($0.id) && isSaved($0.id)
            }) else { capacityBlocked = true; return nil }
            victim = candidate.id
        }
        let token = UUID()
        reservations[token] = Reservation(victim: victim)
        capacityBlocked = false
        return token
    }

    func releaseReservation(_ token: UUID) { reservations[token] = nil }

    @discardableResult
    func retain(_ entry: HistoryEntry, reservation token: UUID) -> Bool {
        guard let reservation = reservations.removeValue(forKey: token),
              !entries.contains(where: { $0.id == entry.id }) else { return false }
        if let victim = reservation.victim { entries.removeAll { $0.id == victim } }
        entries.insert(entry, at: 0)
        capacityBlocked = false
        persist()
        onEntriesChanged?()
        return true
    }

    func add(original: String, refined: String, presetName: String, systemPrompt: String,
             effectiveSystemPrompt: String? = nil, variants: [String: String]? = nil,
             variantPrompts: [String: String]? = nil, effectiveVariantPrompts: [String: String]? = nil) {
        guard let token = reserveCapacity() else { return }
        retain(HistoryEntry(original: original, refined: refined, presetName: presetName,
            systemPrompt: systemPrompt, effectiveSystemPrompt: effectiveSystemPrompt,
            variants: variants, variantPrompts: variantPrompts,
            effectiveVariantPrompts: effectiveVariantPrompts), reservation: token)
    }

    func remove(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        remove(ids: ids)
    }
    func remove(entry: HistoryEntry) { remove(ids: [entry.id]) }
    func clear() { remove(ids: Set(entries.map(\.id))) }

    private func remove(ids: Set<UUID>) {
        guard !mutationsSuspended else { return }
        entries.removeAll { ids.contains($0.id) }
        if let protectedRecoveryID, ids.contains(protectedRecoveryID) { self.protectedRecoveryID = nil }
        capacityBlocked = false
        onEntriesChanged?()
        persist()
    }

    func retrySave() { if !loadFailed && !mutationsSuspended { persist() } }

    @discardableResult
    func flush() async -> Bool {
        await persistence.flush()
        return !hasUnpersistedChanges
    }

    private func persist() {
        guard !loadFailed else { return } // Never overwrite an unreadable existing file.
        saveState = .saving
        scheduledRevision = persistence.enqueue(HistoryStorage(entries: entries)) { [weak self] receipt in
            guard let self, receipt.revision > self.acknowledgedRevision else { return }
            self.acknowledgedRevision = receipt.revision
            if receipt.succeeded { self.persistedEntries = receipt.storage.entries }
            if receipt.revision == self.scheduledRevision {
                self.saveState = receipt.succeeded ? .saved : .failed
            }
            self.objectWillChange.send()
        }
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let storage = try JSONDecoder().decode(HistoryStorage.self, from: Data(contentsOf: fileURL))
                guard storage.version <= HistoryStorage.currentVersion else {
                    loadFailed = true; saveState = .failed; return
                }
                entries = storage.entries
                persistedEntries = entries
                legacyDefaults.removeObject(forKey: legacyStorageKey)
            } else if let data = legacyDefaults.data(forKey: legacyStorageKey) {
                entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
                saveState = .saving
                scheduledRevision = persistence.enqueue(HistoryStorage(entries: entries)) { [weak self] receipt in
                    guard let self else { return }
                    self.acknowledgedRevision = receipt.revision
                    if receipt.succeeded {
                        self.persistedEntries = receipt.storage.entries
                        self.legacyDefaults.removeObject(forKey: self.legacyStorageKey)
                    }
                    if receipt.revision == self.scheduledRevision { self.saveState = receipt.succeeded ? .saved : .failed }
                }
            }
        } catch {
            loadFailed = true
            saveState = .failed
        }
    }
}
