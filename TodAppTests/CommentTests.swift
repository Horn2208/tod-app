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
