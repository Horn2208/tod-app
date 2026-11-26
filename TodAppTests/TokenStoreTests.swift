import Foundation
import Testing
@testable import TodApp

@Suite
struct TokenStoreTests {
    /// The in-memory double stands in for the Keychain everywhere else in the
    /// suite, so its behaviour has to match the contract exactly.
    @Test
    func anEmptyStoreReadsAsNothing() throws {
        #expect(try InMemoryTokenStore().read() == nil)
    }

    @Test
    func whatIsWrittenComesBack() throws {
        let store = InMemoryTokenStore()

        try store.write("rt-1")

        #expect(try store.read() == "rt-1")
    }

    @Test
    func writingAgainReplacesRatherThanDuplicates() throws {
        let store = InMemoryTokenStore()
        try store.write("rt-1")

        try store.write("rt-2")

        #expect(try store.read() == "rt-2")
    }

    @Test
    func clearingLeavesNothingBehind() throws {
        let store = InMemoryTokenStore()
        try store.write("rt-1")

        try store.clear()

        #expect(try store.read() == nil)
    }

    /// Clearing a store that holds nothing is what signing out twice looks
    /// like, and it must not be an error.
    @Test
    func clearingAnEmptyStoreIsFine() throws {
        try InMemoryTokenStore().clear()
    }

    /// The case `SpotifyProviderAuthTests`'s failing-write coverage never
    /// reached: a user who was already signed in, whose next write then
    /// fails. `KeychainTokenStore.write(_:)` updates in place rather than
    /// deleting first specifically so this holds -- a failed write must not
    /// cost the token that was working. There is no way to exercise the real
    /// Keychain here (the test target has no entitlements for it), so this
    /// pins the contract at the `TokenStore` protocol level, through the
    /// double that stands in for it everywhere else in the suite.
    @Test
    func aFailedWriteLeavesAPreviouslyStoredTokenInPlace() throws {
        let store = TokenStoreThatFailsToWrite(stored: "rt-old")

        #expect(throws: TodAppError.tokenStorageFailed) {
            try store.write("rt-new")
        }

        #expect(try store.read() == "rt-old")
    }
}
