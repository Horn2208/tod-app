import SwiftUI

/// Home. One feed down the screen: the song you put up today, then the
/// songs the others put up, each a page you rate right where it is -- the
/// scrolling is the rating -- and at the end where the round stands.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlayingSheetOpen = false
    @State private var isShowingStreakCalendar = false
    /// From the round's status line on to yesterday's reveal.
    @State private var isShowingReveal = false
    /// Starting or joining a group, when there is none yet.
    @State private var groupEntry: GroupEntry?
    /// A song of the feed opened, with its player and comments.
    @State private var openSong: Submission?
    /// The page whose reason is being written, in the bar above the keyboard.
    @State private var noteFor: Submission?
    /// What was rated when the feed was laid out (`HomeFeed.pages`): a page
    /// stays where it is while it is being rated.
    @State private var ratedWhenLaidOut: Set<Int> = []
    /// The song card takes the room between the group switcher and the tab
    /// bar: the visible height less what sits above the card. Nothing measured
    /// yet gives the floor; on tiny screens the floor wins and the page scrolls.
    @State private var viewportHeight: CGFloat = 0
    @State private var cardTop: CGFloat = 0
    private static let contentSpace = "homeContent"
    private static let minCardHeight: CGFloat = 380
    /// The hint under the song card, and the gap above it.
    private static let hintRoom: CGFloat = 58
    private var cardHeight: CGFloat {
        max(Self.minCardHeight, viewportHeight - cardTop - 16 - (rateLine == nil ? 0 : Self.hintRoom))
    }

    private var group: Group? { store.currentGroup }
    private var me: Member? { group.flatMap(HomeToday.me) }
    private var mySong: Submission? {
        group.flatMap { HomeToday.mySubmission(in: $0, userID: store.profile.id) }
    }
    private var rated: Set<Int> { Set(store.myVotes.ratings.keys) }
    /// Everyone else's songs today, in feed order.
    private var otherPages: [Submission] {
        HomeFeed.pages(running: store.runningSubmissions, userID: store.profile.id, rated: ratedWhenLaidOut)
            .filter { !store.isOwn($0) }
    }
    private var toRate: Int {
        store.votableSubmissions.filter { !rated.contains($0.id) }.count
    }
    private var rateLine: String? { HomeFeed.rateLine(toRate: toRate) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 14) {
                        if group != nil {
                            header(proxy)
                            // What belongs to the chosen group fades across
                            // when the group changes, with the switcher's own
                            // timing, instead of jumping.
                            ForEach(otherPages) { submission in
                                songPage(submission)
                            }
                            if let group {
                                roundCard(group)
                                    .id(store.currentGroupID)
                                    .transition(.opacity)
                                    .scrollReveal(reduceMotion: reduceMotion)
                            }
                        } else if store.hasLoadedGroups {
                            NoGroupsView(entry: $groupEntry)
                        } else {
                            GroupsLoadingView()
                        }
                    }
                    .scrollTargetLayout()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .animation(.snappy, value: store.currentGroupID)
                    .coordinateSpace(name: Self.contentSpace)
                }
                // Each song comes to rest as a page, top edge under the bar.
                .scrollTargetBehavior(.viewAligned)
                .dismissesKeyboardOnTap()
            }
            // The pages keep their size while the keyboard is up; the reason
            // is written in the bar underneath (as in `SongFeedView`).
            .ignoresSafeArea(.keyboard, edges: .bottom)

            if let noteFor {
                NoteComposer(submission: noteFor) { self.noteFor = nil }
                    .id(noteFor.id)
            }
        }
        // The scroll view's own height is already the room between the
        // navigation bar and the tab bar's reserved strip.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .refreshable { await store.refresh() }
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle(group?.name ?? "Home")
        .toolbar {
            if group != nil {
                ToolbarItem(placement: .topBarLeading) { streakBadge }
            }
        }
        // The ratings the pages show, for the group on screen; the order is
        // laid out once they are in, and again on every return to Home.
        .task(id: store.currentGroupID) {
            await store.loadMyVotes()
            ratedWhenLaidOut = rated
        }
        .sheet(item: $groupEntry) { GroupEntrySheet(entry: $0) }
        .sheet(isPresented: $isShowingStreakCalendar) {
            NavigationStack {
                StreakCalendarView(
                    postedDates: me?.postedDates ?? [],
                    currentStreak: me?.currentStreak ?? 0)
            }
            .presentationBackground(Color.todBackground)
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
        .sheet(item: $openSong) { submission in
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
    }

    /// The switcher, your song and the hint under it: one stop of the feed,
    /// so the first swipe goes from here straight to the first page.
    private func header(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 14) {
            if store.groups.count > 1 {
                GroupSwitcherBar()
            }
            if let song = mySong {
                songCard(song)
                    .transition(.opacity)
            }
            if let rateLine {
                rateHint(rateLine, proxy: proxy)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: rateLine)
        .scrollReveal(reduceMotion: reduceMotion)
    }

    /// "2 Songs warten auf deine Bewertung", and a tap goes down to the first
    /// of them.
    private func rateHint(_ line: String, proxy: ScrollViewProxy) -> some View {
        Button {
            guard let first = HomeFeed.firstUnrated(
                in: otherPages, userID: store.profile.id, rated: rated) else { return }
            withAnimation(reduceMotion ? nil : .snappy) {
                proxy.scrollTo(first, anchor: .top)
            }
        } label: {
            HStack(spacing: 6) {
                Text(line)
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .font(.todBody(14, weight: .semibold))
            .foregroundStyle(Color.todAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
        .accessibilityHint("Springt zum ersten Song")
        .accessibilityAddTraits(.isButton)
    }

    /// Someone else's song as a page of the feed: the same card as in the
    /// rating feed, rating and all, one screen tall.
    private func songPage(_ submission: Submission) -> some View {
        SongCard(
            submission: submission,
            round: .running,
            onOpen: { openSong = submission },
            onWriteNote: { noteFor = submission })
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5))
            // One page per screen, less the gap to the next, so the next one
            // starts right at the bottom edge rather than peeking in.
            .containerRelativeFrame(.vertical) { height, _ in max(Self.minCardHeight, height - 46) }
            .id(submission.id)
            .scrollReveal(reduceMotion: reduceMotion)
    }

    // MARK: - The group's round

    /// Where the round stands for the whole group. The countdown moves on by
    /// the minute. Once yesterday is revealed the line is the way to it;
    /// before, it is only a line.
    private func roundCard(_ group: Group) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let status = HomeToday.status(
                in: group, userID: store.profile.id,
                rated: rated, now: context.date)
            let line = Text(HomeToday.line(status))
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(18)
            if status.revealed > 0 {
                Button { isShowingReveal = true } label: {
                    HStack(spacing: 8) {
                        line
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.todTextFaint)
                            .padding(.trailing, 16)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .todGlassCard(radius: 20, clipsContent: false)
                .accessibilityHint("Öffnet die Auflösung von gestern")
            } else {
                line.todGlassCard(radius: 20, clipsContent: false)
            }
        }
    }

    // MARK: - Streak

    /// A small pill in the bar's leading corner; it opens the calendar. Shown
    /// at 0 as well, as the old card was, so the calendar stays reachable.
    private var streakBadge: some View {
        let days = me?.currentStreak ?? 0
        return Button { isShowingStreakCalendar = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(days)")
                    .font(.todDisplay(17))
                    .foregroundStyle(Self.streakSheen)
                Text(days == 1 ? "Tag" : "Tage")
                    .font(.todBody(11))
                    .foregroundStyle(Color.todTextDim)
            }
            // The bar draws the glass pill itself; unsized, it squeezes the
            // label into a circle.
            .fixedSize()
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(days == 1 ? "1 Tag in Folge" : "\(days) Tage in Folge")
        .accessibilityHint("Öffnet den Kalender")
    }

    /// Streak orange into a warmer highlight -- the flame's own colour, not
    /// gold: gold reads as an award, and a run of days is not one.
    static let streakSheen = LinearGradient(
        colors: [Color.todStreak, Color(hex: "#ffb178")],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Dein Song

    /// Lit in the cover's own colour once the cover has been read
    /// (`CoverTint`), in the track's derived colour until then.
    private func songCard(_ song: Submission) -> some View {
        CoverTint(artworkURL: song.coverURL, fallbackHex: song.coverColorHex) { tint in
            songCard(song, tint: tint)
        }
    }

    private func songCard(_ song: Submission, tint: Color) -> some View {
        // An empty frame sets the size; the cover is only painted into it, so
        // an aspect-filled picture cannot widen the card past its neighbours.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .overlay { cardFace(song) }
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
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.contentSpace)).minY } action: {
                cardTop = $0
            }
    }

    private func cardFace(_ song: Submission) -> some View {
        ZStack(alignment: .bottom) {
            // The cover fills the whole card; the old one stays until the new
            // one is there, then fades over it. Tapping it opens the song,
            // with its player and what was said.
            CrossfadeCover(url: song.coverURL, placeholderHex: song.coverColorHex)
                .contentShape(Rectangle())
                .onTapGesture { isPlayingSheetOpen = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(song.track) öffnen")

            // Dark at the foot so the white words read on any cover.
            LinearGradient(
                colors: [.clear, .black.opacity(0.55), .black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                // The words belong to one song and fade across to the next.
                VStack(spacing: 14) {
                    VStack(spacing: 4) {
                        Text(song.track)
                            .font(.todSerif(.title))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .todGlow(color: .todSongGlow(hex: song.coverColorHex))
                        Text(song.artist)
                            .font(.todBody(15))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    if let section = song.section {
                        Text("Abschnitt \(timestamp(section.start))–\(timestamp(section.end))")
                            .font(.todMono(11))
                            .foregroundStyle(.white.opacity(0.65))
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
            .padding(22)
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

}

private extension View {
    /// Comes in as it scrolls into view -- fading up, rising a little, growing
    /// from just under full size -- and goes the same way out. With Reduce
    /// Motion, the fade alone.
    func scrollReveal(reduceMotion: Bool) -> some View {
        scrollTransition(.interactive) { content, phase in
            content
                .opacity(1 - abs(phase.value) * 0.85)
                .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.06)
                .offset(y: reduceMotion ? 0 : phase.value * 24)
        }
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
