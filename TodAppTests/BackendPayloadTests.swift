import Foundation
import ImageIO
import Testing
import UIKit
@testable import TodApp

/// What the app sends. A wrong key is a request the server turns down only
/// at runtime, so the bodies are checked here, as JSON, the way the library
/// writes them.
@Suite
struct BackendPayloadTests {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try BackendRecords.encoder.encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func submission(
        track: String = "Nights", artist: String = "Frank Ocean",
        source: TrackSource? = nil, section: TrackSection? = nil
    ) -> Submission {
        Submission(
            id: 99, posterID: "someone", track: track, artist: artist, coverColorHex: "#000000",
            comments: [], source: source, section: section, isrc: nil, appleMusicID: "1440",
            postedAt: Date())
    }

    /// Id, poster and time are the server's; the payload does not carry them.
    @Test
    func aPostSendsOnlyWhatTheAppMaySet() throws {
        let source = TrackSource(
            service: .spotify, serviceTrackID: "abc",
            pageURL: URL(string: "https://open.spotify.com/track/abc")!,
            artworkURL: URL(string: "https://i.scdn.co/image/x"))
        let body = try json(NewSubmissionPayload(
            submission: submission(source: source, section: TrackSection(start: 60, end: 90)),
            groupID: "g1"))

        #expect(Set(body.keys) == [
            "group_id", "track", "artist", "service", "service_track_id", "page_url",
            "artwork_url", "apple_music_id", "section_start", "section_end",
        ])
        #expect(body["service"] as? String == "spotify")
        #expect(body["page_url"] as? String == "https://open.spotify.com/track/abc")
        #expect(body["section_end"] as? Double == 90)
    }

    @Test
    func aPostWithoutSourceOrSectionLeavesThemOut() throws {
        let body = try json(NewSubmissionPayload(submission: submission(), groupID: "g1"))

        #expect(body["service"] == nil)
        #expect(body["section_start"] == nil)
        #expect(body["isrc"] == nil)
    }

    /// A pasted link whose details could not be read has no artist; the
    /// database wants one.
    @Test
    func aPostWithoutArtistSaysSo() throws {
        let body = try json(NewSubmissionPayload(submission: submission(artist: "  "), groupID: "g1"))

        #expect(body["artist"] as? String == "Unbekannt")
    }

    /// A title is at most 200 characters in the database, a pasted URL may
    /// be longer.
    @Test
    func anOverlongTitleIsCut() throws {
        let body = try json(NewSubmissionPayload(
            submission: submission(track: String(repeating: "x", count: 250)), groupID: "g1"))

        #expect((body["track"] as? String)?.unicodeScalars.count == 200)
    }

    @Test
    func aNewGroupSendsNameAndIcon() throws {
        let body = try json(NewGroupPayload(name: "Band", icon: "🎸"))

        #expect(body as NSDictionary == ["name": "Band", "icon": "🎸"] as NSDictionary)
    }

    @Test
    func aGroupEditWritesTheDatabasesSpelling() throws {
        let body = try json(GroupPatch(name: "Band", invitePolicy: .creatorOnly, imagePath: "g/x.jpg"))
        let nameless = try json(GroupPatch(name: nil, invitePolicy: .everyone, imagePath: nil))

        #expect(body as NSDictionary
            == ["name": "Band", "invite_policy": "creator_only", "image_path": "g/x.jpg"] as NSDictionary)
        #expect(nameless as NSDictionary == ["invite_policy": "everyone"] as NSDictionary)
    }

    @Test
    func anInviteNamesOnlyItsGroup() throws {
        #expect(try json(NewInvitePayload(groupID: "g1")) as NSDictionary == ["group_id": "g1"] as NSDictionary)
    }

    @Test
    func aVoteCarriesItsRoundAndItsRating() throws {
        let body = try json(NewVotePayload(
            vote: Vote(voterID: "me", submissionID: 7, rating: .awful, isHiddenGem: false, note: "nein"),
            groupID: "g1", roundDay: "2026-09-17"))

        #expect(body as NSDictionary == [
            "submission_id": 7, "group_id": "g1", "round_day": "2026-09-17",
            "rating": -2, "note": "nein",
        ] as NSDictionary)
    }

    /// Changing a rating without a note must clear the old note, so the null
    /// is written out rather than left away.
    @Test
    func aChangedRatingWithoutANoteClearsTheOldOne() throws {
        let data = try BackendRecords.encoder.encode(VotePatch(rating: 1, note: nil))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(body["rating"] as? Int == 1)
        #expect(body.keys.contains("note"))
        #expect(body["note"] is NSNull)
    }

    @Test
    func aGemNamesItsRoundAndSong() throws {
        #expect(try json(NewGemPayload(groupID: "g1", roundDay: "2026-09-17", submissionID: 7)) as NSDictionary
            == ["group_id": "g1", "round_day": "2026-09-17", "submission_id": 7] as NSDictionary)
        #expect(try json(GemPatch(submissionID: 8)) as NSDictionary == ["submission_id": 8] as NSDictionary)
    }

    @Test
    func aCommentNamesItsSongAndGroup() throws {
        #expect(try json(NewCommentPayload(submissionID: 7, groupID: "g1", body: "gut")) as NSDictionary
            == ["submission_id": 7, "group_id": "g1", "body": "gut"] as NSDictionary)
    }

    /// The message keeps the id the app already shows it under.
    @Test
    func aChatMessageKeepsItsIDInLowerCase() throws {
        let id = UUID(uuidString: "5C1D3E2A-8B7F-4E1A-9D2C-0F3B4A5C6D7E")!
        let message = ChatMessage(
            id: id, authorTag: "DU", authorName: "Du", text: "", isFromCurrentUser: true,
            mentionedSubmissionID: 7)

        #expect(try json(NewChatPayload(message: message, groupID: "g1")) as NSDictionary == [
            "id": "5c1d3e2a-8b7f-4e1a-9d2c-0f3b4a5c6d7e", "group_id": "g1", "body": "",
            "mentioned_submission_id": 7,
        ] as NSDictionary)
    }

    @Test
    func aProfileEditSendsOnlyWhatChanged() throws {
        #expect(try json(ProfilePatch(name: "Lena", avatarPath: nil)) as NSDictionary
            == ["name": "Lena"] as NSDictionary)
        #expect(try json(ProfilePatch(name: nil, avatarPath: "u/a.jpg")) as NSDictionary
            == ["avatar_path": "u/a.jpg"] as NSDictionary)
    }

    @Test
    func anInviteDecodesFromTheServersShape() throws {
        let json = """
        {"code":"abcdef0123456789","group_id":"6F1C0000-0000-0000-0000-000000000000",
         "expires_at":"2026-09-24T09:51:31.123456+00:00"}
        """
        let invite = try BackendRecords.decoder.decode(InviteRecord.self, from: Data(json.utf8)).invite

        #expect(invite.code == "abcdef0123456789")
        #expect(invite.groupID == "6f1c0000-0000-0000-0000-000000000000")
        #expect(invite.expiresAt > Date(timeIntervalSince1970: 1_789_000_000))
    }
}

/// Pictures go up small: a phone photo is several megabytes, the bucket
/// takes five, and an avatar needs a fraction of it.
@Suite
struct ImageDownscaleTests {
    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(_ data: Data) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return (image.width, image.height)
    }

    @Test
    func aLargePictureComesBackAtMost1024PixelsAsJPEG() throws {
        let out = try #require(ImageDownscale.jpeg(from: png(width: 3000, height: 2000)))

        let size = try pixelSize(out)
        #expect(size.width == 1024)
        #expect(size.height == 683)
        #expect(Array(out.prefix(2)) == [0xFF, 0xD8])
    }

    @Test
    func aSmallPictureIsNotEnlarged() throws {
        let out = try #require(ImageDownscale.jpeg(from: png(width: 200, height: 100)))

        let size = try pixelSize(out)
        #expect(size.width == 200)
        #expect(size.height == 100)
    }

    @Test
    func somethingThatIsNoPictureGivesNothing() {
        #expect(ImageDownscale.jpeg(from: Data([1, 2, 3])) == nil)
    }
}

@Suite
@MainActor
struct ImageErrorMessageTests {
    @Test
    func anUnreadablePictureIsExplained() {
        #expect(PostSongModel.message(for: TodAppError.imageUnreadable)
            == "Dieses Bild lässt sich nicht verwenden. Versuch ein anderes.")
    }
}
