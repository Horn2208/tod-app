import Foundation
import Testing
@testable import TodApp

private let noted = Date(timeIntervalSince1970: 1_790_000_000)

private let spotifyHit = TrackCandidate(
    title: "Nights", artist: "Frank Ocean",
    source: TrackSource(
        service: .spotify, serviceTrackID: "7eqoqGkKwgOaWNNHx90uEZ",
        pageURL: URL(string: "https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ")!,
        artworkURL: URL(string: "https://i.scdn.co/image/nights")),
    durationSeconds: 307, isrc: "USUM71612345")

private let appleHit = TrackCandidate(
    title: "Passionfruit", artist: "Drake", source: nil,
    durationSeconds: 298, appleMusicID: "1440892167",
    artworkURL: URL(string: "https://is1-ssl.mzstatic.com/passionfruit/600x600bb.jpg"))

/// A noted song is the hit it was noted from, and back.
@Suite
struct SavedSongTests {
    /// Posting it later must not need a second search: everything the hit
    /// carried comes back.
    @Test
    func itGivesBackTheHitItWasNotedFrom() {
        #expect(SavedSong(spotifyHit, savedAt: noted).candidate == spotifyHit)
        #expect(SavedSong(appleHit, savedAt: noted).candidate == appleHit)
    }

    /// The hit's id, so the bookmark in the search knows it is noted.
    @Test
    func itHasTheHitsID() {
        #expect(SavedSong(spotifyHit, savedAt: noted).id == spotifyHit.id)
    }

    @Test
    func itSurvivesTheRoundTripThroughJSON() throws {
        let song = SavedSong(spotifyHit, savedAt: noted)
        let data = try JSONEncoder().encode(song)

        #expect(try JSONDecoder().decode(SavedSong.self, from: data) == song)
    }

    @Test
    func theNewestComesFirst() {
        let older = SavedSong(appleHit, savedAt: noted)
        let newer = SavedSong(spotifyHit, savedAt: noted.addingTimeInterval(60))

        #expect(SavedSongs.adding(newer, to: [older]).map(\.id) == [spotifyHit.id, appleHit.id])
    }

    /// Noting a song again moves it up rather than listing it twice.
    @Test
    func aSongIsListedOnce() {
        let list = [SavedSong(spotifyHit, savedAt: noted), SavedSong(appleHit, savedAt: noted)]
        let again = SavedSong(appleHit, savedAt: noted.addingTimeInterval(60))

        let result = SavedSongs.adding(again, to: list)

        #expect(result.map(\.id) == [appleHit.id, spotifyHit.id])
        #expect(result.first?.savedAt == again.savedAt)
    }

    @Test
    func removingTakesOnlyThatSong() {
        let list = [SavedSong(spotifyHit, savedAt: noted), SavedSong(appleHit, savedAt: noted)]

        #expect(SavedSongs.removing(id: spotifyHit.id, from: list).map(\.id) == [appleHit.id])
    }
}

/// The file on the phone: one per account.
@Suite
struct FileSavedSongStorageTests {
    private let storage = FileSavedSongStorage(
        directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("SavedSongTests-\(UUID().uuidString)", isDirectory: true))

    @Test
    func nothingNotedYetIsAnEmptyList() throws {
        #expect(try storage.load(for: "lena").isEmpty)
    }

    @Test
    func whatIsSavedComesBack() throws {
        let songs = [SavedSong(spotifyHit, savedAt: noted), SavedSong(appleHit, savedAt: noted)]

        try storage.save(songs, for: "lena")

        #expect(try storage.load(for: "lena") == songs)
    }

    /// A phone handed on must not show the last person's list.
    @Test
    func eachAccountHasItsOwnList() throws {
        try storage.save([SavedSong(spotifyHit, savedAt: noted)], for: "lena")

        #expect(try storage.load(for: "max").isEmpty)
    }

    @Test
    func deletingForgetsTheAccountsList() throws {
        try storage.save([SavedSong(spotifyHit, savedAt: noted)], for: "lena")

        try storage.delete(for: "lena")

        #expect(try storage.load(for: "lena").isEmpty)
    }

    /// An id is a uuid, but a file name is no place to find out it was not.
    @Test
    func theFileNameKeepsToTheDirectory() {
        let file = storage.file(for: "../../etc/passwd")

        #expect(file.deletingLastPathComponent() == storage.directory)
        #expect(file.lastPathComponent == "etcpasswd.json")
    }
}

/// The store's side: the list follows the account.
@Suite
@MainActor
struct AppStoreSavedSongTests {
    private let lena = AccountUser(id: "0b6f7c1e-lena")

    private func store(_ storage: any SavedSongStorage, restoring user: AccountUser?) -> AppStore {
        AppStore(
            provider: FakeMusicProvider(capabilities: .none),
            accountService: FakeAccountService(restored: user),
            savedSongStorage: storage,
            now: { noted })
    }

    @Test
    func theBookmarkNotesASongAndForgetsItAgain() async {
        let store = store(InMemorySavedSongStorage(), restoring: lena)
        await store.restoreSession()

        store.toggleSaved(spotifyHit)
        #expect(store.isSaved(spotifyHit))
        #expect(store.savedSongs.first?.savedAt == noted)

        store.toggleSaved(spotifyHit)
        #expect(!store.isSaved(spotifyHit))
    }

    /// Noted today, still there when the app starts tomorrow.
    @Test
    func theListIsThereAfterARestart() async {
        let storage = InMemorySavedSongStorage()
        let first = store(storage, restoring: lena)
        await first.restoreSession()
        first.toggleSaved(appleHit)

        let second = store(storage, restoring: lena)
        await second.restoreSession()

        #expect(second.savedSongs.map(\.id) == [appleHit.id])
    }

    @Test
    func signingOutEmptiesTheListOnScreenButKeepsIt() async throws {
        let storage = InMemorySavedSongStorage()
        let store = store(storage, restoring: lena)
        await store.restoreSession()
        store.toggleSaved(spotifyHit)

        await store.signOut()

        #expect(store.savedSongs.isEmpty)
        #expect(try storage.load(for: lena.id).map(\.id) == [spotifyHit.id])
    }

    @Test
    func removingTakesItOffTheList() async {
        let store = store(InMemorySavedSongStorage(), restoring: lena)
        await store.restoreSession()
        store.toggleSaved(spotifyHit)
        store.toggleSaved(appleHit)

        store.removeSaved(id: spotifyHit.id)

        #expect(store.savedSongs.map(\.id) == [appleHit.id])
    }

    /// Deleting the account takes its noted songs with it.
    @Test
    func deletingTheAccountDeletesTheList() async throws {
        let storage = InMemorySavedSongStorage()
        let store = AppStore(
            provider: FakeMusicProvider(capabilities: .none),
            accountService: LocalAccountService(),
            savedSongStorage: storage,
            now: { noted })
        await store.restoreSession()
        store.toggleSaved(spotifyHit)

        #expect(await store.deleteAccount())

        #expect(try storage.load(for: LocalAccountService.user.id).isEmpty)
    }
}
