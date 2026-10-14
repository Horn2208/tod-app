import SwiftUI

/// The round as cards you swipe through, one song at a time.
///
/// Replaces the two lists this app used to have. Voting and Reveal were the
/// same content in two shapes, and the difference between them was never the
/// shape -- it was which day was on screen.
struct SongFeedView: View {
    enum Round {
        /// Today: rate freely, see nothing. No rating of anyone's is on
        /// screen, which is exactly what makes changing yours cost nothing.
        case running
        /// Yesterday: decided, with everyone's ratings on show.
        case revealed
    }

    @Environment(AppStore.self) private var store
    let round: Round

    @State private var openSong: Submission?
    /// From an empty Reveal straight on to today's songs.
    @State private var isShowingToday = false
    /// From a round that turned over while open, on to its reveal.
    @State private var isShowingReveal = false
    /// The card whose reason is being written, in the bar above the keyboard.
    @State private var noteFor: Submission?
    /// The card the feed opens at -- a tap on someone in the story row leads
    /// straight to their song. See `GroupsFeed.feedOrder`.
    private let startAt: Int?

    init(round: Round, startAt submissionID: Int? = nil) {
        self.round = round
        self.startAt = submissionID
    }

    private var submissions: [Submission] {
        let inRound: [Submission] = switch round {
        case .running: store.runningSubmissions
        case .revealed: store.revealedSubmissions
        }
        return GroupsFeed.feedOrder(inRound, startingAt: startAt)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SwiftUI.Group {
                if submissions.isEmpty {
                    empty
                } else {
                    feed
                }
            }
            .safeAreaInset(edge: .bottom) {
                if round == .running, !submissions.isEmpty {
                    progressBar
                }
            }
            // After the progress inset, not before: applied outside it, the room
            // lifts the progress bar above the mini player instead of under it.
            .leavesRoomForMiniPlayer()
            // The cards stay where they are while the keyboard is up. Shrunk to
            // the room above it, each page got shorter, the field was scrolled
            // into view, and the card slid under the title with the next one
            // showing below. The reason is written in the bar underneath instead.
            .ignoresSafeArea(.keyboard, edges: .bottom)

            // A sibling, not an inset: it rides the keyboard without changing
            // the size of anything in the feed.
            if let noteFor {
                NoteComposer(submission: noteFor) { self.noteFor = nil }
                    // A fresh bar per card, never one card's draft on another.
                    .id(noteFor.id)
            }
        }
        // The whole screen, edge to edge: on the empty state alone it left
        // the rest of the screen black around a grey band (the user's
        // screenshot, 6. Oktober).
        .background(Color.todBackground.ignoresSafeArea())
        .navigationTitle(round == .running ? "Heute" : "Reveal")
        .navigationDestination(isPresented: $isShowingToday) {
            SongFeedView(round: .running)
        }
        .navigationDestination(isPresented: $isShowingReveal) {
            SongFeedView(round: .revealed)
        }
        // A rating came after midnight: said, with the way to what is now
        // revealed, instead of a choice that silently stays empty.
        .alert("Die Runde ist vorbei", isPresented: Binding(
            get: { round == .running && store.roundIsOver },
            set: { if !$0 { store.acknowledgeRoundOver() } }
        )) {
            Button("Zum Reveal") {
                store.acknowledgeRoundOver()
                Task { await store.refresh() }
                isShowingReveal = true
            }
            Button("OK", role: .cancel) {
                store.acknowledgeRoundOver()
                Task { await store.refresh() }
            }
        } message: {
            Text("Um Mitternacht wird aufgedeckt. Die Songs von gestern kannst du dir jetzt im Reveal ansehen.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.currentGroupID) { await store.loadMyVotes() }
        .sheet(item: $openSong) { submission in
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(submissions) { submission in
                    SongCard(
                        submission: submission,
                        round: round,
                        onOpen: { openSong = submission },
                        onWriteNote: { noteFor = submission }
                    )
                    // One card per screen: the swipe lands on a song, never
                    // between two.
                    .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .dismissesKeyboardOnTap()
    }

    private var progressBar: some View {
        let rated = store.myVotes.ratings.count
        let total = store.votableSubmissions.count
        return VStack(spacing: 4) {
            Text(rated == total && total > 0 ? "Alles bewertet" : "\(rated) von \(total) bewertet")
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(rated == total && total > 0 ? Color.todGood : Color.todText)
            Text("Änderbar bis Mitternacht. Aufgedeckt wird morgen.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
        }
        .padding()
        .frame(maxWidth: .infinity)
        // A rounded glass card floating above the bar, like the app's other
        // cards -- a full-width `.bar` strip drew a hard straight edge across
        // the screen (the user's screenshot, 6. Oktober).
        .todGlassCard(radius: 20, clipsContent: false)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Nothing in this round: one glass card in the middle, as Home says
    /// "nothing from you yet" -- what is missing, when it comes, and the way on.
    private var empty: some View {
        let today = store.runningSubmissions.count
        return VStack(spacing: 14) {
            Image(systemName: round == .running ? "music.note.list" : "eye.slash")
                .font(.system(size: 38))
                .foregroundStyle(Color.todAccent)
                .accessibilityHidden(true)
            Text(round == .running ? "Heute noch nichts zu bewerten" : "Noch nichts aufgedeckt")
                .font(.todDisplay(22))
                .foregroundStyle(Color.todText)
                .multilineTextAlignment(.center)
            Text(round == .running
                 ? "Sobald jemand aus der Gruppe einen Song postet, taucht er hier auf."
                 : "Gestern hat niemand gepostet. Was heute gepostet wird, deckt sich morgen um Mitternacht auf.")
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
            // From an empty Reveal, today is the place with something in it.
            if round == .revealed, today > 0 {
                Button(today == 1 ? "1 Song von heute bewerten" : "\(today) Songs von heute bewerten") {
                    isShowingToday = true
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .todGlassCard(radius: 24, clipsContent: false)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One song

private struct SongCard: View {
    @Environment(AppStore.self) private var store
    let submission: Submission
    let round: SongFeedView.Round
    let onOpen: () -> Void
    let onWriteNote: () -> Void

    private var isOwn: Bool { store.isOwn(submission) }
    private var rating: Rating? { store.myVotes.ratings[submission.id] }
    /// Read from the store, not copied on appear: a copy went stale the moment
    /// the bar below saved a new reason, and the next change of rating sent
    /// the old one along.
    private var note: String { store.myVotes.notes[submission.id] ?? "" }

    var body: some View {
        VStack(spacing: 16) {
            cover
            titles

            switch round {
            case .running: ratingControls
            case .revealed: result
            }

            commentPeek
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        // The cover's colour behind the card. Every song brings its own light
        // rather than the same pink every time.
        //
        // A gradient rather than a blurred circle: it stays inside its own
        // frame without clipping, which matters here because the next card in
        // the swipe sits directly underneath this one.
        .background {
            CoverTint(artworkURL: submission.coverURL, fallbackHex: submission.coverColorHex) { tint in
                RadialGradient(
                    colors: [tint.opacity(0.55), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 320
                )
            }
        }
    }

    /// A button rather than a tap gesture on an image: the way into a song
    /// has to be something VoiceOver can find, name and press.
    private var cover: some View {
        Button(action: onOpen) {
            // Square, a little over half the screen's width: the same share
            // on an SE as on a Pro Max, where 210 points was either most of
            // the screen or a stamp. Capped for iPad-sized widths.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.56, 320) }
                .overlay {
                    CrossfadeCover(url: submission.coverURL, placeholder: Color(hex: submission.coverColorHex))
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Spoken.song(track: submission.track, artist: submission.artist))
        .accessibilityHint("Öffnet den Song")
        // Listening in while rating, without opening the song. Beside the
        // cover's button, not inside it: a button in a button's label gets
        // neither its own tap nor its own VoiceOver element.
        .overlay(alignment: .bottomTrailing) {
            QuickPlayButton(submission: submission)
                .offset(x: 12, y: 12)
        }
    }

    private var titles: some View {
        VStack(spacing: 4) {
            Text(submission.track)
                .font(.todSerif(.title))
                .foregroundStyle(Color.todText)
                .multilineTextAlignment(.center)
                .todGlow(color: .todSongGlow(hex: submission.coverColorHex))
            Text(round == .revealed
                 ? "\(submission.artist) · von \(store.voterName(submission.posterID))"
                 : submission.artist)
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
        }
        // Title and artist are one thing, not two things in a row.
        .accessibilityElement(children: .combine)
    }

    // MARK: Rating, while the day runs

    @ViewBuilder
    private var ratingControls: some View {
        if isOwn {
            VStack(spacing: 10) {
                Text("Dein Song — für den eigenen votet man nicht.")
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextFaint)
                if store.mayDelete(submission) {
                    WithdrawSongButton(submission: submission)
                }
            }
        } else {
            // Rating, gem and reason as one block: one thing to decide, not
            // three loose controls.
            VStack(spacing: 12) {
                ratingSegment
                gemToggle
                // Only once there is a rating to explain: a reason on its own
                // has nothing to attach to, and the store would have no vote
                // to write it into.
                if rating != nil {
                    noteField
                }
            }
            .padding(12)
            .todGlassCard(radius: 18)
            .animation(.snappy, value: rating)
        }
    }

    /// Five equal fields at least 44 points tall: small chips side by side
    /// were below the size a thumb hits reliably while swiping through.
    private var ratingSegment: some View {
        HStack(spacing: 4) {
            ForEach(Rating.allCases, id: \.self) { r in
                let isPicked = rating == r
                Button {
                    Task { await store.castVote(r, for: submission.id, note: note) }
                } label: {
                    Text(r.label)
                        .font(.todBody(12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(isPicked ? Color.todBackground : Color.todTextDim)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            isPicked ? Color.todAccent : Color.clear,
                            in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(PressScale())
                // The pick shows as a fill, which says nothing to VoiceOver.
                .accessibilityAddTraits(isPicked ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.todSurface2, in: RoundedRectangle(cornerRadius: 14))
        // A tick under the thumb as the pick lands.
        .sensoryFeedback(.selection, trigger: rating)
    }

    private var isGem: Bool { store.myVotes.hiddenGemID == submission.id }

    /// A switch you can see: a pill with the gem, filled with gold when set.
    private var gemToggle: some View {
        Button {
            Task { await store.toggleHiddenGem(submission.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isGem ? "diamond.fill" : "diamond")
                    .font(.system(size: 13, weight: .semibold))
                Text(isGem ? "Hidden Gem" : "Als Hidden Gem markieren")
                    .font(.todBody(13, weight: .semibold))
            }
            .foregroundStyle(isGem ? Color.todBackground : Color.todAccent2)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background {
                if isGem {
                    Capsule().fill(Self.gold)
                } else {
                    Capsule().strokeBorder(Color.todAccent2.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .buttonStyle(PressScale())
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isGem)
        .accessibilityLabel("Hidden Gem")
        .accessibilityAddTraits(isGem ? [.isSelected] : [])
        .accessibilityHint("Höchstens einer pro Tag")
        .sensoryFeedback(.selection, trigger: isGem)
    }

    /// The gold the gem wears once set.
    private static let gold = LinearGradient(
        colors: [Color.todAccent2, Color(hex: "#f3d37f")],
        startPoint: .leading,
        endPoint: .trailing)

    private var noteField: some View {
        Button(action: onWriteNote) {
            Text(note.isEmpty ? "Warum? (sehen alle morgen)" : note)
                .font(.todBody(13))
                .foregroundStyle(note.isEmpty ? Color.todTextFaint : Color.todText)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .padding(10)
                .background(Color.todSurface2, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .keepsKeyboardOnTap()
        .accessibilityLabel(note.isEmpty ? "Begründung schreiben" : "Begründung: \(note)")
        .accessibilityHint("Sehen alle morgen")
    }

    // MARK: The result, once the day is over

    @ViewBuilder
    private var result: some View {
        let score = store.roundScores.first { $0.submissionID == submission.id }
        let votes = store.revealedVotes(for: submission.id)

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(pointsLabel(score?.points ?? 0))
                    .font(.todMono(16, weight: .semibold))
                    .foregroundStyle(Color.todAccent2)
                if let gems = score?.hiddenGemCount, gems > 0 {
                    Text("💎 \(gems)")
                        .font(.todMono(13))
                        .foregroundStyle(Color.todTextFaint)
                        .accessibilityLabel(Spoken.gems(gems))
                }
            }
            // Points and gems are one result, not two numbers in a row.
            .accessibilityElement(children: .combine)

            if votes.isEmpty {
                Text("Niemand hat bewertet.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    // Capped: the card is one screen, and a group of twelve
                    // must not push the comments off the bottom of it.
                    ForEach(votes.prefix(4), id: \.voterID) { vote in
                        VoteRow(name: store.voterName(vote.voterID), vote: vote)
                    }
                    if votes.count > 4 {
                        Text("und \(votes.count - 4) weitere")
                            .font(.todMono(11))
                            .foregroundStyle(Color.todTextFaint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// "1 pts" reads like a typo, and a round often turns on a single point.
    private func pointsLabel(_ points: Int) -> String {
        abs(points) == 1 ? "\(points) pt" : "\(points) pts"
    }

    // MARK: Comments

    private var commentPeek: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 4) {
                if let first = submission.comments.first {
                    Text("\(first.authorName): \(first.text)")
                        .font(.todBody(13))
                        .foregroundStyle(Color.todTextDim)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if submission.comments.count > 1 {
                        Text("alle \(submission.comments.count) Kommentare")
                            .font(.todMono(11))
                            .foregroundStyle(Color.todAccent)
                    }
                } else {
                    Text("Sag was dazu")
                        .font(.todBody(13))
                        .foregroundStyle(Color.todAccent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Where the reason for a rating is written: a bar on the keyboard, outside
/// the feed, so typing moves no card. It saves when it closes -- with "Fertig",
/// the return key, or a tap or swipe that puts the keyboard away -- so no
/// half-written reason is lost.
private struct NoteComposer: View {
    @Environment(AppStore.self) private var store
    let submission: Submission
    let onClose: () -> Void

    @State private var draft = ""
    @State private var isClosed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Warum? (sehen alle morgen)", text: $draft, axis: .vertical)
                .font(.todBody(14))
                .foregroundStyle(Color.todText)
                .lineLimit(1...4)
                .submitLabel(.done)
                .focused($isFocused)
                .padding(10)
                .background(Color.todSurface2, in: RoundedRectangle(cornerRadius: 12))
            Button("Fertig", action: close)
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(Color.todAccent)
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.todLine).frame(height: 0.5)
        }
        .onAppear {
            draft = store.myVotes.notes[submission.id] ?? ""
            isFocused = true
        }
        // A vertical field takes the return key as a line break; here it ends
        // the reason, as the key's label says.
        .onChange(of: draft) { _, text in
            guard text.contains("\n") else { return }
            draft = text.replacingOccurrences(of: "\n", with: "")
            close()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { close() }
        }
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        isFocused = false
        if let rating = store.myVotes.ratings[submission.id] {
            let text = draft
            let id = submission.id
            Task { await store.castVote(rating, for: id, note: text) }
        }
        onClose()
    }
}

private struct VoteRow: View {
    let name: String
    let vote: Vote

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todText)
                Text(vote.rating.label)
                    .font(.todMono(11, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.todSurface2, in: Capsule())
                    .foregroundStyle(Color.todTextDim)
            }
            if let note = vote.note, !note.isEmpty {
                Text(note)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A press that shows: the control shrinks a little under the finger and
/// springs back.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.35), value: configuration.isPressed)
    }
}
