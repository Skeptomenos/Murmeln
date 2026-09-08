import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Paste write generation ownership")
struct PasteWriteOwnershipTests {
    @Test("A successful private-board string write keeps the generation returned by clearContents")
    func clearGenerationSurvivesStringWrite() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.setString("original private marker", forType: .string))
        let before = board.changeCount

        let claimedGeneration = board.clearContents()
        let didWrite = board.setString("owned private transcript", forType: .string)
        let afterWrite = board.changeCount

        print("PRIVATE_BOARD_GENERATIONS before=\(before) clear_return=\(claimedGeneration) after_string=\(afterWrite) write_succeeded=\(didWrite)")
        #expect(didWrite)
        #expect(claimedGeneration > before)
        #expect(afterWrite == claimedGeneration)
        #expect(board.string(forType: .string) == "owned private transcript")
    }

    @Test("An external write before setString returns cannot become the transaction's owned generation")
    func externalWriteDuringSuccessfulStringBoundaryIsPreserved() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let competingWriter = NSPasteboard(name: board.name)
        #expect(board.setString("original private marker", forType: .string))
        var ownWriteSucceeded = false
        var externalWriteSucceeded = false
        var ownGeneration: Int?
        var externalGeneration: Int?
        var posts = 0
        var restores = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board,
            setPasteboardString: { text, board in
                ownWriteSucceeded = board.setString(text, forType: .string)
                ownGeneration = board.changeCount
                competingWriter.clearContents()
                externalWriteSucceeded = competingWriter.setString("newer external private marker", forType: .string)
                externalGeneration = competingWriter.changeCount
                return ownWriteSucceeded
            },
            restoreClipboard: { snapshot, board in
                restores += 1
                return snapshot.restoreOutcome(to: board)
            },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { [] },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }))

        let timing = try await service.pasteAndRestore(text: "owned private transcript", captureID: "private-write-ownership")

        print("PRIVATE_WRITE_OWNERSHIP own_generation=\(ownGeneration ?? -1) external_generation=\(externalGeneration ?? -1) final_generation=\(board.changeCount) posts=\(posts) restores=\(restores)")
        #expect(ownWriteSucceeded && externalWriteSucceeded)
        #expect(try #require(externalGeneration) > #require(ownGeneration))
        #expect(timing.commandOutcome == .blocked(.clipboardChanged))
        #expect(timing.clipboardDisposition == .externalWritePreserved)
        #expect(posts == 0)
        #expect(restores == 0)
        #expect(board.changeCount == externalGeneration)
        #expect(board.string(forType: .string) == "newer external private marker")
    }
}
