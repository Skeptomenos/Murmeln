import AppKit
import Testing
@testable import mrml

private final class RejectingPasteboardItem: NSPasteboardItem {
    override func setData(_ data: Data, forType dataType: NSPasteboard.PasteboardType) -> Bool { false }
}

@MainActor
private func makeCommandPasteEvents(baselineFlags: CGEventFlags = []) -> PasteServiceDependencies.PasteEvents? {
    PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
}

@MainActor
@Suite("Clipboard recovery safety")
struct ClipboardRecoverySafetyTests {
    @Test("Cancellation before posting reports failed restoration and records the attempt")
    func cancelledRestorationFailureIsReported() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        _ = board.setString("previous", forType: .string)
        var records: [PasteOperationalRecord] = []
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(pasteboard: board,
            setPasteboardString: { $1.setString($0, forType: .string) }, restoreClipboard: { _, _ in .restoreFailed },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) }, postEvent: { _ in posts += 1 },
            sleep: { _ in throw CancellationError() }, nowNanoseconds: { 0 },
            recordPasteAttempt: { records.append($0) }))
        var result: PasteTiming?
        do { result = try await service.pasteAndRestore(text: "final", captureID: "c") } catch {}
        #expect(posts == 0)
        #expect(result?.clipboardDisposition == .restoreFailed)
        #expect(result?.commandOutcome == .blocked(.cancelled))
        #expect(PasteFailurePresentation(blocker: .cancelled, clipboardDisposition: .restoreFailed).message.contains("could not be restored"))
        #expect(records.count == 1 && records.first?.clipboardDisposition == .restoreFailed)
    }

    @Test("Unavailable preservation causes zero automatic writes and posts", arguments: [0, 1, 2, 3])
    func unavailableSnapshotNeverMutates(kind: Int) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        _ = board.setString("original", forType: .string)
        var writes = 0
        var posts = 0
        var observedGeneration = board.changeCount
        let service = PasteService(dependencies: PasteServiceDependencies(pasteboard: board,
            captureClipboard: { board in
                let snapshot: ClipboardSnapshot
                switch kind {
                case 0: snapshot = ClipboardSnapshot.capture(from: board, readData: { _, _ in nil })
                case 1: snapshot = ClipboardSnapshot.capture(from: board, makeItem: { RejectingPasteboardItem() })
                case 2:
                    snapshot = ClipboardSnapshot.capture(from: board, makeItem: {
                        board.clearContents(); _ = board.setString("external", forType: .string)
                        return NSPasteboardItem()
                    })
                default:
                    snapshot = ClipboardSnapshot.capture(from: board)
                    board.clearContents(); _ = board.setString("external", forType: .string)
                }
                observedGeneration = board.changeCount
                return snapshot
            },
            setPasteboardString: { writes += 1; return $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) }, postEvent: { _ in posts += 1 },
            sleep: { _ in }, nowNanoseconds: { 0 }))
        let result = try await service.pasteAndRestore(text: "dictation", captureID: nil)
        #expect(result.commandOutcome == .blocked(.clipboardSnapshotUnavailable))
        #expect(writes == 0 && posts == 0 && board.changeCount == observedGeneration)
    }

    @Test("Event construction cannot cause a replacement clipboard to be pasted")
    func eventConstructionReplacement() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                board.clearContents()
                _ = board.setString("new copy", forType: .string)
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            }, postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }))
        let result = try await service.pasteAndRestore(text: "dictation", captureID: nil)
        #expect(posts == 0)
        #expect(result.commandOutcome == .blocked(.clipboardChanged))
        #expect(board.string(forType: .string) == "new copy")
    }

    @Test("Reconstruction cannot erase a replacement clipboard")
    func reconstructionReplacement() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("original", forType: .string)
        var replace = false
        let snapshot = ClipboardSnapshot.capture(from: board, makeItem: {
            if replace { board.clearContents(); _ = board.setString("new copy", forType: .string) }
            return NSPasteboardItem()
        })
        replace = true
        #expect(!snapshot.restore(to: board))
        #expect(board.string(forType: .string) == "new copy")
    }

    @Test("A snapshot that becomes stale during reconstruction is unavailable")
    func snapshotReconstructionReplacement() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("original", forType: .string)
        let snapshot = ClipboardSnapshot.capture(from: board, makeItem: {
            board.clearContents()
            _ = board.setString("new copy", forType: .string)
            return NSPasteboardItem()
        })
        #expect(!snapshot.isAvailable)
    }

    @Test("Known Secure Input leaves the unrelated clipboard untouched")
    func knownBlockDoesNotWrite() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        #expect(board.setString("unrelated", forType: .string))
        let generation = board.changeCount
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { true },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) }, postEvent: { _ in Issue.record("Must not post") },
            sleep: { _ in }, nowNanoseconds: { 0 }))
        let result = try await service.pasteAndRestore(text: "dictation", captureID: nil)
        #expect(result.commandOutcome == .blocked(.secureInputActive))
        #expect(board.changeCount == generation)
        #expect(board.string(forType: .string) == "unrelated")
    }

    @Test("Clipboard replacement before posting prevents every key event")
    func externalReplacementStopsPosting() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) }, postEvent: { _ in posts += 1 },
            sleep: { duration in
                if duration == .milliseconds(100) { board.clearContents(); _ = board.setString("new user copy", forType: .string) }
            }, nowNanoseconds: { 0 }))
        _ = try await service.pasteAndRestore(text: "dictation", captureID: nil)
        #expect(posts == 0)
        #expect(board.string(forType: .string) == "new user copy")
    }

    @Test("Recovery Copy cannot replace the clipboard while paste owns it")
    func copyIsBusyWhilePasteOwnsClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let gate = PasteTransactionGate()
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) }, postEvent: { _ in },
            sleep: { _ in }, nowNanoseconds: { 0 }), transactionGate: gate)
        try await gate.acquire()
        let generation = board.changeCount
        #expect(!service.copyToClipboardForRecovery(text: "old result"))
        #expect(board.changeCount == generation)
        await gate.release()
    }

    @Test("An unreadable advertised representation cannot be restored as complete")
    func partialSnapshotIsUnavailable() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        let custom = NSPasteboard.PasteboardType("test.unreadable")
        #expect(item.setString("readable", forType: .string))
        #expect(item.setData(Data([1, 2]), forType: custom))
        board.clearContents()
        #expect(board.writeObjects([item]))
        let snapshot = ClipboardSnapshot.capture(from: board, readData: { item, type in
            type == custom ? nil : item.data(forType: type)
        })
        let generation = board.changeCount
        #expect(!snapshot.restore(to: board))
        #expect(board.changeCount == generation)
    }
}
