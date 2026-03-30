import Testing
import Foundation
@testable import mrml

@Suite("Parallel Refinement Audit Runner Tests")
struct ParallelRefinementAuditRunnerTests {
    @Test("Selected preset retries once and succeeds")
    func selectedPresetRetrySucceeds() async throws {
        let casualID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let structuredID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let presets = [
            RefinementVariantPlan(presetID: casualID, name: "Casual", basePrompt: "Casual prompt", effectivePrompt: "Casual prompt + dict"),
            RefinementVariantPlan(presetID: structuredID, name: "Structured", basePrompt: "Structured prompt", effectivePrompt: "Structured prompt + dict")
        ]
        let clock = DeterministicNow([100, 350])
        let runner = ParallelRefinementAuditRunner(
            selectedPresetID: structuredID,
            selectedPresetName: "Structured",
            presets: presets,
            now: clock.callAsFunction
        )
        let attemptCounter = LockedCounter()

        let result = try await runner.run { plan in
            let attempt = await attemptCounter.increment(for: plan.name)

            switch (plan.name, attempt) {
            case ("Casual", _):
                return RefinementExecutionResult(
                    text: "casual result",
                    timing: StageTiming(startedAt: 120, finishedAt: 220)
                )
            case ("Structured", 1):
                throw StubFailure(message: "selected failed")
            case ("Structured", 2):
                return RefinementExecutionResult(
                    text: "structured retry result",
                    timing: StageTiming(startedAt: 360, finishedAt: 520)
                )
            default:
                throw StubFailure(message: "unexpected attempt")
            }
        }

        #expect(result.variantsByPresetID[structuredID]?.text == "structured retry result")
        #expect(result.variantsByPresetID[structuredID]?.basePrompt == "Structured prompt")
        #expect(result.variantsByPresetID[structuredID]?.effectivePrompt == "Structured prompt + dict")
        #expect(result.selectedVariant.text == "structured retry result")
        #expect(result.selectedRecoveredByRetry == true)
        #expect(result.successCount == 2)
        #expect(result.failureCount == 0)
        #expect(result.selectedResultReadyAt == 520)
        #expect(result.auditFanoutFinishedAt == 520)
    }

    @Test("Selected preset failure after retry becomes explicit error")
    func selectedPresetRetryFailureThrows() async throws {
        let casualID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let structuredID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        let presets = [
            RefinementVariantPlan(presetID: casualID, name: "Casual", basePrompt: "Casual prompt", effectivePrompt: "Casual prompt + dict"),
            RefinementVariantPlan(presetID: structuredID, name: "Structured", basePrompt: "Structured prompt", effectivePrompt: "Structured prompt + dict")
        ]
        let clock = DeterministicNow([100, 300])
        let runner = ParallelRefinementAuditRunner(
            selectedPresetID: structuredID,
            selectedPresetName: "Structured",
            presets: presets,
            now: clock.callAsFunction
        )
        let attemptCounter = LockedCounter()

        await #expect(throws: ParallelRefinementError.self) {
            try await runner.run { plan in
                let attempt = await attemptCounter.increment(for: plan.name)

                if plan.name == "Casual" {
                    return RefinementExecutionResult(
                        text: "casual result",
                        timing: StageTiming(startedAt: 120, finishedAt: 220)
                    )
                }

                if plan.name == "Structured", attempt <= 2 {
                    throw StubFailure(message: "selected failed")
                }

                throw StubFailure(message: "unexpected attempt")
            }
        }
    }

    @Test("Fanout timing remains separate from selected-result readiness")
    func auditFanoutTimingCanOutliveSelectedResult() async throws {
        let casualID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let structuredID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
        let markdownID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        let presets = [
            RefinementVariantPlan(presetID: casualID, name: "Casual", basePrompt: "Casual prompt", effectivePrompt: "Casual prompt + dict"),
            RefinementVariantPlan(presetID: structuredID, name: "Structured", basePrompt: "Structured prompt", effectivePrompt: "Structured prompt + dict"),
            RefinementVariantPlan(presetID: markdownID, name: "Markdown", basePrompt: "Markdown prompt", effectivePrompt: "Markdown prompt + dict")
        ]
        let clock = DeterministicNow([100, 480])
        let runner = ParallelRefinementAuditRunner(
            selectedPresetID: casualID,
            selectedPresetName: "Casual",
            presets: presets,
            now: clock.callAsFunction
        )

        let result = try await runner.run { plan in
            switch plan.name {
            case "Casual":
                return RefinementExecutionResult(
                    text: "casual result",
                    timing: StageTiming(startedAt: 120, finishedAt: 220)
                )
            case "Structured":
                return RefinementExecutionResult(
                    text: "structured result",
                    timing: StageTiming(startedAt: 130, finishedAt: 460)
                )
            case "Markdown":
                throw StubFailure(message: "markdown failed")
            default:
                throw StubFailure(message: "unexpected preset")
            }
        }

        #expect(result.selectedResultReadyAt == 220)
        #expect(result.auditFanoutFinishedAt == 480)
        #expect(result.successCount == 2)
        #expect(result.failureCount == 1)
        #expect(result.selectedVariant.name == "Casual")
    }

    @Test("Selected preset identity survives duplicate display names")
    func selectedPresetIdentitySurvivesDuplicateDisplayNames() async throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-00000000AAA1")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-00000000AAA2")!
        let presets = [
            RefinementVariantPlan(presetID: firstID, name: "Custom", basePrompt: "First prompt", effectivePrompt: "First prompt + dict"),
            RefinementVariantPlan(presetID: secondID, name: "Custom", basePrompt: "Second prompt", effectivePrompt: "Second prompt + dict")
        ]
        let runner = ParallelRefinementAuditRunner(
            selectedPresetID: secondID,
            selectedPresetName: "Custom",
            presets: presets,
            now: { 100 }
        )

        let result = try await runner.run { plan in
            if plan.presetID == firstID {
                return RefinementExecutionResult(
                    text: "first result",
                    timing: StageTiming(startedAt: 110, finishedAt: 210)
                )
            }

            return RefinementExecutionResult(
                text: "second result",
                timing: StageTiming(startedAt: 120, finishedAt: 220)
            )
        }

        #expect(result.selectedVariant.presetID == secondID)
        #expect(result.selectedVariant.text == "second result")
        #expect(result.variantsByPresetID[firstID]?.text == "first result")
        #expect(result.variantsByPresetID[secondID]?.text == "second result")
    }
}

private struct StubFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private actor LockedCounter {
    private var counts: [String: Int] = [:]

    func increment(for key: String) -> Int {
        let next = (counts[key] ?? 0) + 1
        counts[key] = next
        return next
    }
}

private final class DeterministicNow: @unchecked Sendable {
    private var values: [UInt64]
    private let lock = NSLock()

    init(_ values: [UInt64]) {
        self.values = values
    }

    func callAsFunction() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }

        if values.isEmpty {
            return 0
        }
        return values.removeFirst()
    }
}
