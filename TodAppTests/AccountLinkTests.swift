import Foundation
import Testing
@testable import TodApp

/// "Konto sichern – mit Apple verknüpfen" (`docs/prompt.md`, item 18).
@Suite
@MainActor
struct AccountLinkTests {
    actor LinkingAccountService: AccountService {
        let refusal: TodAppError?
        private(set) var links = 0
        init(refusal: TodAppError? = nil) { self.refusal = refusal }

        func restore() async -> AccountUser? { nil }
        func signInWithApple(idToken: String, nonce: String, name: String?) async throws -> AccountUser {
            AccountUser(id: "apple")
        }
        func signInAnonymously() async throws -> AccountUser {
            AccountUser(id: "anon", isAnonymous: true)
        }
        func signOut() async {}
        func linkApple(idToken: String, nonce: String) async throws -> AccountUser {
            links += 1
            if let refusal { throw refusal }
            return AccountUser(id: "anon", isAnonymous: false)
        }
    }

    private func store(_ service: LinkingAccountService) -> AppStore {
        AppStore(groupRepo: MockGroupRepository(groups: []), accountService: service)
    }

    @Test
    func linkingKeepsTheAccountAndEndsItsAnonymity() async {
        let service = LinkingAccountService()
        let store = store(service)
        await store.continueWithoutAccount()
        #expect(store.account?.isAnonymous == true)

        #expect(await store.linkApple(idToken: "t", nonce: "n"))

        #expect(store.account == AccountUser(id: "anon", isAnonymous: false))
    }

    @Test
    func anAppleIDInUseIsSaidSoAndNothingChanges() async {
        let store = store(LinkingAccountService(refusal: .appleIDInUse))
        await store.continueWithoutAccount()

        let linked = await store.linkApple(idToken: "t", nonce: "n")

        #expect(!linked)
        #expect(store.lastError == .appleIDInUse)
        #expect(store.account?.isAnonymous == true)
        #expect(PostSongModel.message(for: TodAppError.appleIDInUse).contains("Apple-ID"))
    }

    @Test
    func anAccountWithSignInIsNotLinkedAgain() async {
        let service = LinkingAccountService()
        let store = store(service)
        await store.signInWithApple(idToken: "t", nonce: "n", name: nil)

        let linked = await store.linkApple(idToken: "t", nonce: "n")

        #expect(!linked)
        #expect(await service.links == 0)
    }
}
