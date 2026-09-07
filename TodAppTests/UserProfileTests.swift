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
}
