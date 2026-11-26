import Foundation

/// Forwards the first outcome to a continuation and drops every later one.
///
/// Resuming a `CheckedContinuation` twice does not throw -- it traps the whole
/// process with "SWIFT TASK CONTINUATION MISUSE". A completion handler owned by
/// a system framework is not something we can promise fires exactly once, and a
/// sign-in flow really did crash this app that way. So the guarantee is made
/// here instead of assumed out there.
final class SingleResume<Success: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Success, Error>?

    init(_ continuation: CheckedContinuation<Success, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Success) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    /// Hands out the continuation once and never again. The lock matters: two
    /// callbacks arriving on different threads must not both get one.
    private func take() -> CheckedContinuation<Success, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let pending = continuation
        continuation = nil
        return pending
    }
}
