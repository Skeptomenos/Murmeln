import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("History Copy safety")
struct HistoryCopySafetyTests {
    @Test("Every History payload uses the same clipboard owner and resolves the live ID")
    func copyPayloadsAndBusyOwner() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let history = HistoryStore(fileURL: url, legacyDefaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
        let entry = HistoryEntry(original: "original text", refined: "chosen result", presetName: "Selected",
            systemPrompt: "base prompt", variants: ["Selected": "chosen result", "Other": "other result"])
        #expect(history.retain(entry, reservation: try #require(history.reserveCapacity())))
        let gate = PasteTransactionGate()
        var writes: [String] = []
        var posts = 0
        let paste = PasteService(dependencies: PasteServiceDependencies(pasteboard: board,
            setPasteboardString: { writes.append($0); return $1.setString($0, forType: .string) },
            preflightPostEventAccess: { false }, secureInputActive: { true },
            readModifierFlags: { [] },
            makePasteEvents: { _ in nil }, postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }),
            transactionGate: gate)
        let copier = HistoryCopyController(store: history, paste: paste, announce: { _ in })
        let actions: [HistoryCopyController.Payload] = [.finalResult, .original, .variant("Other"), .fullAudit]
        try await gate.acquire()
        let generation = board.changeCount
        for action in actions { copier.copy(id: entry.id, payload: action) }
        #expect(copier.message == ClipboardCopyOutcome.busy.message)
        #expect(writes.isEmpty && board.changeCount == generation)
        let selection = HistorySelectionTextView()
        selection.string = entry.refined
        selection.setSelectedRange(NSRange(location: 0, length: 6))
        selection.copySelection = { copier.copySelection(id: entry.id, text: $0) }
        var fallbackCount = 0
        HistoryCopyCommand.perform(firstResponder: selection) {
            fallbackCount += 1
            copier.copy(id: entry.id, payload: .finalResult)
        }
        #expect(fallbackCount == 0)
        #expect(copier.message == ClipboardCopyOutcome.busy.message && writes.isEmpty)
        gate.release()
        for _ in 0..<10 { await Task.yield() }
        #expect(writes.isEmpty)
        HistoryCopyCommand.perform(firstResponder: selection) {
            fallbackCount += 1
            copier.copy(id: entry.id, payload: .finalResult)
        }
        #expect(fallbackCount == 0)
        #expect(writes == ["chosen"])
        writes.removeAll()
        for action in actions { copier.copy(id: entry.id, payload: action) }
        #expect(Array(writes.prefix(3)) == ["chosen result", "original text", "other result"])
        #expect(writes.count == 4)
        #expect(writes.last?.contains("Variant: Selected (SELECTED)") == true)
        #expect(writes.last?.contains("other result") == true)
        #expect(posts == 0)
        history.remove(entry: entry)
        copier.copy(id: entry.id, payload: .finalResult)
        #expect(writes.count == 4)
        #expect(copier.message == "This entry was deleted.")
        #expect(await history.flush())
    }
}
