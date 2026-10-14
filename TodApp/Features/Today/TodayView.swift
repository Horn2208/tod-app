import SwiftUI

/// Home. One feed down the screen, a song per screen: the one you put up
/// today, then the others' songs, each a full-screen page you rate right
/// where it is -- the scrolling is the rating -- and at the end where the
/// round stands.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFrontmostPage) private var isFrontmostPage
    @Environment(\.scenePhase) private var scenePhase
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
    /// Yesterday's ranking over Home (`RankingOverlay`).
    @State private var isShowingRanking = false
    /// The group whose votes and scores have arrived: the ranking waits for
    /// them rather than counting up to zeroes.
    @State private var scoresLoadedFor: String?
    /// Whether Home itself is on screen, nothing pushed on top of it.
    @State private var isOnScreen = false
    /// Bumped when a seen mark is set, so the check below reads it again.
    @State private var seenMarkTick = 0
    /// The bars around the page: navigation on top, tab bar and home
    /// indicator below. The pages run underneath them, their words do not.
    @State private var insets = EdgeInsets()
    /// The page the feed has come to rest on; nil before any scrolling.
    @State private var settledPage: Int?
    /// Taps on a page's cover, per song: each one presses its play button.
    @State private var coverTaps: [Int: Int] = [:]
    /// The round's card after the last page: no song plays there.
    private static let roundCardID = -1

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
    /// Every page of the feed: your song, then the others' (`HomeFeed`).
    private var pages: [Submission] {
        (mySong.map { [$0] } ?? []) + otherPages
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if group != nil, !pages.isEmpty {
                feed
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        if let group {
                            if store.groups.count > 1 { GroupSwitcherBar() }
                            roundCard(group)
                        } else if store.hasLoadedGroups {
                            NoGroupsView(entry: $groupEntry)
                        } else {
                            GroupsLoadingView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }

            if let noteFor {
                NoteComposer(submission: noteFor) { self.noteFor = nil }
                    .id(noteFor.id)
            }
        }
        // The switcher stays where it is while the group changes; only its
        // ring moves. Over the first page only, out of the way below it.
        .overlay(alignment: .top) {
            if group != nil, !pages.isEmpty, store.groups.count > 1 {
                GroupSwitcherBar()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .opacity(isOnFirstPage ? 1 : 0)
                    .allowsHitTesting(isOnFirstPage)
                    .accessibilityHidden(!isOnFirstPage)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isOnFirstPage)
            }
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
        .refreshable { await store.refresh() }
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle(group?.name ?? "Home")
        // A title over the cover rather than a large one above it; the bar
        // stays clear, the page's own scrim keeps it readable.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
            scoresLoadedFor = store.currentGroupID
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
        // Presented without the sheet's slide: the backdrop is simply there,
        // and the card brings its own motion.
        .onChange(of: isRankingDue, initial: true) { _, due in
            guard due != isShowingRanking else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = due
            withTransaction(transaction) { isShowingRanking = due }
        }
        .fullScreenCover(isPresented: $isShowingRanking) {
            RankingOverlayView(
                groupName: group?.name ?? "",
                rows: rankingRows,
                onClose: markRankingSeen,
                onComments: {
                    markRankingSeen()
                    isShowingReveal = true
                })
                .presentationBackground(.clear)
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
        .sheet(item: $openSong) { submission in
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
    }

    // MARK: - Yesterday's ranking

    private var rankingRows: [RankingOverlay.Row] {
        RankingOverlay.ranking(
            scores: store.roundScores, submissions: store.revealedSubmissions, userID: store.profile.id)
    }

    /// Up once per group and revealed day, as soon as Home is what is on
    /// screen: not over the Posten page, a sheet or a pushed screen.
    private var isRankingDue: Bool {
        _ = seenMarkTick
        let groupID = store.currentGroupID
        let blocked = !isFrontmostPage || !isOnScreen || scoresLoadedFor != groupID
            || isShowingStreakCalendar || openSong != nil
            || groupEntry != nil || noteFor != nil || isShowingReveal
        // Already up: only a seen mark takes it down, not its own cover
        // making Home "not on screen".
        let revealedDay = store.revealedSubmissions.isEmpty ? nil : RoundVisibility.revealedDay()
        return RankingOverlay.shouldShowRanking(
            revealedDay: revealedDay,
            lastSeen: RankingSeenMarks.lastSeen(in: groupID),
            isBlocked: blocked && !isShowingRanking)
    }

    private func markRankingSeen() {
        RankingSeenMarks.markSeen(RoundVisibility.revealedDay(), in: store.currentGroupID)
        seenMarkTick += 1
    }

    // MARK: - The feed

    /// The pages, one screen each, running under the bars; the round's
    /// status after the last.
    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a handful of pages, and a lazy stack's guessed
                // heights put the jump to the first unrated song a page off.
                VStack(spacing: 0) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, song in
                        page(song, isFirst: index == 0, proxy: proxy)
                            .id(song.id)
                    }
                    if let group {
                        roundCard(group)
                            .padding(.horizontal)
                            .padding(.top, 16)
                            .padding(.bottom, insets.bottom + 16)
                            .id(Self.roundCardID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            // Read, never set: a set position puts a page under the bar
            // (UEBERGABE, paged feeds).
            .scrollPosition(id: $settledPage)
            .scrollIndicators(.hidden)
            .dismissesKeyboardOnTap()
            .ignoresSafeArea(.container, edges: .vertical)
            // The pages keep their size while the keyboard is up; the reason
            // is written in the bar underneath (as in `SongFeedView`).
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// A song as a whole screen: the cover filling it, dark at both ends so
    /// the bars and the words read on any cover, and the song's controls at
    /// the foot -- rating for the others' songs, the hint to them on yours.
    private func page(_ song: Submission, isFirst: Bool, proxy: ScrollViewProxy) -> some View {
        let isOwn = store.isOwn(song)
        return ZStack {
            // The same cover as everywhere (`CrossfadeCover`): the old one
            // stays until the new one is there, then fades over it.
            Color.clear
                .overlay {
                    CrossfadeCover(url: song.coverURL, placeholderHex: song.coverColorHex)
                }
                .clipped()
                .contentShape(Rectangle())
                // Play and pause, as on a reel; the button below says the
                // same to VoiceOver, so the cover itself stays out of it.
                .onTapGesture { coverTaps[song.id, default: 0] += 1 }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.35), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: insets.top + (isFirst ? 150 : 60))
                Spacer(minLength: 0)
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.8), .black.opacity(0.92)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: insets.bottom + (isOwn ? 380 : 480))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Spacer(minLength: 0)
                titles(song)
                HStack(spacing: 18) {
                    QuickPlayButton(
                        submission: song,
                        autoplay: playingPage == song.id,
                        toggleTick: coverTaps[song.id, default: 0])
                    Button("Kommentare") { openSong = song }
                        .font(.todBody(15, weight: .semibold))
                        .foregroundStyle(Color.todText)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 44)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
                }
                if isOwn {
                    if let rateLine {
                        rateHint(rateLine, proxy: proxy)
                    }
                } else {
                    RatingControls(submission: song, onWriteNote: { noteFor = song })
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, insets.top + 8)
            .padding(.bottom, insets.bottom + 12)
            .animation(reduceMotion ? nil : .snappy, value: rateLine)
        }
        .containerRelativeFrame(.vertical)
        .scrollReveal()
    }

    private var isOnFirstPage: Bool {
        settledPage == nil || settledPage == pages.first?.id
    }

    /// The page whose song sounds by itself (`HomeFeed.playingPage`):
    /// nothing while Home is not what is on screen.
    private var playingPage: Int? {
        let blocked = !isFrontmostPage || !isOnScreen || scenePhase != .active
            || isShowingRanking || isShowingStreakCalendar || openSong != nil
            || groupEntry != nil || isShowingReveal
        return HomeFeed.playingPage(settled: settledPage, pages: pages.map(\.id), isBlocked: blocked)
    }

    /// Title, artist and, on a post with one, the picked stretch.
    private func titles(_ song: Submission) -> some View {
        VStack(spacing: 4) {
            Text(song.track)
                .font(.todSerif(.title))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .todGlow(color: .todSongGlow(hex: song.coverColorHex))
            Text(song.artist)
                .font(.todBody(15))
                .foregroundStyle(.white.opacity(0.8))
            if let section = song.section {
                Text("Abschnitt \(timestamp(section.start))–\(timestamp(section.end))")
                    .font(.todMono(11))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
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
            .foregroundStyle(Color.todText)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color.todAccent.opacity(0.85), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line)
        .accessibilityHint("Springt zum ersten Song")
        .accessibilityAddTraits(.isButton)
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

    private func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

}

private extension View {
    /// Comes in as it scrolls into view, a fade only: on a page as large as
    /// the screen, a rise or a shrink opened gaps at the edges. The same with
    /// Reduce Motion, since a fade is not motion.
    func scrollReveal() -> some View {
        scrollTransition(.interactive) { content, phase in
            content.opacity(1 - abs(phase.value) * 0.5)
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
