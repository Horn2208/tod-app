import Foundation

/// Captures a request across the @Sendable boundary that an injected closure imposes.
/// Lets a test hand an URLRequest from within a closure back out to its test context.
internal final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: URLRequest?

    var value: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func store(_ request: URLRequest) {
        lock.lock(); defer { lock.unlock() }
        stored = request
    }
}

/// A one-way boolean flag that a @Sendable closure can raise.
/// Lets a closure record that it was called, even if it cannot return a value.
internal final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised: Bool = false

    var isRaised: Bool {
        lock.lock(); defer { lock.unlock() }
        return raised
    }

    func raise() {
        lock.lock(); defer { lock.unlock() }
        raised = true
    }
}
