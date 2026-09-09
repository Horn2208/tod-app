import SwiftUI

/// The groups screen, shaped after a messaging app's inbox: search on top, a
/// row of faces, then one row per group showing what was last posted there.
///
/// The shape is borrowed; the furniture is not. The reference screen carries
/// note pills above its avatars and folder chips below them -- features of that
/// app with no counterpart here. Inventing a use for them would add surface
/// nobody asked for.
struct GroupsFeedView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var playing: Submission?

    private var groups: [Group] {
        GroupsFeed.ordered(GroupsFeed.matching(query, in: store.groups))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                searchField
                storyRow
                groupRows
            }
            .padding(.vertical, 12)
        }
        .background(Color.todBackground)
        .navigationTitle("Gruppen")
        .sheet(item: $playing) { submission in
            if let source = submission.source {
                TrackPlayerSheet(
                    candidateTitle: submission.track,
                    artist: submission.artist,
                    source: source,
                    section: submission.section,
                    capabilities: store.capabilities,
                    provider: store.provider,
                    currentlyPlaying: store.currentlyPlaying
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.todTextFaint)
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
        .padding(.horizontal)
    }

    @ViewBuilder
    private var storyRow: some View {
        let members = GroupsFeed.storyMembers(across: store.groups)
        if !members.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(members) { member in
                        Button { playing = songOfTheDay(for: member) } label: {
                            VStack(spacing: 6) {
                                AvatarBadge(member: member, size: 62, showsPostedRing: true)
                                Text(member.isCurrentUser ? "Du" : member.name)
                                    .font(.todBody(12))
                                    .foregroundStyle(Color.todTextDim)
                                    .lineLimit(1)
                            }
                            .frame(width: 70)
                        }
                        .buttonStyle(.plain)
                        .disabled(songOfTheDay(for: member) == nil)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var groupRows: some View {
        LazyVStack(spacing: 2) {
            ForEach(groups) { group in
                NavigationLink {
                    GroupDetailView(group: group)
                } label: {
                    GroupRow(group: group)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Whatever this person put up most recently. Only a submission with a
    /// source can be played, so one without stays untappable rather than
    /// opening an empty sheet.
    private func songOfTheDay(for member: Member) -> Submission? {
        store.groups
            .flatMap(\.submissions)
            .filter { $0.posterID == member.id && $0.source != nil }
            .max { $0.postedAt < $1.postedAt }
    }
}

private struct GroupRow: View {
    let group: Group

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
            if let latest = GroupsFeed.latestSubmission(in: group) {
                Text(latest.postedAt, style: .time)
                    .font(.todMono(11))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// The group's own picture when it has one, its emoji when it does not --
    /// a grey square would say less than the symbol the group already picked.
    @ViewBuilder
    private var picture: some View {
        if let data = group.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.todSurface2)
                .overlay(Text(group.icon).font(.system(size: 24)))
                .frame(width: 52, height: 52)
        }
    }
}
