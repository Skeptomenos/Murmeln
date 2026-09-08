import AppKit
import Testing
@testable import mrml

@Suite("Paste Service Integration Tests")
@MainActor
struct PasteServiceIntegrationTests {
    @Test("A multi-item snapshot restores in one checked pasteboard batch")
    func multiItemSnapshotRestoresInOneBatch() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let first = NSPasteboardItem()
        let second = NSPasteboardItem()
        #expect(first.setString("first", forType: .string))
        #expect(second.setString("second", forType: .string))
        pasteboard.clearContents()
        #expect(pasteboard.writeObjects([first, second]))
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        #expect(pasteboard.setString("replacement", forType: .string))
        var writeBatches: [[String]] = []

        let restored = snapshot.restore(to: pasteboard, writeObjects: { items, pasteboard in
            writeBatches.append(items.compactMap { $0.string(forType: .string) })
            return pasteboard.writeObjects(items)
        })
        #expect(restored)
        #expect(writeBatches == [["first", "second"]])
        #expect(pasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) } == ["first", "second"])
    }

    @Test("Empty clipboard is restored after the target reads each of 20 posted transcripts")
    func emptyClipboardRestoresAfterRepeatedPosts() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var fakeTargetReads: [String] = []
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                if duration == .milliseconds(200),
                   let transcript = pasteboard.string(forType: .string) {
                    fakeTargetReads.append(transcript)
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        for iteration in 0..<20 {
            pasteboard.clearContents()
            let transcript = "empty-clipboard-\(iteration)"

            let timing = try await service.pasteAndRestore(text: transcript, captureID: nil)

            #expect(timing.commandOutcome == .posted)
            #expect(timing.clipboardDisposition == .restored)
            #expect(pasteboard.string(forType: .string) == nil)
            #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
        }

        #expect(fakeTargetReads == (0..<20).map { "empty-clipboard-\($0)" })
    }

    @Test("Twenty sequential pairs reach the target in order and restore the sentinel")
    func repeatedSequentialTransactionsPreserveOrder() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var fakeTargetReads: [String] = []
        var postAccessChecks = 0
        var secureInputChecks = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: {
                postAccessChecks += 1
                return true
            },
            secureInputActive: {
                secureInputChecks += 1
                return false
            },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                if duration == .milliseconds(200),
                   let transcript = pasteboard.string(forType: .string) {
                    fakeTargetReads.append(transcript)
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        var expectedReads: [String] = []
        for iteration in 0..<20 {
            for prefix in ["one", "two"] {
                let transcript = "\(prefix)-\(iteration)"
                expectedReads.append(transcript)

                let timing = try await service.pasteAndRestore(text: transcript, captureID: nil)

                #expect(timing.commandOutcome == .posted)
                #expect(timing.clipboardDisposition == .restored)
                #expect(pasteboard.string(forType: .string) == "sentinel")
            }
        }

        #expect(fakeTargetReads == expectedReads)
        #expect(postAccessChecks == 80)
        #expect(secureInputChecks == 80)
    }

    @Test("Each request rechecks current Secure Input state")
    func eachRequestRechecksSecureInput() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        var secureInputStates = [false, false, true, false, false]
        var postCount = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { secureInputStates.removeFirst() },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postCount += 1 },
            sleep: { _ in },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        let first = try await service.pasteAndRestore(text: "first", captureID: nil)
        let second = try await service.pasteAndRestore(text: "second", captureID: nil)
        let third = try await service.pasteAndRestore(text: "third", captureID: nil)

        #expect(first.commandOutcome == .posted)
        #expect(second.commandOutcome == .blocked(.secureInputActive))
        #expect(third.commandOutcome == .posted)
        #expect(postCount == 8)
        #expect(secureInputStates.isEmpty)
    }

    @Test("A posted command preserves a clipboard write made during the target-read window")
    func postedCommandPreservesExternalClipboardWrite() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var fakeTargetRead: String?
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                guard duration == .milliseconds(200) else { return }
                fakeTargetRead = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                #expect(pasteboard.setString("external copy", forType: .string))
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        let timing = try await service.pasteAndRestore(text: "transcript", captureID: nil)

        #expect(fakeTargetRead == "transcript")
        #expect(timing.commandOutcome == .posted)
        #expect(timing.clipboardDisposition == .externalWritePreserved)
        #expect(pasteboard.string(forType: .string) == "external copy")
    }

    @Test("Overlapping requests serialize the complete clipboard transaction")
    func overlappingRequestsSerializeCompleteTransaction() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var writtenTranscripts: [String] = []
        var fakeTargetReads: [String] = []
        var firstRestoreDelay: CheckedContinuation<Void, Never>?
        var restoreDelayCount = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                writtenTranscripts.append(text)
                return pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                guard duration == .milliseconds(200) else { return }
                restoreDelayCount += 1
                if let transcript = pasteboard.string(forType: .string) {
                    fakeTargetReads.append(transcript)
                }
                if restoreDelayCount == 1 {
                    await withCheckedContinuation { continuation in
                        firstRestoreDelay = continuation
                    }
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        let firstTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "one", captureID: nil)
        }
        await yieldUntil { firstRestoreDelay != nil }

        let secondTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "two", captureID: nil)
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        let writesBeforeFirstTransactionFinished = writtenTranscripts

        firstRestoreDelay?.resume()
        firstRestoreDelay = nil
        let first = try await firstTask.value
        let second = try await secondTask.value

        #expect(writesBeforeFirstTransactionFinished == ["one"])
        #expect(first.commandOutcome == .posted)
        #expect(first.clipboardDisposition == .restored)
        #expect(second.commandOutcome == .posted)
        #expect(second.clipboardDisposition == .restored)
        #expect(fakeTargetReads == ["one", "two"])
        #expect(pasteboard.string(forType: .string) == "sentinel")
    }

    @Test("Cancellation before posting restores the clipboard and posts nothing")
    func cancellationBeforePostingRestoresWithoutPosting() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var settleDelay: CheckedContinuation<Void, Never>?
        var postCount = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postCount += 1 },
            sleep: { duration in
                if duration == .milliseconds(100) {
                    await withCheckedContinuation { continuation in
                        settleDelay = continuation
                    }
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        let task = Task { @MainActor in
            try await service.pasteAndRestore(text: "cancel me", captureID: nil)
        }
        await yieldUntil { settleDelay != nil }
        task.cancel()
        settleDelay?.resume()
        settleDelay = nil
        let result = await task.result

        #expect(postCount == 0)
        #expect(pasteboard.string(forType: .string) == "sentinel")
        #expect(try result.get().commandOutcome == .blocked(.cancelled))
    }

    @Test("Cancellation after posting restores an originally empty clipboard")
    func cancellationAfterPostingRestoresEmptyClipboard() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()

        var restoreDelay: CheckedContinuation<Void, Never>?
        var postCount = 0
        var operationalRecords: [PasteOperationalRecord] = []
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postCount += 1 },
            sleep: { duration in
                if duration == .milliseconds(200) {
                    await withCheckedContinuation { continuation in
                        restoreDelay = continuation
                    }
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            },
            makePasteAttemptID: { "attempt-cancelled-after-post" },
            recordPasteAttempt: { operationalRecords.append($0) }
        ))

        let task = Task { @MainActor in
            try await service.pasteAndRestore(text: "cancel after post", captureID: nil)
        }
        await yieldUntil { restoreDelay != nil }
        #expect(postCount == 4)
        task.cancel()
        restoreDelay?.resume()
        restoreDelay = nil
        let result = await task.result

        #expect(pasteboard.string(forType: .string) == nil)
        #expect(pasteboard.pasteboardItems?.isEmpty ?? true)
        #expect(operationalRecords.count == 1)
        #expect(operationalRecords.first?.pasteAttemptID == "attempt-cancelled-after-post")
        #expect(operationalRecords.first?.commandOutcome == "posted")
        #expect(operationalRecords.first?.clipboardDisposition == .restored)
        #expect(try result.get().commandOutcome == .posted)
    }

    @Test("Cancellation cleanup does not overwrite a newer clipboard write")
    func cancellationCleanupPreservesExternalClipboardWrite() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var restoreDelay: CheckedContinuation<Void, Never>?
        var fakeTargetRead: String?
        var operationalRecords: [PasteOperationalRecord] = []
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                guard duration == .milliseconds(200) else { return }
                fakeTargetRead = pasteboard.string(forType: .string)
                pasteboard.clearContents()
                #expect(pasteboard.setString("external copy", forType: .string))
                await withCheckedContinuation { continuation in
                    restoreDelay = continuation
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            },
            makePasteAttemptID: { "attempt-cancelled-external" },
            recordPasteAttempt: { operationalRecords.append($0) }
        ))

        let task = Task { @MainActor in
            try await service.pasteAndRestore(text: "cancel after external copy", captureID: nil)
        }
        await yieldUntil { restoreDelay != nil }
        task.cancel()
        restoreDelay?.resume()
        restoreDelay = nil
        let result = await task.result

        #expect(fakeTargetRead == "cancel after external copy")
        #expect(pasteboard.string(forType: .string) == "external copy")
        #expect(operationalRecords.count == 1)
        #expect(operationalRecords.first?.pasteAttemptID == "attempt-cancelled-external")
        #expect(operationalRecords.first?.commandOutcome == "posted")
        #expect(operationalRecords.first?.clipboardDisposition == .externalWritePreserved)
        #expect(try result.get().commandOutcome == .posted)
    }

    @Test("A cancelled queued request never enters the clipboard transaction")
    func cancelledQueuedRequestNeverEntersTransaction() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var writtenTranscripts: [String] = []
        var firstRestoreDelay: CheckedContinuation<Void, Never>?
        var restoreDelayCount = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                writtenTranscripts.append(text)
                return pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { duration in
                guard duration == .milliseconds(200) else { return }
                restoreDelayCount += 1
                if restoreDelayCount == 1 {
                    await withCheckedContinuation { continuation in
                        firstRestoreDelay = continuation
                    }
                }
            },
            nowNanoseconds: {
                now += 1_000_000
                return now
            }
        ))

        let firstTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "one", captureID: nil)
        }
        await yieldUntil { firstRestoreDelay != nil }

        let cancelledTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "two", captureID: nil)
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        cancelledTask.cancel()

        let thirdTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "three", captureID: nil)
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(writtenTranscripts == ["one"])

        firstRestoreDelay?.resume()
        firstRestoreDelay = nil
        let first = try await firstTask.value
        let cancelledResult = await cancelledTask.result
        let third = try await thirdTask.value

        #expect(first.commandOutcome == .posted)
        #expect(throws: CancellationError.self) {
            _ = try cancelledResult.get()
        }
        #expect(third.commandOutcome == .posted)
        #expect(writtenTranscripts == ["one", "three"])
        #expect(pasteboard.string(forType: .string) == "sentinel")
    }

    @Test("Suspended diagnostics do not hold the clipboard transaction gate")
    func suspendedDiagnosticsDoNotHoldClipboardTransaction() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var attemptIDs = ["attempt-one", "attempt-two"]
        var writtenTranscripts: [String] = []
        var recordedAttemptIDs: [String] = []
        var firstPersistenceDelay: CheckedContinuation<Void, Never>?
        var postCount = 0
        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                writtenTranscripts.append(text)
                return pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in postCount += 1 },
            sleep: { _ in },
            nowNanoseconds: {
                now += 1_000_000
                return now
            },
            makePasteAttemptID: { attemptIDs.removeFirst() },
            makeCaptureID: { "generated-capture" },
            recordPasteAttempt: { record in
                recordedAttemptIDs.append(record.pasteAttemptID)
                if record.pasteAttemptID == "attempt-one" {
                    await withCheckedContinuation { continuation in
                        firstPersistenceDelay = continuation
                    }
                }
            }
        ))

        let firstTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "one", captureID: "capture-one")
        }
        await yieldUntil { firstPersistenceDelay != nil }

        #expect(writtenTranscripts == ["one"])
        #expect(postCount == 4)
        #expect(pasteboard.string(forType: .string) == "sentinel")

        let secondTask = Task { @MainActor in
            try await service.pasteAndRestore(text: "two", captureID: "capture-two")
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        let writesWhileFirstPersistenceWasSuspended = writtenTranscripts

        firstPersistenceDelay?.resume()
        firstPersistenceDelay = nil
        let first = try await firstTask.value
        let second = try await secondTask.value

        #expect(first.commandOutcome == .posted)
        #expect(second.commandOutcome == .posted)
        #expect(second.clipboardDisposition == .restored)
        #expect(writesWhileFirstPersistenceWasSuspended == ["one", "two"])
        #expect(writtenTranscripts == ["one", "two"])
        #expect(recordedAttemptIDs == ["attempt-one", "attempt-two"])
        #expect(postCount == 8)
        #expect(pasteboard.string(forType: .string) == "sentinel")
    }

    @Test("Diagnostics persistence failure does not change paste outcome or cleanup")
    func diagnosticsFailureDoesNotChangePasteOutcomeOrCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("paste-diagnostics-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let diagnosticsURL = directory.appendingPathComponent("capture-diagnostics.jsonl")
        let diagnostics = CaptureDiagnostics(
            fileURL: diagnosticsURL,
            persistedCaptureStateURL: directory.appendingPathComponent("unfinished-capture.json"),
            sessionID: "failure-session",
            isEnabled: false,
            dependencies: CaptureDiagnosticsDependencies(appendLine: { _, _ in false })
        )
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("sentinel", forType: .string))

        var now: UInt64 = 0
        let service = PasteService(dependencies: PasteServiceDependencies(
            pasteboard: pasteboard,
            setPasteboardString: { text, pasteboard in
                pasteboard.setString(text, forType: .string)
            },
            preflightPostEventAccess: { true },
            secureInputActive: { false },
            readModifierFlags: { [] },
            makePasteEvents: { baselineFlags in makeCommandPasteEvents(baselineFlags: baselineFlags) },
            postEvent: { _ in },
            sleep: { _ in },
            nowNanoseconds: {
                now += 1_000_000
                return now
            },
            makePasteAttemptID: { "attempt-failed-write" },
            recordPasteAttempt: { record in
                _ = await diagnostics.recordPasteAttempt(record)
            }
        ))

        let timing = try await service.pasteAndRestore(text: "diagnostics may fail", captureID: "capture-failure")

        #expect(timing.commandOutcome == .posted)
        #expect(timing.clipboardDisposition == .restored)
        #expect(timing.pasteAttemptID == "attempt-failed-write")
        #expect(pasteboard.string(forType: .string) == "sentinel")
        #expect(!FileManager.default.fileExists(atPath: diagnosticsURL.path))
    }

    private func yieldUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<200 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }

    private func makeCommandPasteEvents(baselineFlags: CGEventFlags = []) -> PasteServiceDependencies.PasteEvents? {
        PasteServiceDependencies.makeCommandPasteEvents(keyCode: 9, baselineFlags: baselineFlags)
    }
}
