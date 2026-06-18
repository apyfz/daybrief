import Foundation

/// Thrown by ``withTimeout(_:clock:operation:)`` when `operation` exceeds the budget.
struct TimeoutError: Error, Equatable {}

/// Runs `operation`, racing it against `timeout` on `clock`.
///
/// Whichever of the operation or the timeout finishes first wins; the loser is
/// cancelled. The operation must honor cooperative cancellation (the `Connector`
/// contract requires it) so the sleeper winning actually aborts the in-flight
/// work. Cancellation of the *enclosing* task propagates into both children and
/// rethrows as `CancellationError`.
///
/// - Parameters:
///   - timeout: The budget. A non-positive budget times out immediately.
///   - clock: The clock to sleep on (injectable for deterministic tests).
///   - operation: The async, throwing work to bound.
/// - Returns: The operation's result if it finishes within `timeout`.
/// - Throws: ``TimeoutError`` if the budget elapses first; otherwise whatever
///   `operation` throws (including `CancellationError`).
func withTimeout<R: Sendable>(
    _ timeout: Duration,
    clock: any Clock<Duration>,
    operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    try await withThrowingTaskGroup(of: R.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await clock.sleep(for: timeout)
            throw TimeoutError()
        }

        defer { group.cancelAll() }
        // The first child to finish (the operation succeeding, the sleeper
        // throwing TimeoutError, or either throwing on cancellation) decides the
        // race; `cancelAll` in the defer tears down the loser.
        guard let result = try await group.next() else {
            // Unreachable: two tasks were added, so `next()` yields at least once.
            throw TimeoutError()
        }
        return result
    }
}
