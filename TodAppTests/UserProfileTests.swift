import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct UserProfileTests {
    /// Its own repository each, so no test renames the shared one.
    private func makeStore() -> AppStore {
        AppStore(profileRepo: InMemoryRepository())
    }

    @Test
    func aFreshStoreHasAProfileForTheCurrentUser() {
        let store = makeStore()

        #expect(store.profile.id == "du")
        #expect(!store.profile.name.isEmpty)
    }

    @Test
    func renamingSticks() async {
        let store = makeStore()

        await store.updateProfile(name: "Lennet", imageData: nil)

        #expect(store.profile.name == "Lennet")
    }

    /// Passing no image must not wipe one that was already chosen -- the
    /// profile screen edits name and picture independently.
    @Test
    func renamingKeepsAnExistingPicture() async {
        let store = makeStore()
        let picture = Data([0x01, 0x02])
        await store.updateProfile(name: "Lennet", imageData: picture)

        await store.updateProfile(name: "Lenny", imageData: nil)

        #expect(store.profile.imageData == picture)
        #expect(store.profile.name == "Lenny")
    }

    @Test
    func aBlankNameIsRefused() async {
        let store = makeStore()
        let before = store.profile.name

        await store.updateProfile(name: "   ", imageData: nil)

        #expect(store.profile.name == before)
    }

    /// Everything is free at launch except Battle, so the flag starts off.
    @Test
    func premiumStartsOff() {
        #expect(makeStore().profile.isPremium == false)
    }

    @Test
    func premiumCanBeTurnedOnAndOffAgain() {
        let store = makeStore()

        store.setPremium(true)
        #expect(store.profile.isPremium)

        store.setPremium(false)
        #expect(store.profile.isPremium == false)
    }

    /// The locks read the profile, so renaming or changing a picture must not
    /// disturb what has been paid for.
    @Test
    func editingTheProfileLeavesPremiumAlone() async {
        let store = makeStore()
        store.setPremium(true)

        await store.updateProfile(name: "Lennet", imageData: Data([0x01]))

        #expect(store.profile.isPremium)
    }
}
