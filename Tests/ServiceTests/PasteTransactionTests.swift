import AppKit
import Testing
@testable import mrml

@Suite("Paste Service Dependency Tests")
@MainActor
struct PasteServiceDependencyTests {
    @Test("Early cancellation records once without sampling OS state", arguments: ["targeted", "legacy", "waiting", "admitted"])
    func earlyCancellationIsRecorded(mode: String) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var records: [PasteOperationalRecord] = []
        var samples = 0
        var clockReads = 0
        var started = false
        let gate = PasteTransactionGate()
        if mode == "waiting" { #expect(gate.tryAcquire()) }
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, captureClipboard: { board in samples += 1; return ClipboardSnapshot.capture(from: board) },
            setPasteboardString: { _, _ in samples += 1; return false },
            preflightPostEventAccess: { samples += 1; return false },
            secureInputActive: { samples += 1; return false }, readModifierFlags: { samples += 1; return [] },
            makePasteEvents: { _ in samples += 1; return nil }, postEvent: { _ in samples += 1 },
            sleep: { _ in }, nowNanoseconds: {
                clockReads += 1
                if mode == "admitted", clockReads == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                return 0
            }, makePasteAttemptID: { "early-attempt" },
            recordPasteAttempt: { records.append($0) }), transactionGate: gate)
        let task = Task { @MainActor in
            started = true
            if mode == "targeted" || mode == "legacy" { withUnsafeCurrentTask { $0?.cancel() } }
            do {
                _ = try await service.pasteAndRestore(text: "dictation", captureID: "early-capture",
                    target: mode == "targeted" ? UnverifiedPasteTarget(reason: .initialCaptureUnverifiable) : nil)
                Issue.record("Cancellation must still throw")
            } catch is CancellationError {} catch { Issue.record("Unexpected error") }
        }
        if mode == "waiting" {
            while !started { await Task.yield() }
            task.cancel()
        }
        await task.value
        if mode == "waiting" {
            #expect(!gate.tryAcquire(), "Cancelled waiter must not release another transaction's gate")
            gate.release()
        }
        #expect(samples == 0)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.captureID == "early-capture" && record.pasteAttemptID == "early-attempt")
        #expect(record.decision?.stage == (mode == "admitted" ? .initialPreflight : .admission) && record.decision?.reason == .taskCancelled)
        #expect(record.postAccessState == nil && record.secureInputState == nil)
        #expect(try JSONDecoder().decode(PasteOperationalRecord.self, from: JSONEncoder().encode(record)) == record)
        #expect(gate.tryAcquire())
        gate.release()
    }

    @Test("Mouse coalescing changes do not cancel keyboard delivery", arguments: [false, true], [false, true])
    func nonCoalescedChangeAllowsPaste(beforeWrite: Bool, removesFlag: Bool) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.setString("sentinel", forType: .string))
        let baseline: CGEventFlags = removesFlag ? .maskNonCoalesced : []
        let changed: CGEventFlags = removesFlag ? [] : .maskNonCoalesced
        var flags = baseline
        var posts = 0
        var modifierReads = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, captureClipboard: { board in
                let snapshot = ClipboardSnapshot.capture(from: board)
                if beforeWrite { flags = changed }
                return snapshot
            }, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { modifierReads += 1; return flags },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { duration in
                if duration == .milliseconds(100), !beforeWrite { flags = changed }
            }, nowNanoseconds: { 0 }))
        #expect(PasteServiceDependencies.modifiersPermitPaste([]))
        #expect(PasteServiceDependencies.modifiersPermitPaste(.maskNonCoalesced))

        let timing = try await service.pasteAndRestore(text: "dictation")

        #expect(timing.commandOutcome == .posted && timing.clipboardDisposition == .restored)
        #expect(timing.decision?.stage == .posted && timing.decision?.reason == .commandPosted)
        #expect(timing.decision?.modifiers == PasteModifierObservation(before: baseline.rawValue, atDecision: changed.rawValue))
        #expect(modifierReads == 3 && posts == 4 && board.string(forType: .string) == "sentinel")
    }

    @Test("Mouse coalescing changes cannot hide other flag changes", arguments: [false, true], [
        CGEventFlags.maskShift.rawValue, CGEventFlags.maskSecondaryFn.rawValue,
        CGEventFlags.maskAlphaShift.rawValue, CGEventFlags.maskNumericPad.rawValue,
        CGEventFlags.maskHelp.rawValue, UInt64(1) << 40
    ])
    func nonCoalescedChangeCannotHideOtherFlags(beforeWrite: Bool, otherFlag: UInt64) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.setString("sentinel", forType: .string))
        let changed = CGEventFlags(rawValue: otherFlag).union(.maskNonCoalesced)
        var flags: CGEventFlags = []
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, captureClipboard: { board in
                let snapshot = ClipboardSnapshot.capture(from: board)
                if beforeWrite { flags = changed }
                return snapshot
            }, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { flags },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { duration in
                if duration == .milliseconds(100), !beforeWrite { flags = changed }
            }, nowNanoseconds: { 0 }))

        let timing = try await service.pasteAndRestore(text: "dictation")

        #expect(timing.commandOutcome == .blocked(.cancelled))
        #expect(timing.clipboardDisposition == (beforeWrite ? .unchanged : .restored))
        #expect(timing.decision?.stage == (beforeWrite ? .beforeWrite : .beforePost))
        #expect(timing.decision?.reason == .modifiersChanged)
        #expect(timing.decision?.modifiers == PasteModifierObservation(before: 0, atDecision: changed.rawValue))
        #expect(posts == 0 && board.string(forType: .string) == "sentinel")
    }

    @Test("Restored cancellation records distinguish settle cancellation from changed modifiers", arguments: [false, true])
    func restoredCancellationRecordsExactDecision(cancelDuringSettle: Bool) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        #expect(board.setString("sentinel", forType: .string))
        var flags: CGEventFlags = []
        var posts = 0
        var records: [PasteOperationalRecord] = []
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { flags },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { duration in
                if duration == .milliseconds(100) {
                    if cancelDuringSettle { throw CancellationError() }
                    flags = .maskCommand
                }
            }, nowNanoseconds: { 0 }, makePasteAttemptID: { "decision-attempt" },
            recordPasteAttempt: { records.append($0) }))

        let timing = try await service.pasteAndRestore(text: "dictation", captureID: "decision-capture")

        #expect(timing.commandOutcome == .blocked(.cancelled))
        #expect(timing.clipboardDisposition == .restored)
        #expect(posts == 0 && board.string(forType: .string) == "sentinel")
        let record = try #require(records.first)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        #expect(json["decision_stage"] as? String == (cancelDuringSettle ? "settle" : "before_post"))
        #expect(json["decision_reason"] as? String == (cancelDuringSettle ? "task_cancelled" : "modifiers_changed"))
        #expect(json["target_policy"] as? String == "legacy")
        #expect(record.captureID == "decision-capture" && record.pasteAttemptID == "decision-attempt")
    }

    @Test("Production paste event factory closes its Command modifier chord without posting")
    func productionFactoryClosesCommandChord() throws {
        let events = try #require(PasteServiceDependencies.live.makePasteEvents([]))
        let sequence = events.ordered

        #expect(sequence.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(sequence.last?.flags.contains(.maskCommand) == false)
        #expect(sequence.map { $0.getIntegerValueField(.eventSourceStateID) } == Array(repeating: Int64(CGEventSourceStateID.combinedSessionState.rawValue), count: 4))
        #expect(sequence.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 })
    }

    @Test("Production constructor preserves the allowed baseline around the resolved paste key", arguments: [UInt64(0), CGEventFlags.maskAlphaShift.rawValue, CGEventFlags.maskAlphaShift.union(.maskNonCoalesced).rawValue])
    func constructorPreservesBaseline(rawFlags: UInt64) throws {
        let baseline = CGEventFlags(rawValue: rawFlags)
        let events = try #require(PasteServiceDependencies.makeCommandPasteEvents(keyCode: 14, baselineFlags: baseline))

        #expect(events.ordered.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [55, 14, 14, 55])
        #expect(events.ordered.map(\.flags) == [baseline.union(.maskCommand), baseline.union(.maskCommand), baseline.union(.maskCommand), baseline])
    }

    @Test("Production constructor refuses unsafe modifiers without creating a release", arguments: [CGEventFlags.maskCommand.rawValue, CGEventFlags.maskControl.rawValue, CGEventFlags.maskAlternate.rawValue, CGEventFlags.maskShift.rawValue, CGEventFlags.maskSecondaryFn.rawValue])
    func constructorRefusesHeldModifiers(rawFlags: UInt64) {
        #expect(PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: CGEventFlags(rawValue: rawFlags)) == nil)
    }

    @Test("Targetless paste refuses held modifiers before clipboard access", arguments: [CGEventFlags.maskCommand.rawValue, CGEventFlags.maskControl.rawValue, CGEventFlags.maskAlternate.rawValue, CGEventFlags.maskShift.rawValue, CGEventFlags.maskSecondaryFn.rawValue])
    func heldModifiersRefuseBeforeClipboard(rawFlags: UInt64) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        let generation = board.changeCount
        var snapshots = 0
        var writes = 0
        var makes = 0
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board,
            captureClipboard: { board in snapshots += 1; return ClipboardSnapshot.capture(from: board) },
            setPasteboardString: { text, board in writes += 1; return board.setString(text, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { CGEventFlags(rawValue: rawFlags) },
            makePasteEvents: { flags in makes += 1; return PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: flags) },
            postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }))

        let result = try await service.pasteAndRestore(text: "dictation")

        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(result.clipboardDisposition == .unchanged)
        #expect(snapshots == 0 && writes == 0 && makes == 0 && posts == 0)
        #expect(board.changeCount == generation)
    }

    @Test("Changed modifiers cancel before the first event and restore the clipboard", arguments: ["settle-command", "construction-command", "construction-caps-lock"])
    func modifierChangeBeforePostingCancels(stage: String) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        var flags: CGEventFlags = []
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { flags },
            makePasteEvents: { baseline in
                let events = PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baseline)
                if stage == "construction-command" { flags = .maskCommand }
                if stage == "construction-caps-lock" { flags = .maskAlphaShift }
                return events
            }, postEvent: { _ in posts += 1 }, sleep: { duration in
                if duration == .milliseconds(100), stage == "settle-command" { flags = .maskCommand }
            }, nowNanoseconds: { 0 }))

        let result = try await service.pasteAndRestore(text: "dictation")

        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(result.clipboardDisposition == .restored)
        #expect(posts == 0 && board.string(forType: .string) == "sentinel")
    }

    @Test("Final modifier sampling cannot bypass clipboard ownership or cancellation", arguments: [false, true])
    func finalModifierSampleCannotBypassLastChecks(externalClipboardWrite: Bool) async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        var modifierSamples = 0
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: {
                modifierSamples += 1
                if modifierSamples == 3 {
                    if externalClipboardWrite {
                        board.clearContents()
                        #expect(board.setString("external copy", forType: .string))
                    } else {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
                return []
            }, makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }))
        let operation = Task { try await service.pasteAndRestore(text: "dictation") }

        let result = try await operation.value

        #expect(modifierSamples == 3)
        #expect(posts == 0)
        #expect(result.commandOutcome == .blocked(externalClipboardWrite ? .clipboardChanged : .cancelled))
        #expect(result.clipboardDisposition == (externalClipboardWrite ? .externalWritePreserved : .restored))
        #expect(board.string(forType: .string) == (externalClipboardWrite ? "external copy" : "sentinel"))
    }

    @Test("Modifier change during snapshot materialization refuses before clipboard mutation")
    func snapshotModifierChangeRefusesBeforeWrite() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        let generation = board.changeCount
        var flags: CGEventFlags = []
        var writes = 0
        var makes = 0
        var posts = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, captureClipboard: { board in
                let snapshot = ClipboardSnapshot.capture(from: board)
                flags = .maskShift
                return snapshot
            }, setPasteboardString: { text, board in writes += 1; return board.setString(text, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { flags },
            makePasteEvents: { flags in makes += 1; return PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: flags) },
            postEvent: { _ in posts += 1 }, sleep: { _ in }, nowNanoseconds: { 0 }))

        let result = try await service.pasteAndRestore(text: "dictation")

        #expect(result.commandOutcome == .blocked(.cancelled))
        #expect(result.clipboardDisposition == .unchanged)
        #expect(writes == 0 && makes == 0 && posts == 0)
        #expect(board.changeCount == generation && board.string(forType: .string) == "sentinel")
    }

    @Test("Transaction passes the actual allowed baseline to the production constructor")
    func transactionPreservesCapsLock() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        var posted: [CGEventFlags] = []
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false }, readModifierFlags: { .maskAlphaShift },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { posted.append($0.flags) }, sleep: { _ in }, nowNanoseconds: { 0 }))

        let result = try await service.pasteAndRestore(text: "dictation")

        #expect(result.commandOutcome == .posted)
        #expect(posted == [.maskAlphaShift.union(.maskCommand), .maskAlphaShift.union(.maskCommand), .maskAlphaShift.union(.maskCommand), .maskAlphaShift])
    }

    @Test("Cancellation after the first event cannot interrupt the owned modifier release")
    func cancellationDuringChordStillReleasesCommand() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        _ = board.setString("sentinel", forType: .string)
        var posted: [CGEvent] = []
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: board, setPasteboardString: { $1.setString($0, forType: .string) },
            preflightPostEventAccess: { true }, secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: $0) },
            postEvent: { event in
                posted.append(event)
                if posted.count == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }, sleep: { _ in }, nowNanoseconds: { 0 }))
        let operation = Task { try await service.pasteAndRestore(text: "dictation") }

        let result = try await operation.value

        #expect(result.commandOutcome == .posted)
        #expect(posted.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(posted.last?.flags.contains(.maskCommand) == false)
        #expect(board.string(forType: .string) == "sentinel")
    }

    @Test("Injected boundaries drive a complete transaction without posting globally")
    func injectedBoundariesDriveTransaction() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var timestamps: [UInt64] = [10_000_000, 11_000_000, 12_000_000]
        var sleepDurations: [Duration] = []
        var postedEvents: [(type: CGEventType, flags: CGEventFlags)] = []
        var callOrder: [String] = []
        var operationalRecord: PasteOperationalRecord?

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                callOrder.append("write-transcript")
                return pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: {
                callOrder.append("post-access")
                return true
            },
            secureInputActive: {
                callOrder.append("secure-input")
                return false
            },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                callOrder.append("make-events")
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            },
            postEvent: { event in
                callOrder.append(event.type == .flagsChanged ? (event.flags.contains(.maskCommand) ? "post-command-down" : "post-command-up") : (event.type == .keyDown ? "post-down" : "post-up"))
                postedEvents.append((event.type, event.flags))
            },
            sleep: { duration in
                callOrder.append(duration == .milliseconds(100) ? "settle" : "restore-delay")
                sleepDurations.append(duration)
            },
            nowNanoseconds: {
                timestamps.removeFirst()
            },
            makePasteAttemptID: { "attempt-posted" },
            recordPasteAttempt: { operationalRecord = $0 }
        ))

        let timing = try await service.pasteAndRestore(text: "transaction text", captureID: "slice-0")

        #expect(timing.commandOutcome == .posted)
        #expect(timing.clipboardDisposition == .restored)
        #expect(timing.commandSentElapsedMs == 1)
        #expect(timing.totalElapsedMs == 2)
        #expect(timing.pasteAttemptID == "attempt-posted")
        #expect(timing.postAccessState == true)
        #expect(timing.secureInputState == false)
        #expect(operationalRecord?.captureID == "slice-0")
        #expect(operationalRecord?.commandOutcome == "posted")
        #expect(operationalRecord?.level == "info")
        #expect(sleepDurations == [.milliseconds(100), .milliseconds(200)])
        #expect(callOrder == [
            "post-access",
            "secure-input",
            "write-transcript",
            "settle",
            "make-events",
            "post-access",
            "secure-input",
            "post-command-down",
            "post-down",
            "post-up",
            "post-command-up",
            "restore-delay"
        ])
        #expect(postedEvents.map(\.type) == [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        #expect(postedEvents.dropLast().allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(postedEvents.last?.flags.contains(.maskCommand) == false)
        #expect(pasteboard.string(forType: .string) == "sentinel")
    }

    @Test("Injected event-access denial blocks without creating or posting events")
    func injectedEventAccessDenialBlocks() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var makeEventsCallCount = 0
        var postCallCount = 0
        var sleepCallCount = 0
        var timestamps: [UInt64] = [20_000_000, 21_000_000]

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: { false },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                makeEventsCallCount += 1
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in sleepCallCount += 1 },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "manual recovery", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.postEventAccessDenied))
        #expect(timing.clipboardDisposition == .unchanged)
        #expect(timing.commandSentElapsedMs == nil)
        #expect(timing.pasteAttemptID != nil)
        #expect(timing.postAccessState == false)
        #expect(timing.secureInputState == false)
        #expect(makeEventsCallCount == 0)
        #expect(postCallCount == 0)
        #expect(sleepCallCount == 0)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("Injected Secure Input blocks without creating or posting events")
    func injectedSecureInputBlocks() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var makeEventsCallCount = 0
        var postCallCount = 0
        var sleepCallCount = 0
        var timestamps: [UInt64] = [30_000_000, 31_000_000, 32_000_000]

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: { true },
            secureInputActive: { true },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                makeEventsCallCount += 1
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in sleepCallCount += 1 },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "secure recovery", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.secureInputActive))
        #expect(timing.clipboardDisposition == .unchanged)
        #expect(timing.commandSentElapsedMs == nil)
        #expect(timing.pasteAttemptID != nil)
        #expect(timing.postAccessState == true)
        #expect(timing.secureInputState == true)
        #expect(makeEventsCallCount == 0)
        #expect(postCallCount == 0)
        #expect(sleepCallCount == 0)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("Event-post denial takes precedence when Secure Input is also active")
    func eventPostDenialPrecedesSecureInput() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var secureInputCallCount = 0
        var makeEventsCallCount = 0
        var postCallCount = 0
        var sleepCallCount = 0
        var timestamps: [UInt64] = [35_000_000, 36_000_000]

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: { false },
            secureInputActive: {
                secureInputCallCount += 1
                return true
            },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                makeEventsCallCount += 1
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in sleepCallCount += 1 },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "permission first", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.postEventAccessDenied))
        #expect(timing.clipboardDisposition == .unchanged)
        #expect(timing.commandSentElapsedMs == nil)
        #expect(timing.postAccessState == false)
        #expect(timing.secureInputState == true)
        #expect(secureInputCallCount == 1)
        #expect(makeEventsCallCount == 0)
        #expect(postCallCount == 0)
        #expect(sleepCallCount == 0)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("Injected clipboard write rejection restores the prior clipboard and stops before event creation")
    func injectedClipboardWriteRejectionRestoresPriorClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var preflightCallCount = 0
        var secureInputCallCount = 0
        var makeEventsCallCount = 0
        var postCallCount = 0
        var sleepCallCount = 0
        var timestamps: [UInt64] = [37_000_000, 38_000_000]

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { _, _ in false },
            preflightPostEventAccess: {
                preflightCallCount += 1
                return true
            },
            secureInputActive: {
                secureInputCallCount += 1
                return false
            },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in
                makeEventsCallCount += 1
                return makeCommandPasteEvents(baselineFlags: baselineFlags)
            },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in sleepCallCount += 1 },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "must remain recoverable", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.clipboardWriteFailed))
        #expect(timing.clipboardDisposition == .restored)
        #expect(timing.commandSentElapsedMs == nil)
        #expect(timing.postAccessState == true)
        #expect(timing.secureInputState == false)
        #expect(preflightCallCount == 1)
        #expect(secureInputCallCount == 1)
        #expect(makeEventsCallCount == 0)
        #expect(postCallCount == 0)
        #expect(sleepCallCount == 0)
        #expect(pasteboard.string(forType: .string) == "sentinel")
    }

    @Test("Copy Again retries the checked clipboard write without posting events")
    func copyAgainRetriesClipboardWriteOnly() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("old", forType: .string))

        var writtenTexts: [String] = []
        var preflightCallCount = 0
        var postCallCount = 0

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                writtenTexts.append(text)
                return pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: {
                preflightCallCount += 1
                return true
            },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in },
            nowNanoseconds: { 0 }
        ))

        let copied = service.copyToClipboardForRecovery(text: "recover me")

        #expect(copied)
        #expect(writtenTexts == ["recover me"])
        #expect(pasteboard.string(forType: .string) == "recover me")
        #expect(preflightCallCount == 0)
        #expect(postCallCount == 0)
    }

    @Test("Injected Copy Again rejection preserves the prior clipboard")
    func injectedCopyAgainRejectionPreservesPriorClipboard() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("keep me", forType: .string))

        var writtenTexts: [String] = []
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, _ in
                writtenTexts.append(text)
                return false
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { 0 }
        ))

        let copied = service.copyToClipboardForRecovery(text: "still recoverable")

        #expect(copied == false)
        #expect(writtenTexts == ["still recoverable"])
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test("Failed Copy Again does not overwrite a new pasteboard owner")
    func failedCopyAgainPreservesNewPasteboardOwner() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("old", forType: .string))

        var restoreCallCount = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { _, pasteboard in
                pasteboard.clearContents()
                #expect(pasteboard.setString("new owner", forType: .string))
                return false
            },
            restoreClipboard: { snapshot, pasteboard in
                restoreCallCount += 1
                return snapshot.restoreOutcome(to: pasteboard)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { 0 }
        ))

        let copied = service.copyToClipboardForRecovery(text: "recover me")

        #expect(copied == false)
        #expect(restoreCallCount == 0)
        #expect(pasteboard.string(forType: .string) == "new owner")
    }

    @Test("Injected event-creation failure stays distinct from event posting")
    func injectedEventCreationFailureBlocks() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var postCallCount = 0
        var sleepCallCount = 0
        var timestamps: [UInt64] = [40_000_000, 41_000_000, 42_000_000]

        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { _ in nil },
            postEvent: { _ in postCallCount += 1 },
            sleep: { _ in sleepCallCount += 1 },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "creation recovery", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.keyEventCreationFailed))
        #expect(timing.clipboardDisposition == .restored)
        #expect(timing.commandSentElapsedMs == nil)
        #expect(timing.postAccessState == true)
        #expect(timing.secureInputState == false)
        #expect(postCallCount == 0)
        #expect(sleepCallCount == 1)
        #expect(pasteboard.string(forType: .string) == nil)
    }

    @Test("Posted command reports a failed clipboard restore without changing command outcome")
    func postedCommandReportsRestoreFailure() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var restoreCallCount = 0
        var timestamps: [UInt64] = [50_000_000, 51_000_000, 52_000_000]
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            restoreClipboard: { _, _ in
                restoreCallCount += 1
                return .restoreFailed
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "posted text", captureID: nil)

        #expect(restoreCallCount == 1)
        #expect(timing.commandOutcome == .posted)
        #expect(timing.clipboardDisposition == .restoreFailed)
    }

    @Test("An empty saved clipboard is restored after the posted command")
    func emptySavedClipboardIsRestored() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        var postedEvents = 0
        var timestamps: [UInt64] = [55_000_000, 56_000_000, 57_000_000]
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postedEvents += 1 },
            sleep: { _ in },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "kept transcript", captureID: nil)

        #expect(postedEvents == 4)
        #expect(timing.commandOutcome == .posted)
        #expect(timing.clipboardDisposition == .restored)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
    }

    @Test("Clipboard write blocker reports a failed prior-clipboard restore")
    func clipboardWriteBlockerReportsRestoreFailure() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var timestamps: [UInt64] = [58_000_000, 59_000_000]
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { _, _ in false },
            restoreClipboard: { _, _ in .restoreFailed },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "unwritten transcript", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.clipboardWriteFailed))
        #expect(timing.clipboardDisposition == .restoreFailed)
        #expect(timing.commandSentElapsedMs == nil)
    }

    @Test("Clipboard write failure does not restore over a new pasteboard owner")
    func clipboardWriteFailurePreservesNewPasteboardOwner() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var restoreCallCount = 0
        var timestamps: [UInt64] = [59_500_000, 60_500_000]
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { _, pasteboard in
                pasteboard.clearContents()
                #expect(pasteboard.setString("new owner", forType: .string))
                return false
            },
            restoreClipboard: { snapshot, pasteboard in
                restoreCallCount += 1
                return snapshot.restoreOutcome(to: pasteboard)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "unwritten transcript", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.clipboardWriteFailed))
        #expect(timing.clipboardDisposition == .externalWritePreserved)
        #expect(restoreCallCount == 0)
        #expect(pasteboard.string(forType: .string) == "new owner")
    }

    @Test("Blocked attempt preserves a newer external clipboard write")
    func blockedAttemptPreservesExternalClipboardWrite() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var timestamps: [UInt64] = [60_000_000, 61_000_000]
        var checks = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in pasteboard.setString(text, forType: .string) },
            preflightPostEventAccess: {
                checks += 1
                if checks == 1 { return true }
                pasteboard.clearContents()
                #expect(pasteboard.setString("external copy", forType: .string))
                return false
            },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: { timestamps.removeFirst() }
        ))

        let timing = try await service.pasteAndRestore(text: "transcript", captureID: nil)

        #expect(timing.commandOutcome == .blocked(.postEventAccessDenied))
        #expect(timing.clipboardDisposition == .externalWritePreserved)
        #expect(pasteboard.string(forType: .string) == "external copy")
    }

    private func makeCommandPasteEvents(baselineFlags: CGEventFlags = []) -> PasteServiceDependencies.PasteEvents? {
        PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
    }
}
