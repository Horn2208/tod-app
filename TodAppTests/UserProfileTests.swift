import Foundation
import Testing
@testable import TodApp

@Suite
@MainActor
struct UserProfileTests {
    @Test
    func aFreshStoreHasAProfileForTheCurrentUser() {
        let store = AppStore()

        #expect(store.profile.id == "du")
        #expect(!store.profile.name.isEmpty)
    }

    @Test
    func renamingSticks() {
        let store = AppStore()

        store.updateProfile(name: "Lennet", imageData: nil)

        #expect(store.profile.name == "Lennet")
    }

    /// Passing no image must not wipe one that was already chosen -- the
    /// profile screen edits name and picture independently.
    @Test
    func renamingKeepsAnExistingPicture() {
        let store = AppStore()
        let picture = Data([0x01, 0x02])
        store.updateProfile(name: "Lennet", imageData: picture)

        store.updateProfile(name: "Lenny", imageData: nil)

        #expect(store.profile.imageData == picture)
        #expect(store.profile.name == "Lenny")
    }

    @Test
    func aBlankNameIsRefused() {
        let store = AppStore()
        let before = store.profile.name

        store.updateProfile(name: "   ", imageData: nil)

        #expect(store.profile.name == before)
    }

    /// Everything is free at launch except Battle, so the flag starts off.
    @Test
    func premiumStartsOff() {
        #expect(AppStore().profile.isPremium == false)
    }

    @Test
    func premiumCanBeTurnedOnAndOffAgain() {
        let store = AppStore()

        store.setPremium(true)
        #expect(store.profile.isPremium)

        store.setPremium(false)
        #expect(store.profile.isPremium == false)
    }

    /// The locks read the profile, so renaming or changing a picture must not
    /// disturb what has been paid for.
    @Test
    func editingTheProfileLeavesPremiumAlone() {
        let store = AppStore()
        store.setPremium(true)

        store.updateProfile(name: "Lennet", imageData: Data([0x01]))

        #expect(store.profile.isPremium)
    }
}
