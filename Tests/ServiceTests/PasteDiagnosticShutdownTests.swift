import AppKit
import Testing
@testable import mrml

@MainActor
@Suite("Paste diagnostic shutdown")
struct PasteDiagnosticShutdownTests {
    @Test("Quit owns and joins the diagnostic before and after posting", arguments: [false, true])
    func joinsDiagnostic(afterPosting: Bool) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        _ = board.setString("sentinel", forType: .string)
        var suspended: CheckedContinuation<Void, Never>?
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(pasteboard: board,
            setPasteboardString: { $1.setString($0, forType: .string) }, preflightPostEventAccess: { true },
            secureInputActive: { false }, readModifierFlags: { [] }, makePasteEvents: { baselineFlags in
                return PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
            }, postEvent: { _ in posts += 1 }, sleep: { duration in
                if duration == (afterPosting ? .milliseconds(200) : .milliseconds(100)) {
                    await withCheckedContinuation { suspended = $0 }
                }
            }, nowNanoseconds: { 0 }))
        let command = PasteDiagnosticCommand(environment: [PasteDiagnosticCommand.environmentKey: "1"], pasteService: service)
        command.start()
        command.start()
        #expect(await waitUntil { suspended != nil })
        var finished = false
        let quit = Task { await command.quiesce(); finished = true }
        for _ in 0..<20 { await Task.yield() }
        #expect(!finished)
        suspended?.resume()
        suspended = nil
        await quit.value
        #expect(posts == (afterPosting ? 4 : 0))
        #expect(board.string(forType: .string) == "sentinel")
        command.start()
        for _ in 0..<20 { await Task.yield() }
        #expect(!command.isRunning && suspended == nil)
    }
}
