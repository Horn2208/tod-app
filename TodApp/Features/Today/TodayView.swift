import SwiftUI

/// Home. Two things matter here: the song you put up today, and how many days
/// in a row you have managed it. Everything else is a tab away.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var isPlayingSheetOpen = false
    @State private var isShowingStreakCalendar = false
    /// Rating the day's songs, from the round card.
    @State private var isShowingFeed = false
    /// From the round card on to yesterday's reveal.
    @State private var isShowingReveal = false
    /// Starting or joining a group, when there is none yet.
    @State private var groupEntry: GroupEntry?

    private var group: Group? { store.currentGroup }
    private var me: Member? { group.flatMap(HomeToday.me) }
    private var mySong: Submission? {
        group.flatMap { HomeToday.mySubmission(in: $0, userID: store.profile.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if group != nil {
                    if store.groups.count > 1 {
                        GroupSwitcherBar()
                    }
                    // What belongs to the chosen group fades across when the
                    // group changes, with the switcher's own timing, instead
                    // of jumping. The streak is rebuilt per group and fades;
                    // the song card is not, so its cover and glow can carry
                    // over into the next group's (`CrossfadeCover`,
                    // `CoverTint`) rather than starting from nothing.
                    VStack(spacing: 22) {
                        Button { isShowingStreakCalendar = true } label: { streak }
                            .buttonStyle(.plain)
                            .accessibilityHint("Öffnet den Kalender")
                            .id(store.currentGroupID)
                            .transition(.opacity)
                        if let song = mySong {
                            songCard(song)
                                .transition(.opacity)
                        }
                        if let group {
                            roundCard(group)
                                .id(store.currentGroupID)
                                .transition(.opacity)
                        }
                    }
                } else if store.hasLoadedGroups {
                    NoGroupsView(entry: $groupEntry)
                } else {
                    GroupsLoadingView()
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .animation(.snappy, value: store.currentGroupID)
        }
        .refreshable { await store.refresh() }
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle(group?.name ?? "Home")
        .sheet(item: $groupEntry) { GroupEntrySheet(entry: $0) }
        .sheet(isPresented: $isShowingStreakCalendar) {
            NavigationStack {
                StreakCalendarView(
                    postedDates: me?.postedDates ?? [],
                    currentStreak: me?.currentStreak ?? 0)
            }
            .presentationBackground(Color.todBackground)
        }
        .navigationDestination(isPresented: $isShowingFeed) {
            SongFeedView(round: .running)
        }
        .navigationDestination(isPresented: $isShowingReveal) {
            SongFeedView(round: .revealed)
        }
        .sheet(isPresented: $isPlayingSheetOpen) {
            if let song = mySong {
                SongDetailView(submission: song)
                    .presentationDetents([.large])
                    .presentationBackground(Color.todBackground)
            }
        }
    }

    // MARK: - The group's round

    /// Where the round stands for the whole group, and the way on: rating
    /// while there is something to rate, the reveal once yesterday is out.
    /// The countdown moves on by the minute.
    private func roundCard(_ group: Group) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = HomeToday.status(
                in: group, userID: store.profile.id,
                rated: Set(store.myVotes.ratings.keys), now: context.date)
            VStack(spacing: 12) {
                Text(HomeToday.line(status))
                    .font(.todBody(14))
                    .foregroundStyle(Color.todTextDim)
                    .multilineTextAlignment(.center)
                if status.toRate > 0 {
                    Button("Jetzt bewerten") { isShowingFeed = true }
                        .buttonStyle(TodPrimaryButtonStyle())
                } else if status.revealed > 0 {
                    Button("Gestern ist aufgedeckt") { isShowingReveal = true }
                        .font(.todBody(15, weight: .semibold))
                        .foregroundStyle(Color.todText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(18)
            .todGlassCard(radius: 20, clipsContent: false)
        }
    }

    // MARK: - Streak

    private var streak: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(me?.currentStreak ?? 0)")
                    .font(.todDisplay(56))
            }
            // The one number in the app that gets a sheen rather than a flat
            // fill, alongside the top of the leaderboard.
            .foregroundStyle(Self.streakSheen)
            Text(streakWording)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .todGlassCard(radius: 20)
        // "5 Tage in Folge" in one go, rather than a bare number and then a
        // line that explains it.
        .accessibilityElement(children: .combine)
    }

    /// The cover's colour behind the card, so every posted song lights its own
    /// card instead of all of them wearing the same pink.
    ///
    /// A gradient rather than a blurred circle: it is painted inside its own
    /// frame, needs no clipping to stay in the card, and costs no blur pass.
    private func glow(_ tint: Color) -> some View {
        RadialGradient(
            colors: [tint.opacity(0.65), .clear],
            center: .top,
            startRadius: 0,
            endRadius: 260
        )
    }

    /// Streak orange into a warmer highlight -- the flame's own colour, not
    /// gold: gold reads as an award, and a run of days is not one.
    static let streakSheen = LinearGradient(
        colors: [Color.todStreak, Color(hex: "#ffb178")],
        startPoint: .top,
        endPoint: .bottom
    )

    private var streakWording: String {
        switch me?.currentStreak ?? 0 {
        case 0: "Noch keine Serie. Heute fängt eine an."
        case 1: "Tag in Folge"
        default: "Tage in Folge"
        }
    }

    // MARK: - Dein Song

    /// Lit in the cover's own colour once the cover has been read
    /// (`CoverTint`), in the track's derived colour until then.
    private func songCard(_ song: Submission) -> some View {
        CoverTint(artworkURL: song.coverURL, fallbackHex: song.coverColorHex) { tint in
            songCard(song, tint: tint)
        }
    }

    private func songCard(_ song: Submission, tint: Color) -> some View {
        VStack(spacing: 14) {
            // The old cover stays until the new one is there, then fades
            // over it -- no flash of the flat colour between two songs.
            // A share of the screen's width rather than 220 points, as in
            // the feed: neither most of an SE nor a stamp on a Pro Max.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.58, 340) }
                .overlay { CrossfadeCover(url: song.coverURL, placeholderHex: song.coverColorHex) }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                // The cover opens the song, with its player and what was said.
                .contentShape(Rectangle())
                .onTapGesture { isPlayingSheetOpen = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(song.track) öffnen")

            // The words belong to one song and fade across to the next.
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    Text(song.track)
                        .font(.todDisplay(24))
                        .foregroundStyle(Color.todText)
                        .multilineTextAlignment(.center)
                    Text(song.artist)
                        .font(.todBody(15))
                        .foregroundStyle(Color.todTextDim)
                }

                if let section = song.section {
                    Text("Abschnitt \(timestamp(section.start))–\(timestamp(section.end))")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                }
            }
            .id(song.id)
            .transition(.opacity)

            // Play right here, like on the rating cards (`QuickPlayButton`);
            // the song itself -- player and comments -- behind the cover and
            // the quieter button beside it.
            HStack(spacing: 18) {
                QuickPlayButton(submission: song)
                Button("Kommentare") { isPlayingSheetOpen = true }
                    .font(.todBody(15, weight: .semibold))
                    .foregroundStyle(Color.todText)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
            }
        }
        // As wide as the cards above it; the wide button used to set this.
        .frame(maxWidth: .infinity)
        .padding(22)
        // Glass first, then the colour behind it: each `.background` goes
        // behind the last, so the material has to be applied first for the
        // glow to end up *under* it and shimmer through rather than wash over
        // it.
        .background(.ultraThinMaterial)
        .background { glow(tint) }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
        // The song's own colour, blurred out behind the card, so today's post
        // looks like itself rather than like every other card in the app.
        .background(
            tint
                .blur(radius: 60)
                .opacity(0.55)
                .padding(-30)
        )
    }

    private func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

}

struct TodPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// A nested view, because `isEnabled` reaches a button style only through a
    /// real view's environment -- reading it on the style itself never sees it,
    /// which is how a disabled button ended up looking pressable.
    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.todBody(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(background)
                .foregroundStyle(isEnabled ? Color.todBackground : Color.todTextFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private var background: Color {
            guard isEnabled else { return .todSurface2 }
            return Color.todAccent.opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
