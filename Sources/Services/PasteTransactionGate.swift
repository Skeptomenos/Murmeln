import Foundation

/// A cancellation-aware FIFO gate for complete paste transactions.
///
/// AppKit work and ownership stay on `MainActor`; the gate owns waiter IDs
/// and continuations. A cancelled waiter never enters the clipboard boundary.
@MainActor
final class PasteTransactionGate {
    private var isHeld = false
    private var waiterOrder: [UUID] = []
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    /// Explicit Copy must never queue behind a paste or a waiting paste.
    func tryAcquire() -> Bool {
        guard !isHeld else { return false }
        isHeld = true
        return true
    }

    func acquire() async throws {
        try Task.checkCancellation()

        guard isHeld else {
            isHeld = true
            return
        }

        let waiterID = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }

                waiterOrder.append(waiterID)
                waiters[waiterID] = continuation
            }
        } onCancel: {
            // The cancellation handler is synchronous. This bounded task hops
            // back to the actor that exclusively owns the waiter collection.
            Task {
                await self.cancelWaiter(waiterID)
            }
        }

        guard acquired else {
            throw CancellationError()
        }

        do {
            try Task.checkCancellation()
        } catch {
            release()
            throw error
        }
    }

    func release() {
        while let waiterID = waiterOrder.first {
            waiterOrder.removeFirst()
            guard let continuation = waiters.removeValue(forKey: waiterID) else {
                continue
            }

            continuation.resume(returning: true)
            return
        }

        isHeld = false
    }

    private func cancelWaiter(_ waiterID: UUID) {
        waiterOrder.removeAll { $0 == waiterID }
        waiters.removeValue(forKey: waiterID)?.resume(returning: false)
    }
}
