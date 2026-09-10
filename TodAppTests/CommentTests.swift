import Foundation
import Testing
@testable import TodApp

@Suite
struct CommentTests {
    @Test
    func aCommentKeepsItsAuthorAndTime() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let comment = Comment(
            id: 1, authorID: "lena", authorName: "Lena",
            text: "Bester Song heute", postedAt: when
        )

        #expect(comment.authorName == "Lena")
        #expect(comment.postedAt == when)
    }

    /// Posts stored before comments had structure must still decode, so the
    /// field is optional-safe rather than a hard schema break.
    @Test
    func aSubmissionWithoutCommentsDecodes() throws {
        let json = Data("""
        {"id":1,"posterID":"du","track":"Genesis","artist":"Justice",
         "coverColorHex":"#b3527a","comments":[]}
        """.utf8)

        let submission = try JSONDecoder().decode(Submission.self, from: json)

        #expect(submission.comments.isEmpty)
    }

    @Test
    func commentsSurviveARoundTrip() throws {
        let submission = Submission(
            id: 1, posterID: "du", track: "Genesis", artist: "Justice",
            coverColorHex: "#b3527a",
            comments: [
                Comment(id: 1, authorID: "mats", authorName: "Mats",
                        text: "Läuft bei dir", postedAt: Date(timeIntervalSince1970: 0))
            ]
        )

        let decoded = try JSONDecoder().decode(
            Submission.self, from: JSONEncoder().encode(submission)
        )

        #expect(decoded.comments.first?.authorName == "Mats")
        #expect(decoded.comments.first?.text == "Läuft bei dir")
    }
}

/// Commenting through the store, where the group a song belongs to has to be
/// worked out rather than assumed.
@Suite
@MainActor
struct CommentFlowTests {
    private func makeStore() async -> (AppStore, InMemoryRepository) {
        // One fresh repository for every role, never `.shared`: other suites
        // write into that singleton, and a comment count is exactly the kind of
        // thing that then depends on test order.
        let repo = InMemoryRepository()
        let store = AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo
        )
        await store.loadGroups()
        return (store, repo)
    }

    /// Hands back the submission rather than its comments. `[Comment]` cannot
    /// be written here: Swift Testing has a `Comment` of its own, and the
    /// module's own name is taken by the `TodApp` app struct, so neither the
    /// bare name nor `TodApp.Comment` resolves.
    private func song(_ store: AppStore, _ submissionID: Int) -> Submission? {
        store.groups.flatMap(\.submissions).first { $0.id == submissionID }
    }

    @Test
    func aCommentAppearsUnderTheSongWithItsAuthor() async {
        let (store, _) = await makeStore()
        let before = song(store, 3)?.comments.count ?? 0

        await store.addComment("bester Übergang bisher", to: 3)

        let after = song(store, 3)?.comments ?? []
        #expect(after.count == before + 1)
        #expect(after.last?.text == "bester Übergang bisher")
        #expect(after.last?.authorID == "du")
        #expect(store.lastError == nil)
    }

    /// The send button is disabled on an empty field, but the guard belongs in
    /// the store too -- otherwise the rule lives only in one view's `canSend`.
    @Test
    func whitespaceAloneIsNotAComment() async {
        let (store, _) = await makeStore()
        let before = song(store, 3)?.comments.count ?? 0

        await store.addComment("   \n  ", to: 3)

        #expect(song(store, 3)?.comments.count == before)
    }

    @Test
    func aCommentIsTrimmedBeforeItIsStored() async {
        let (store, _) = await makeStore()

        await store.addComment("  läuft  ", to: 3)

        #expect(song(store, 3)?.comments.last?.text == "läuft")
    }

    /// The story row spans every group, so a song can be open while another
    /// group is selected. Filing the comment under `currentGroup` would drop it
    /// into the wrong group -- or, for a group without that submission id,
    /// throw it away entirely.
    @Test
    func aCommentGoesToTheSongsOwnGroupNotTheSelectedOne() async {
        let (store, _) = await makeStore()
        store.selectGroup("lnc")

        // Submission 5 belongs to `wg`.
        await store.addComment("die WG hat recht", to: 5)

        let wg = store.groups.first { $0.id == "wg" }
        let lnc = store.groups.first { $0.id == "lnc" }
        #expect(wg?.submissions.first { $0.id == 5 }?.comments.last?.text == "die WG hat recht")
        #expect(lnc?.submissions.allSatisfy { $0.comments.allSatisfy { $0.authorID != "du" } } == true)
        #expect(store.lastError == nil)
    }

    @Test
    func aSongNobodyGroupHasIsNotCommentedOn() async {
        let (store, _) = await makeStore()

        await store.addComment("ins Leere", to: 9999)

        #expect(store.lastError == nil)
    }
}

@Suite
struct CommentTimeTests {
    private let de = Locale(identifier: "de_DE")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The bug this rule exists for: a comment written a second ago came back
    /// as "in 0 Sekunden", reading as if it had been posted from the future.
    @Test
    func aCommentJustWrittenReadsAsJustNow() {
        #expect(CommentTime.label(for: now, now: now, locale: de) == "gerade eben")
        #expect(CommentTime.label(for: now.addingTimeInterval(-3), now: now, locale: de) == "gerade eben")
    }

    /// A clock a few seconds out of step points the same wording forwards.
    @Test
    func aTimestampSlightlyAheadOfNowStillReadsAsJustNow() {
        #expect(CommentTime.label(for: now.addingTimeInterval(5), now: now, locale: de) == "gerade eben")
    }

    @Test
    func anOlderCommentSaysHowLongAgo() {
        let label = CommentTime.label(for: now.addingTimeInterval(-3600), now: now, locale: de)

        #expect(label.contains("Stunde"))
        #expect(label.hasPrefix("vor"))
    }
}
