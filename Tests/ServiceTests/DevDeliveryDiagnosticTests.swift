import AppKit
import Testing
@testable import mrml

@MainActor
private final class ProbeTarget: DevDeliveryDiagnosticTargetChecking {
    var valid = true
    func isStillValid() -> Bool { valid }
}

@MainActor
private final class ProbeFixture {
    let board = NSPasteboard.withUniqueName()
    let target = ProbeTarget()
    let gate = PasteTransactionGate()
    var access = true
    var secure = true
    var modifierFlags: CGEventFlags = []
    var posts: [CGEventType] = []
    var writes: [String] = []
    var acceptsClipboardWrite = true
    var onSleep: (Duration) throws -> Void = { _ in }
    var onMakeEvents: () -> Void = {}

    init() { _ = board.setString("previous clipboard", forType: .string) }

    lazy var service = PasteService(dependencies: PasteServiceDependencies(
        pasteboard: board,
        setPasteboardString: { [self] text, board in
            writes.append(text)
            guard acceptsClipboardWrite else { return false }
            return board.setString(text, forType: .string)
        }, preflightPostEventAccess: { [self] in access }, secureInputActive: { [self] in secure },
        readModifierFlags: { [self] in modifierFlags },
        makePasteEvents: { [self] baselineFlags in
            onMakeEvents()
            return PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
        }, postEvent: { [self] in posts.append($0.type) },
        sleep: { [self] in try onSleep($0) }, nowNanoseconds: { 0 }), transactionGate: gate)

    func run(bundle: String = "com.mrml.app.dev", flag: String? = "1") async -> DevDeliveryDiagnosticResult {
        let environment = flag.map { [DevDeliveryDiagnostic.environmentKey: $0] } ?? [:]
        return await service.runDevDeliveryDiagnostic(target: target, bundleIdentifier: bundle, environment: environment)
    }
}

@MainActor
@Suite("Dev delivery experiment safety")
struct DevDeliveryDiagnosticTests {
    @Test("Diagnostic uses the shared held-modifier guard before any event", arguments: [false, true])
    func modifiersRefuseDiagnostic(afterConstruction: Bool) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        if afterConstruction { f.onMakeEvents = { f.modifierFlags = .maskCommand } }
        else { f.modifierFlags = .maskCommand }

        guard case .completed(let timing) = await f.run() else { Issue.record("Unexpected refusal"); return }

        #expect(timing.commandOutcome == .blocked(.cancelled))
        #expect(f.posts.isEmpty)
        #expect(f.writes.count == (afterConstruction ? 1 : 0))
        #expect(f.board.string(forType: .string) == "previous clipboard")
    }

    @Test("Write rejection preserves the actual security samples without posting")
    func rejectedWritePreservesSamples() async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        f.acceptsClipboardWrite = false
        guard case .completed(let timing) = await f.run() else { Issue.record("Unexpected refusal"); return }
        #expect(timing.commandOutcome == .blocked(.clipboardWriteFailed))
        #expect(timing.postAccessState == true && timing.secureInputState == true)
        #expect(f.posts.isEmpty && f.board.string(forType: .string) == "previous clipboard")
    }

    @Test("Without a captured target, normal delivery remains blocked while the diagnostic can run")
    func experimentDoesNotChangeNormalPolicy() async throws {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        let normal = try await f.service.pasteAndRestore(text: "real dictation")
        #expect(normal.commandOutcome == .blocked(.secureInputActive))
        #expect(f.writes.isEmpty && f.posts.isEmpty)
        guard case .completed(let timing) = await f.run() else { Issue.record("Diagnostic refused"); return }
        #expect(timing.commandOutcome == .posted)
        #expect(timing.secureInputState == true && timing.postAccessState == true)
        #expect(f.posts == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(f.writes == [DevDeliveryDiagnostic.fixedText])
        #expect(f.board.string(forType: .string) == "previous clipboard")
    }

    @Test("Production, other bundles and missing opt-in cannot mutate the clipboard",
          arguments: [("com.mrml.app", "1"), ("other.dev", "1"), ("com.mrml.app.dev", "0")])
    func disabledConfiguration(input: (String, String)) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        let generation = f.board.changeCount
        guard case .refused(.disabled) = await f.run(bundle: input.0, flag: input.1) else {
            Issue.record("Disabled configuration entered probe"); return
        }
        #expect(f.board.changeCount == generation && f.posts.isEmpty && f.writes.isEmpty)
    }

    @Test("Missing flag, invalid target and busy ownership never queue or write", arguments: [0, 1, 2])
    func refusesWithoutMutation(kind: Int) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        if kind == 1 { f.target.valid = false }
        if kind == 2 { #expect(f.gate.tryAcquire()) }
        let generation = f.board.changeCount
        guard case .refused(let refusal) = await f.run(flag: kind == 0 ? nil : "1") else {
            Issue.record("Expected refusal"); return
        }
        #expect(refusal == (kind == 0 ? .disabled : kind == 1 ? .invalidTarget : .busy))
        if kind == 2 { f.gate.release() }
        #expect(f.board.changeCount == generation && f.posts.isEmpty && f.writes.isEmpty)
    }

    @Test("Changed target at either late boundary stops posting and restores owned clipboard", arguments: [false, true])
    func lateTargetChange(duringEventCreation: Bool) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        if duringEventCreation { f.onMakeEvents = { f.target.valid = false } }
        else { f.onSleep = { _ in f.target.valid = false } }
        guard case .completed(let timing) = await f.run() else { Issue.record("Unexpected refusal"); return }
        #expect(timing.commandOutcome == .blocked(.cancelled))
        #expect(f.posts.isEmpty)
        #expect(timing.clipboardDisposition == .restored)
        #expect(f.board.string(forType: .string) == "previous clipboard")
    }

    @Test("Late permission loss, external copy and cancellation cannot post", arguments: [0, 1, 2])
    func lateTransactionGuard(kind: Int) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        f.onSleep = { _ in
            if kind == 0 { f.access = false }
            if kind == 1 { f.board.clearContents(); _ = f.board.setString("external copy", forType: .string) }
            if kind == 2 { throw CancellationError() }
        }
        guard case .completed(let timing) = await f.run() else { Issue.record("Unexpected refusal"); return }
        #expect(timing.commandOutcome == .blocked(kind == 0 ? .postEventAccessDenied : kind == 1 ? .clipboardChanged : .cancelled))
        #expect(timing.secureInputState == true)
        #expect(f.posts.isEmpty)
        #expect(f.board.string(forType: .string) == (kind == 1 ? "external copy" : "previous clipboard"))
    }

    @Test("Cancellation and external copy after posting preserve actual posted outcome", arguments: [false, true])
    func afterPost(cancel: Bool) async {
        let f = ProbeFixture()
        defer { f.board.releaseGlobally() }
        f.onSleep = { duration in
            if duration == .milliseconds(200) {
                if cancel { throw CancellationError() }
                f.board.clearContents(); _ = f.board.setString("external copy", forType: .string)
            }
        }
        guard case .completed(let timing) = await f.run() else { Issue.record("Unexpected refusal"); return }
        #expect(timing.commandOutcome == .posted && timing.secureInputState == true)
        #expect(f.posts == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(f.board.string(forType: .string) == (cancel ? "previous clipboard" : "external copy"))
    }
}
