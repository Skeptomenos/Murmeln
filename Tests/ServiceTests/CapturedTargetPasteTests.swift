import AppKit
import Testing
@testable import mrml

@MainActor
private final class RetainedTarget: PasteTargetChecking {
    var valid = true
    var onCheck: () -> Void = {}
    func isStillValid() -> Bool { onCheck(); return valid }
}

@MainActor
private final class CapturedTargetFixture {
    let board = NSPasteboard.withUniqueName()
    let gate = PasteTransactionGate()
    let target = RetainedTarget()
    var secure = true
    var access = true
    var posts: [CGEventType] = []
    var records: [PasteOperationalRecord] = []
    var writes: [String] = []
    var onSnapshot: () -> Void = {}
    var onSleep: (Duration) throws -> Void = { _ in }
    var onMakeEvents: () -> Void = {}

    init() { _ = board.setString("previous clipboard", forType: .string) }

    lazy var service = PasteService(dependencies: PasteServiceDependencies(
        pasteboard: board,
        captureClipboard: { [self] board in onSnapshot(); return ClipboardSnapshot.capture(from: board) },
        setPasteboardString: { [self] text, board in writes.append(text); return board.setString(text, forType: .string) },
        preflightPostEventAccess: { [self] in access }, secureInputActive: { [self] in secure },
        readModifierFlags: { [] },
        makePasteEvents: { [self] baselineFlags in
            onMakeEvents()
            return PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
        }, postEvent: { [self] in posts.append($0.type) }, sleep: { [self] in try onSleep($0) },
        nowNanoseconds: { 0 }, recordPasteAttempt: { [self] in records.append($0) }), transactionGate: gate)

    func run() async throws -> PasteTiming {
        try await service.pasteAndRestore(text: "dictation", captureID: "capture", target: target)
    }
}

@MainActor
@Suite("Captured target paste transactions")
struct CapturedTargetPasteTests {
    @Test("Failed native Notion capture refuses legacy paste in either Secure Input state", arguments: [false, true])
    func failedNotionCaptureNeverFallsBack(secure: Bool) async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.secure = secure
        let binaryType = NSPasteboard.PasteboardType("app.murmeln.test.notional-binary")
        let first = NSPasteboardItem()
        #expect(first.setString("previous clipboard", forType: .string))
        #expect(first.setData(Data([0, 255, 3, 128]), forType: binaryType))
        let second = NSPasteboardItem()
        #expect(second.setData(Data([4, 0, 254]), forType: binaryType))
        f.board.clearContents()
        #expect(f.board.writeObjects([first, second]))
        let generation = f.board.changeCount
        let before = try #require(f.board.pasteboardItems)
        let beforeTypes = before.map(\.types)
        let beforeBytes = try before.map { item in try item.types.map { try #require(item.data(forType: $0)) } }
        var snapshots = 0
        var makes = 0
        f.onSnapshot = { snapshots += 1 }
        f.onMakeEvents = { makes += 1 }
        let proof = CapturedPasteTarget.select(bundleIdentifier: "notion.id", capturedTarget: nil)
        let service: any PasteServicing = f.service

        let result = try await service.pasteAndRestore(text: "dictation", captureID: "failed-notion-capture", target: proof)

        #expect(proof != nil && proof?.isStillValid() == false)
        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(result.clipboardDisposition == .unchanged)
        #expect(snapshots == 0 && makes == 0 && f.writes.isEmpty && f.posts.isEmpty)
        #expect(f.board.changeCount == generation)
        let after = try #require(f.board.pasteboardItems)
        #expect(after.map(\.types) == beforeTypes)
        #expect(try after.map { item in try item.types.map { try #require(item.data(forType: $0)) } } == beforeBytes)
        #expect(f.records.count == 1)
        let record = try #require(f.records.first)
        #expect(record.captureID == "failed-notion-capture" && record.pasteAttemptID == result.pasteAttemptID)
        #expect(record.commandOutcome == "blocked" && record.blocker == .cancelled)
        #expect(record.clipboardDisposition == .unchanged)
        #expect(record.postAccessState == true && record.secureInputState == secure)
        #expect(result.postAccessState == true && result.secureInputState == secure)
    }

    @Test("PasteServicing dispatch preserves the retained target and real Secure Input telemetry")
    func validTargetUnderSecureInput() async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        let service: any PasteServicing = f.service
        let result = try await service.pasteAndRestore(text: "dictation", captureID: "capture", target: f.target)
        #expect(result.commandOutcome == .posted)
        #expect(result.postAccessState == true && result.secureInputState == true)
        #expect(f.posts == [.flagsChanged, .keyDown, .keyUp, .flagsChanged] && f.writes == ["dictation"])
        #expect(result.clipboardDisposition == .restored)
        #expect(f.board.string(forType: .string) == "previous clipboard")
        #expect(f.records.count == 1)
    }

    @Test("No retained proof keeps the global Secure Input blocker")
    func missingTargetDoesNotWaiveGlobalProtection() async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        let result = try await f.service.pasteAndRestore(text: "dictation", target: nil)
        #expect(result.commandOutcome == .blocked(.secureInputActive))
        #expect(f.writes.isEmpty && f.posts.isEmpty)
    }

    @Test("Invalid retained target never falls back to global policy", arguments: [true, false])
    func invalidTargetBlocksRegardlessOfGlobalState(secure: Bool) async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.secure = secure; f.target.valid = false
        let generation = f.board.changeCount
        let result = try await f.run()
        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(f.writes.isEmpty && f.posts.isEmpty && f.board.changeCount == generation)
    }

    @Test("Target change during clipboard snapshot cannot mutate it")
    func targetChangesBeforeClipboardMutation() async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.onSnapshot = { f.target.valid = false }
        let generation = f.board.changeCount
        let result = try await f.run()
        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(f.writes.isEmpty && f.posts.isEmpty && f.board.changeCount == generation)
    }

    @Test("Late target loss blocks even when Secure Input clears", arguments: [false, true])
    func targetChangesBeforePost(duringEvents: Bool) async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        let invalidate = { f.target.valid = false; f.secure = false }
        if duringEvents { f.onMakeEvents = invalidate }
        else { f.onSleep = { _ in invalidate() } }
        let result = try await f.run()
        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(result.clipboardDisposition == .restored && result.secureInputState == false)
        #expect(f.posts.isEmpty && f.board.string(forType: .string) == "previous clipboard")
    }

    @Test("Retained proof cannot waive permission, external copy or cancellation", arguments: [0, 1, 2])
    func mandatoryLateGuards(kind: Int) async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.onSleep = { _ in
            if kind == 0 { f.access = false }
            if kind == 1 { f.board.clearContents(); _ = f.board.setString("external", forType: .string) }
            if kind == 2 { throw CancellationError() }
        }
        let result = try await f.run()
        #expect(result.commandOutcome == .blocked(kind == 0 ? .postEventAccessDenied : kind == 1 ? .clipboardChanged : .cancelled))
        #expect(f.posts.isEmpty && result.secureInputState == true)
        #expect(f.board.string(forType: .string) == (kind == 1 ? "external" : "previous clipboard"))
    }

    @Test("A clipboard write during the final AX validation is preserved")
    func externalCopyDuringFinalTargetCheck() async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.target.onCheck = {
            if f.board.string(forType: .string) == "dictation" {
                f.board.clearContents(); _ = f.board.setString("external", forType: .string)
            }
        }
        let result = try await f.run()
        #expect(result.commandOutcome == .blocked(.clipboardChanged))
        #expect(f.posts.isEmpty && f.board.string(forType: .string) == "external")
    }

    @Test("Busy retained-target delivery refuses instead of queuing")
    func busyDoesNotQueue() async throws {
        let f = CapturedTargetFixture()
        defer { f.board.releaseGlobally() }
        f.secure = false
        #expect(f.gate.tryAcquire())
        var finished = false
        let request = Task { let result = try await f.run(); finished = true; return result }
        for _ in 0..<20 { await Task.yield() }
        let completedBeforeRelease = finished
        f.gate.release()
        let result = try await request.value
        #expect(completedBeforeRelease)
        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(f.writes.isEmpty && f.posts.isEmpty)
    }
}
