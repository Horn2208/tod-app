import Foundation
import Testing
@testable import TodApp

/// Deleting the account: Apple asks it of every app with accounts. The server
/// removes the person and everything theirs; the app then stands where a
/// fresh install does.
@MainActor
@Suite
struct AccountDeletionTests {
    actor DeletingAccountService: AccountService {
        private let failure: TodAppError?
        private(set) var didDelete = false

        init(failure: TodAppError? = nil) { self.failure = failure }

        func restore() -> AccountUser? { AccountUser(id: "leaving-user") }
        func signInWithApple(idToken: String, nonce: String, name: String?) throws -> AccountUser {
            AccountUser(id: "leaving-user")
        }
        func signOut() {}
        func deleteAccount() throws {
            if let failure { throw failure }
            didDelete = true
        }
    }

    private func store(_ account: DeletingAccountService) -> AppStore {
        let repo = InMemoryRepository()
        return AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo, profileRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            accountService: account,
            reminders: RecordingReminders())
    }

    @Test
    func aDeletedAccountLeavesTheAppSignedOutAndEmpty() async {
        let account = DeletingAccountService()
        let store = store(account)
        await store.restoreSession()
        #expect(store.isSignedIn)

        let deleted = await store.deleteAccount()

        #expect(deleted)
        #expect(await account.didDelete)
        #expect(!store.isSignedIn)
        #expect(store.groups.isEmpty)
    }

    /// The profile sheet saves its name as it closes -- after the deletion.
    /// With no account left that is no error to show on the start screen.
    @Test
    func savingAfterDeletionIsQuiet() async {
        let store = store(DeletingAccountService())
        await store.restoreSession()
        _ = await store.deleteAccount()

        await store.updateProfile(name: "Neu", imageData: nil)

        #expect(store.lastError == nil)
    }

    /// Nothing is thrown away on this phone when the server did not delete.
    @Test
    func aFailedDeletionKeepsEverythingAndSaysSo() async {
        let store = store(DeletingAccountService(failure: .notAllowed))
        await store.restoreSession()
        let groups = store.groups.count

        let deleted = await store.deleteAccount()

        #expect(!deleted)
        #expect(store.isSignedIn)
        #expect(store.groups.count == groups)
        #expect(store.lastError == .notAllowed)
    }
}
