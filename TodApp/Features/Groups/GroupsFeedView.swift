import SwiftUI

/// The groups screen, shaped after a messaging app's inbox: search on top, a
/// row of faces, then one row per group showing what was last posted there.
///
/// The shape is borrowed; the furniture mostly is not. The bubble above a face
/// has a counterpart here -- the song that person posted today -- so it stays.
/// The reference's folder chips have none and are left out.
struct GroupsFeedView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var playing: Submission?
    /// Set by a tap on someone in the story row: the feed of their round, at
    /// their card.
    @State private var feedTarget: FeedTarget?
    @State private var groupEntry: GroupEntry?

    private var groups: [Group] {
        GroupsFeed.ordered(GroupsFeed.matching(query, in: store.groups))
    }

    var body: some View {
        ScrollView {
            if store.groups.isEmpty {
                // Nothing to search or list yet.
                SwiftUI.Group {
                    if store.hasLoadedGroups {
                        NoGroupsView(entry: $groupEntry)
                    } else {
                        GroupsLoadingView()
                    }
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    searchField
                    storyRow
                    groupRows
                }
                .padding(.vertical, 12)
            }
        }
        .refreshable { await store.refresh() }
        .toolbar { GroupEntryMenu(entry: $groupEntry) }
        .sheet(item: $groupEntry) { GroupEntrySheet(entry: $0) }
        .dismissesKeyboardOnTap()
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle("Gruppen")
        .navigationDestination(item: $feedTarget) { target in
            SongFeedView(round: target.round, startAt: target.submissionID)
        }
        .sheet(item: $playing) { submission in
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.todTextFaint)
                // The field beside it announces itself.
                .accessibilityHidden(true)
            TextField("Gruppen suchen", text: $query)
                .font(.todBody(15))
                .foregroundStyle(Color.todText)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
        // The whole capsule, magnifier included: it reads as one field.
        .keepsKeyboardOnTap()
        .padding(.horizontal)
    }

    @ViewBuilder
    private var storyRow: some View {
        let members = GroupsFeed.storyMembers(across: store.groups)
        if !members.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(members) { member in
                        storyItem(member)
                    }
                }
                .padding(.horizontal)
            }
            // A swipe here moves the row, not the page.
            .claimsSidewaysSwipes()
        }
    }

    private func storyItem(_ member: Member) -> some View {
        let target = GroupsFeed.storyTarget(for: member, in: store.groups)
        let bubble = GroupsFeed.storyBubble(for: member, in: store.groups)

        return Button { open(target) } label: {
            VStack(spacing: 6) {
                // Room for a bubble above every circle, filled or not, so the
                // faces stay on one line.
                SwiftUI.Group {
                    if let bubble { songBubble(bubble) } else { Color.clear }
                }
                .frame(width: 78, height: 34)
                AvatarBadge(member: member, size: 62, showsPostedRing: true)
                Text(member.isCurrentUser ? "Du" : member.name)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
                    .lineLimit(1)
            }
            .frame(width: 78)
        }
        .buttonStyle(.plain)
        .disabled(target == nil)
        // The ring means "posted today" and the bubble names the song. Both
        // said out loud, because neither is heard.
        .accessibilityLabel(Spoken.storyMember(
            name: member.name,
            isCurrentUser: member.isCurrentUser,
            hasPostedToday: member.hasPostedToday,
            song: bubble.map { Spoken.song(track: $0.track, artist: $0.artist) }))
    }

    /// What someone posted today, small, above their circle.
    private func songBubble(_ bubble: GroupsFeed.StoryBubble) -> some View {
        VStack(spacing: 0) {
            Text(bubble.track)
                .font(.todBody(10, weight: .bold))
                .foregroundStyle(Color.todText)
            Text(bubble.artist)
                .font(.todBody(9))
                .foregroundStyle(Color.todTextDim)
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            LinearGradient(
                colors: [Color.todAccent.opacity(0.55), Color.todAccent2.opacity(0.35)],
                startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.todLine, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    /// Into the feed of that person's round, with their group selected -- the
    /// row spans every group, the feed shows one. A song older than yesterday
    /// is in no feed, so it opens on its own as before.
    private func open(_ target: GroupsFeed.StoryTarget?) {
        switch target {
        case .today(let groupID, let submissionID)?:
            store.selectGroup(groupID)
            feedTarget = FeedTarget(round: .running, submissionID: submissionID)
        case .yesterday(let groupID, let submissionID)?:
            store.selectGroup(groupID)
            feedTarget = FeedTarget(round: .revealed, submissionID: submissionID)
        case .older(let submissionID)?:
            playing = store.groups.flatMap(\.submissions).first { $0.id == submissionID }
        case nil:
            break
        }
    }

    private var groupRows: some View {
        LazyVStack(spacing: 10) {
            ForEach(groups) { group in
                NavigationLink {
                    // Straight into the chat: it is the group's hub now, and
                    // the menu of screens that used to sit here was a stop on
                    // the way to somewhere else.
                    ChatView(group: group)
                } label: {
                    GroupRow(group: group)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

}

private struct GroupRow: View {
    let group: Group
    /// The last message seen in this group's chat (`ChatReadMarks`).
    @AppStorage private var lastSeenID: String

    init(group: Group) {
        self.group = group
        _lastSeenID = AppStorage(wrappedValue: "", ChatReadMarks.key(for: group.id))
    }

    private var activity: GroupsFeed.Activity? { GroupsFeed.latestActivity(in: group) }
    private var time: String? { activity?.at.map { GroupsFeed.timeLabel(for: $0) } }
    private var hasUnread: Bool { GroupsFeed.hasUnread(in: group, lastSeenID: lastSeenID) }

    var body: some View {
        HStack(spacing: 12) {
            picture
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Text(GroupsFeed.previewText(for: group))
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextDim)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if let time {
                    Text(time)
                        .font(.todMono(11))
                        .foregroundStyle(hasUnread ? Color.todAccent : Color.todTextFaint)
                }
                if hasUnread {
                    Circle()
                        .fill(Color.todAccent)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.todLine, lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16))
        // One row, one sentence -- rather than a name, a preview and a time
        // arriving as three separate stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Spoken.groupRow(
            name: group.name,
            preview: GroupsFeed.previewText(for: group),
            time: time) + (hasUnread ? ", neue Nachrichten" : ""))
    }

    /// The group's own picture when it has one, its emoji when it does not --
    /// a grey square would say less than the symbol the group already picked.
    @ViewBuilder
    private var picture: some View {
        GroupAvatar(group: group, size: 52)
    }
}

/// Where the story row -- and a song mentioned in chat -- navigates: a round,
/// and the card to open it at.
struct FeedTarget: Hashable {
    let round: SongFeedView.Round
    let submissionID: Int
}
