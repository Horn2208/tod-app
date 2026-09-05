import Foundation
@testable import TodApp

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

/// Counts how many times a @Sendable closure was called.
/// Lets a test check "exactly once" / "no more than expected" rather than
/// just "at least once", which a `Flag` alone cannot express. Every current
/// use counts intercepted network requests (a refresh attempt, a pause call),
/// so this sits next to `RequestBox` under that name rather than a bare
/// `Counter` -- the name says what is actually being counted.
internal final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        stored += 1
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        stored = 0
    }
}

/// A `TokenStore` whose `write(_:)` always fails, as a real Keychain write
/// can (device locked in an unexpected way, storage full, entitlement
/// missing). Lets a test simulate that failure without touching the real
/// Keychain. `read()` and `clear()` behave like `InMemoryTokenStore` so a
/// test can still set up or inspect state around the failing write.
internal final class TokenStoreThatFailsToWrite: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    init(stored: String? = nil) {
        self.stored = stored
    }

    func read() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func write(_ refreshToken: String) throws {
        throw TodAppError.tokenStorageFailed
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
