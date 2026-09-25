import SwiftUI

/// Home. Two things matter here: the song you put up today, and how many days
/// in a row you have managed it. Everything else is a tab away.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var isPosting = false
    @State private var isPlayingSheetOpen = false
    @State private var isShowingStreakCalendar = false
    /// Set when a post lands, and Home carries on straight into rating the
    /// day's songs -- posting and rating are one habit, not two errands.
    @State private var isShowingFeed = false
    /// Which song was yours when the post sheet opened, so its closing can tell
    /// a new post from a cancelled sheet.
    @State private var songBeforePosting: Int?
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
                    // of jumping.
                    VStack(spacing: 22) {
                        Button { isShowingStreakCalendar = true } label: { streak }
                            .buttonStyle(.plain)
                            .accessibilityHint("Öffnet den Kalender")
                        if let song = mySong {
                            songCard(song)
                        } else {
                            postPrompt
                        }
                    }
                    .id(store.currentGroupID)
                    .transition(.opacity)
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
        .navigationTitle("Home")
        .sheet(item: $groupEntry) { GroupEntrySheet(entry: $0) }
        .sheet(isPresented: $isPosting, onDismiss: {
            if let posted = mySong?.id, posted != songBeforePosting {
                isShowingFeed = true
            }
        }) { PostSongView() }
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
        .sheet(isPresented: $isPlayingSheetOpen) {
            if let song = mySong {
                SongDetailView(submission: song)
                    .presentationDetents([.large])
                    .presentationBackground(Color.todBackground)
            }
        }
    }

    // MARK: - Streak

    private var streak: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // SF Symbols rather than emoji: an emoji brings its own colour
                // and its own look per platform, and the streak has a token of
                // its own to wear.
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    // The wording under the number carries the meaning.
                    .accessibilityHidden(true)
                Text("\(me?.currentStreak ?? 0)")
                    .font(.todDisplay(56))
            }
            // The one number in the app that gets a sheen rather than a flat
            // fill, alongside the top of the leaderboard. Applied to the pair
            // so the flame and the number are lit by the same light.
            .foregroundStyle(Self.streakSheen)
            Text(streakWording)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
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
            AsyncImage(url: song.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(hex: song.coverColorHex))
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            // The cover opens the song, with its player and what was said.
            .contentShape(Rectangle())
            .onTapGesture { isPlayingSheetOpen = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(song.track) öffnen")

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

    // MARK: - Noch nichts gepostet

    private var postPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 38))
                .foregroundStyle(Color.todAccent)
                .accessibilityHidden(true)
            Text("Heute noch nichts von dir")
                .font(.todDisplay(22))
                .foregroundStyle(Color.todText)
            Text("Ein Song pro Tag. Deine Gruppe wartet.")
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
            Button("+ Song posten") {
                songBeforePosting = mySong?.id
                isPosting = true
            }
            .buttonStyle(TodPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
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
