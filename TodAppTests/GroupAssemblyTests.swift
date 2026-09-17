import Foundation
import Testing
@testable import TodApp

/// Rows as the database hands them over, turned into the groups the screens
/// already know. No network: the rows are written out here.
@Suite
struct GroupAssemblyTests {
    private let me = "aaaaaaaa-0000-0000-0000-000000000001"
    private let lena = "bbbbbbbb-0000-0000-0000-000000000002"
    private let gone = "cccccccc-0000-0000-0000-000000000003"
    private let wg = "11111111-0000-0000-0000-00000000000a"
    private let band = "22222222-0000-0000-0000-00000000000b"

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    /// 17 September 2026, 14:00 in Berlin.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 14))!
    }

    private func at(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    // MARK: Decoding

    /// The shape PostgREST sends: embedded rows under the table's name,
    /// timestamps with microseconds and an offset, a hidden profile as null.
    @Test
    func aGroupWithItsMembersDecodesFromTheServersShape() throws {
        let json = """
        [{"id":"\(wg)","name":"WG Chaos","icon":"🏠","image_path":"\(wg)/a.jpg",
          "creator_id":"\(me)","invite_policy":"creator_only",
          "group_members":[
            {"user_id":"\(me)","profiles":{"name":"Lennet","avatar_path":null}},
            {"user_id":"\(gone)","profiles":null}]}]
        """
        let rows = try BackendRecords.decoder.decode([GroupRecord].self, from: Data(json.utf8))

        let row = try #require(rows.first)
        #expect(row.id == wg)
        #expect(row.imagePath == "\(wg)/a.jpg")
        #expect(row.creatorID == me)
        #expect(row.invitePolicy == "creator_only")
        #expect(row.members.map(\.userID) == [me, gone])
        #expect(row.members.first?.profile?.name == "Lennet")
        #expect(row.members.last?.profile == nil)
    }

    @Test
    func aSubmissionWithCommentsDecodesFromTheServersShape() throws {
        let json = """
        [{"id":42,"group_id":"\(wg)","poster_id":"\(lena)","track":"Nights","artist":"Frank Ocean",
          "service":"spotify","service_track_id":"7eqoqGkKwgOaWNNHx90uEZ",
          "page_url":"https://open.spotify.com/track/7eqoqGkKwgOaWNNHx90uEZ",
          "artwork_url":null,"duration_seconds":307,"isrc":"USUM71611513","apple_music_id":null,
          "section_start":60,"section_end":90.5,
          "posted_at":"2026-09-17T09:51:31.123456+00:00","round_day":"2026-09-17",
          "comments":[{"id":7,"author_id":"\(me)","body":"der Beat-Switch",
                       "created_at":"2026-09-17T10:00:00+00:00"}]}]
        """
        let rows = try BackendRecords.decoder.decode([SubmissionRecord].self, from: Data(json.utf8))

        let row = try #require(rows.first)
        #expect(row.id == 42)
        #expect(row.sectionEnd == 90.5)
        #expect(row.roundDay == "2026-09-17")
        #expect(abs(row.postedAt.timeIntervalSince(at(day: 17, hour: 11)) - (51 * 60 + 31.123456)) < 0.001)
        #expect(row.comments?.first?.body == "der Beat-Switch")
    }

    @Test
    func chatVotesAndGemsDecodeFromTheServersShape() throws {
        let chat = """
        [{"id":"5C1D3E2A-8B7F-4E1A-9D2C-0F3B4A5C6D7E","group_id":"\(wg)","author_id":"\(lena)",
          "body":"","mentioned_submission_id":42,"created_at":"2026-09-17T10:00:00.5+00:00"}]
        """
        let votes = """
        [{"submission_id":42,"group_id":"\(wg)","round_day":"2026-09-16","voter_id":"\(me)",
          "rating":-2,"note":null}]
        """
        let gems = """
        [{"voter_id":"\(me)","group_id":"\(wg)","round_day":"2026-09-16","submission_id":42}]
        """

        let message = try #require(try BackendRecords.decoder.decode([ChatRecord].self, from: Data(chat.utf8)).first)
        let vote = try #require(try BackendRecords.decoder.decode([VoteRecord].self, from: Data(votes.utf8)).first)
        let gem = try #require(try BackendRecords.decoder.decode([GemRecord].self, from: Data(gems.utf8)).first)

        #expect(message.mentionedSubmissionID == 42)
        #expect(message.body.isEmpty)
        #expect(vote.rating == -2)
        #expect(vote.roundDay == "2026-09-16")
        #expect(gem.submissionID == 42)
    }

    /// Postgres writes uuids in lower case, the app compares them as strings;
    /// an upper-case id from anywhere must not make someone a stranger.
    @Test
    func idsAreReadInLowerCase() throws {
        let json = """
        [{"id":"\(wg.uppercased())","name":"WG","icon":"🏠","image_path":null,
          "creator_id":"\(me.uppercased())","invite_policy":"everyone",
          "group_members":[{"user_id":"\(me.uppercased())","profiles":{"name":"L","avatar_path":null}}]}]
        """
        let row = try #require(try BackendRecords.decoder.decode([GroupRecord].self, from: Data(json.utf8)).first)

        #expect(row.id == wg)
        #expect(row.creatorID == me)
        #expect(row.members.first?.userID == me)
    }

    // MARK: Assembly

    private func groupRow(
        id: String, name: String, policy: String = "everyone",
        members: [MemberRecord], imagePath: String? = nil
    ) -> GroupRecord {
        GroupRecord(
            id: id, name: name, icon: "🏠", imagePath: imagePath, creatorID: me,
            invitePolicy: policy, members: members)
    }

    private func member(_ id: String, _ name: String?) -> MemberRecord {
        MemberRecord(userID: id, profile: name.map { ProfileRecord(id: nil, name: $0, avatarPath: nil, isPremium: nil) })
    }

    private func post(
        _ id: Int, in group: String, by poster: String, at date: Date,
        service: String? = nil, trackID: String? = nil, page: String? = nil,
        section: (Double?, Double?) = (nil, nil), comments: [CommentRecord]? = nil
    ) -> SubmissionRecord {
        SubmissionRecord(
            id: id, groupID: group, posterID: poster, track: "Song \(id)", artist: "Artist",
            service: service, serviceTrackID: trackID, pageURL: page, artworkURL: nil,
            durationSeconds: nil, isrc: nil, appleMusicID: nil,
            sectionStart: section.0, sectionEnd: section.1,
            postedAt: date, roundDay: RoundDayFixture.berlin(date), comments: comments)
    }

    private func assemble(
        _ groups: [GroupRecord], _ posts: [SubmissionRecord] = [], _ chat: [ChatRecord] = [],
        images: [String: Data] = [:]
    ) -> [Group] {
        GroupAssembly.groups(
            from: groups, submissions: posts, messages: chat, images: images,
            me: me, now: now, calendar: calendar)
    }

    @Test
    func postsAndMessagesLandInTheirOwnGroup() {
        let groups = assemble(
            [groupRow(id: wg, name: "WG", members: [member(me, "Lennet")]),
             groupRow(id: band, name: "Band", members: [member(me, "Lennet")])],
            [post(1, in: wg, by: me, at: at(day: 17, hour: 9)),
             post(2, in: band, by: me, at: at(day: 17, hour: 10))],
            [ChatRecord(id: UUID().uuidString, groupID: band, authorID: me, body: "hi",
                     mentionedSubmissionID: nil, createdAt: at(day: 17, hour: 11))])

        let byID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
        #expect(byID[wg]?.submissions.map(\.id) == [1])
        #expect(byID[band]?.submissions.map(\.id) == [2])
        #expect(byID[wg]?.chatMessages.isEmpty == true)
        #expect(byID[band]?.chatMessages.map(\.text) == ["hi"])
    }

    @Test
    func groupsAreOrderedByName() {
        let groups = assemble([
            groupRow(id: wg, name: "WG Chaos", members: []),
            groupRow(id: band, name: "Band", members: []),
        ])

        #expect(groups.map(\.name) == ["Band", "WG Chaos"])
    }

    @Test
    func theSignedInUserIsMarkedAndListedFirst() {
        let group = assemble([groupRow(
            id: wg, name: "WG", members: [member(lena, "Lena"), member(me, "Lennet")])]).first

        #expect(group?.members.map(\.id) == [me, lena])
        #expect(group?.members.map(\.isCurrentUser) == [true, false])
    }

    /// A member whose profile the server does not show still belongs to the
    /// group; the name says so rather than leaving a blank.
    @Test
    func aMemberWithoutAVisibleProfileIsStillListed() {
        let group = assemble([groupRow(id: wg, name: "WG", members: [member(gone, nil)])]).first

        #expect(group?.members.first?.name == "Jemand")
    }

    /// Streaks and "posted today" hang off these dates, and they come from the
    /// posts themselves -- the same rule as everywhere else in the app.
    @Test
    func postingDaysComeFromEachMembersOwnPosts() {
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [member(me, "Lennet"), member(lena, "Lena")])],
            [post(3, in: wg, by: lena, at: at(day: 17, hour: 9)),
             post(1, in: wg, by: me, at: at(day: 15, hour: 9)),
             post(2, in: wg, by: me, at: at(day: 16, hour: 9))]
        ).first

        let mine = group?.members.first { $0.id == me }
        let hers = group?.members.first { $0.id == lena }
        #expect(mine?.postedDates == [at(day: 15, hour: 9), at(day: 16, hour: 9)])
        #expect(hers?.postedDates == [at(day: 17, hour: 9)])
    }

    @Test
    func postsAreInTheOrderTheyWentUp() {
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [])],
            [post(2, in: wg, by: me, at: at(day: 17, hour: 10)),
             post(1, in: wg, by: lena, at: at(day: 16, hour: 10))]
        ).first

        #expect(group?.submissions.map(\.id) == [1, 2])
    }

    @Test
    func aCompleteSourceBecomesATrackSource() throws {
        let page = "https://open.spotify.com/track/abc"
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [])],
            [post(1, in: wg, by: me, at: now, service: "spotify", trackID: "abc", page: page),
             post(2, in: wg, by: me, at: now)]
        ).first

        let sourced = try #require(group?.submissions.first { $0.id == 1 })
        #expect(sourced.source == TrackSource(
            service: .spotify, serviceTrackID: "abc", pageURL: URL(string: page)!, artworkURL: nil))
        #expect(group?.submissions.first { $0.id == 2 }?.source == nil)
    }

    /// A service the app does not know is no source at all, not a crash.
    @Test
    func anUnknownServiceIsNoSource() {
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [])],
            [post(1, in: wg, by: me, at: now, service: "tidal", trackID: "x", page: "https://tidal.com/x")]
        ).first

        #expect(group?.submissions.first?.source == nil)
    }

    @Test
    func aSectionNeedsBothEnds() {
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [])],
            [post(1, in: wg, by: me, at: now, section: (60, 90)),
             post(2, in: wg, by: me, at: now, section: (60, nil))]
        ).first

        #expect(group?.submissions.first { $0.id == 1 }?.section == TrackSection(start: 60, end: 90))
        #expect(group?.submissions.first { $0.id == 2 }?.section == nil)
    }

    /// Without artwork the card needs a colour, and the same song keeps the
    /// same one -- keyed like a fresh post is.
    @Test
    func aPostsFallbackColourFollowsItsTrack() {
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [])],
            [post(1, in: wg, by: me, at: now, service: "spotify", trackID: "abc",
                  page: "https://open.spotify.com/track/abc")]
        ).first

        #expect(group?.submissions.first?.coverColorHex == CoverColor.hex(forTrack: "abc"))
    }

    @Test
    func commentsAreNamedAfterTheirAuthorAndInOrder() {
        let comments = [
            CommentRecord(id: 2, authorID: me, body: "zweiter", createdAt: at(day: 17, hour: 12)),
            CommentRecord(id: 1, authorID: lena, body: "erster", createdAt: at(day: 17, hour: 11)),
            CommentRecord(id: 3, authorID: gone, body: "dritter", createdAt: at(day: 17, hour: 13)),
        ]
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [member(me, "Lennet"), member(lena, "Lena")])],
            [post(1, in: wg, by: lena, at: now, comments: comments)]
        ).first

        let list = group?.submissions.first?.comments ?? []
        #expect(list.map(\.text) == ["erster", "zweiter", "dritter"])
        #expect(list.map(\.authorName) == ["Lena", "Lennet", "Jemand"])
        #expect(list.map(\.authorID) == [lena, me, gone])
    }

    @Test
    func chatMessagesSayWhoWroteThemAndRunOldestFirst() {
        let chat = [
            ChatRecord(id: "5C1D3E2A-8B7F-4E1A-9D2C-0F3B4A5C6D7E", groupID: wg, authorID: me,
                    body: "zweite", mentionedSubmissionID: nil, createdAt: at(day: 17, hour: 12)),
            ChatRecord(id: "6C1D3E2A-8B7F-4E1A-9D2C-0F3B4A5C6D7E", groupID: wg, authorID: lena,
                    body: "erste", mentionedSubmissionID: 7, createdAt: at(day: 17, hour: 11)),
        ]
        let group = assemble(
            [groupRow(id: wg, name: "WG", members: [member(me, "Lennet"), member(lena, "Lena")])],
            [], chat
        ).first

        let messages = group?.chatMessages ?? []
        #expect(messages.map(\.text) == ["erste", "zweite"])
        #expect(messages.map(\.authorName) == ["Lena", "Du"])
        #expect(messages.map(\.authorTag) == ["LE", "DU"])
        #expect(messages.map(\.isFromCurrentUser) == [false, true])
        #expect(messages.first?.mentionedSubmissionID == 7)
        #expect(messages.last?.id == UUID(uuidString: "5C1D3E2A-8B7F-4E1A-9D2C-0F3B4A5C6D7E"))
    }

    /// A round ends at midnight; the database never stores it.
    @Test
    func theRoundEndsAtTheNextMidnight() {
        let group = assemble([groupRow(id: wg, name: "WG", members: [])]).first

        #expect(group?.roundEndsAt == calendar.date(from: DateComponents(year: 2026, month: 9, day: 18)))
    }

    @Test
    func theInvitePolicyAndCreatorAreRead() {
        let groups = assemble([
            groupRow(id: wg, name: "A", policy: "creator_only", members: []),
            groupRow(id: band, name: "B", policy: "everyone", members: []),
        ])

        #expect(groups.map(\.invitePolicy) == [.creatorOnly, .everyone])
        #expect(groups.first?.creatorID == me)
        #expect(groups.first?.activeBattle == nil)
    }

    /// A picture the repository has fetched is matched to its group by path;
    /// one it could not fetch leaves the emoji to stand in.
    @Test
    func aFetchedPictureIsAttachedByItsPath() {
        let picture = Data([1, 2, 3])
        let groups = assemble(
            [groupRow(id: wg, name: "A", members: [], imagePath: "\(wg)/a.jpg"),
             groupRow(id: band, name: "B", members: [], imagePath: "\(band)/missing.jpg")],
            images: ["\(wg)/a.jpg": picture])

        #expect(groups.map(\.imageData) == [picture, nil])
    }
}

/// The database's own rule for a post's day, spelled out for the fixtures.
enum RoundDayFixture {
    static func berlin(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}
