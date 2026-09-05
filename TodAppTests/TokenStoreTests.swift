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
}
