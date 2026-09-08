import Foundation
import Testing
@testable import mrml

actor RecoveryDiskWriter {
    var outcomes: [Bool]
    var suspended = false
    var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ outcomes: [Bool] = []) { self.outcomes = outcomes }
    func setOutcomes(_ values: [Bool]) { outcomes = values }
    func suspendNext() { suspended = true }
    func release() { suspended = false; continuation?.resume(); continuation = nil }
    func write(_ data: Data, to url: URL) async throws {
        if suspended { waiting = true; await withCheckedContinuation { continuation = $0 }; waiting = false }
        let succeeds = outcomes.isEmpty ? true : outcomes.removeFirst()
        guard succeeds else { throw CocoaError(.fileWriteNoPermission) }
        try data.write(to: url, options: .atomic)
    }
}

@MainActor
@Suite("History recovery persistence", .serialized)
struct HistoryRecoveryPersistenceTests {
    private func makeStore(_ url: URL, writer: RecoveryDiskWriter) throws -> HistoryStore {
        HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)),
            persistence: HistoryPersistence(fileURL: url, writer: { try await writer.write($0, to: $1) }))
    }
    private func add(_ text: String, to store: HistoryStore) throws -> HistoryEntry {
        let entry = HistoryEntry(original: text, refined: text, presetName: "Raw", systemPrompt: "", captureID: UUID().uuidString)
        #expect(store.retain(entry, reservation: try #require(store.reserveCapacity())))
        return entry
    }

    @Test("A failed write followed by A+B success acknowledges both exact entries")
    func laterSnapshotSavesBoth() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecoveryDiskWriter([false, true])
        let store = try makeStore(url, writer: writer)
        let a = try add("A", to: store)
        let b = try add("B", to: store)
        #expect(await store.flush())
        #expect(store.isSaved(a.id) && store.isSaved(b.id))
        let reopened = try makeStore(url, writer: writer)
        #expect(reopened.entries == [b, a])
    }

    @Test("A success followed by A+B failure leaves unchanged A saved and B recoverable")
    func newerFailureDoesNotEraseReceipt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecoveryDiskWriter([true, false])
        let store = try makeStore(url, writer: writer)
        let a = try add("A", to: store)
        let b = try add("B", to: store)
        #expect(!(await store.flush()))
        #expect(store.isSaved(a.id))
        #expect(!store.isSaved(b.id))
        #expect(store.entry(id: b.id) == b)
        #expect(try makeStore(url, writer: writer).entries == [a])
        store.retrySave()
        #expect(await store.flush())
        #expect(try makeStore(url, writer: writer).entries == [b, a])
    }

    @Test("A late old save cannot acknowledge a failed deletion or resurrect its action")
    func deletionDuringOldWrite() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecoveryDiskWriter([true, false])
        await writer.suspendNext()
        let store = try makeStore(url, writer: writer)
        let a = try add("A", to: store)
        for _ in 0..<100 { await Task.yield() }
        #expect(await writer.waiting)
        store.protectedRecoveryID = a.id
        store.remove(entry: a)
        #expect(store.entry(id: a.id) == nil)
        #expect(store.protectedRecoveryID == nil)
        await writer.release()
        #expect(!(await store.flush()))
        #expect(store.entries.isEmpty)
        #expect(store.hasPendingDeletion)
        #expect(try makeStore(url, writer: writer).entries == [a])
        store.retrySave()
        #expect(await store.flush())
        #expect(try makeStore(url, writer: writer).entries.isEmpty)
    }

    @Test("Reservations count against capacity and never evict a protected recovery result")
    func mixedCapacity() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = RecoveryDiskWriter()
        let store = try makeStore(url, writer: writer)
        let saved = try add("saved", to: store)
        #expect(await store.flush())
        await writer.setOutcomes(Array(repeating: false, count: 60))
        for n in 0..<49 { _ = try add("unsaved \(n)", to: store) }
        #expect(!(await store.flush()))
        store.protectedRecoveryID = saved.id
        #expect(store.reserveCapacity() == nil)
        store.protectedRecoveryID = nil
        let token = try #require(store.reserveCapacity())
        #expect(store.entry(id: saved.id) != nil)
        #expect(store.reserveCapacity() == nil)
        store.remove(entry: saved)
        #expect(store.reserveCapacity() == nil) // Removed victim is now the reserved free slot.
        store.releaseReservation(token)
        #expect(store.reserveCapacity() != nil)
    }
}
