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

    private var submissions: [Submission] {
        switch round {
        case .running: store.runningSubmissions
        case .revealed: store.revealedSubmissions
        }
    }

    var body: some View {
        SwiftUI.Group {
            if submissions.isEmpty {
                empty
            } else {
                feed
            }
        }
        .background(Color.todBackground)
        .navigationTitle(round == .running ? "Heute" : "Reveal")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.currentGroupID) { await store.loadMyVotes() }
        .safeAreaInset(edge: .bottom) {
            if round == .running, !submissions.isEmpty {
                progressBar
            }
        }
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
                        onOpen: { openSong = submission }
                    )
                    // One card per screen: the swipe lands on a song, never
                    // between two.
                    .containerRelativeFrame(.vertical)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
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
        .background(.bar)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(round == .running ? "Heute noch nichts zu bewerten" : "Noch nichts aufgedeckt")
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todText)
            Text(round == .running
                 ? "Sobald jemand aus der Gruppe einen Song postet, taucht er hier auf."
                 : "Aufgedeckt wird die Runde von gestern. Was heute gepostet wird, siehst du morgen.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
    }
}

// MARK: - One song

private struct SongCard: View {
    @Environment(AppStore.self) private var store
    let submission: Submission
    let round: SongFeedView.Round
    let onOpen: () -> Void

    @State private var note = ""

    private var isOwn: Bool { store.isOwn(submission) }
    private var rating: Rating? { store.myVotes.ratings[submission.id] }

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
        // The cover's colour, thrown behind the card and blurred out. Every
        // song brings its own light rather than the same pink every time.
        .background(alignment: .top) {
            Circle()
                .fill(Color(hex: submission.coverColorHex))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .opacity(0.5)
                .offset(y: -60)
        }
        .onAppear { note = store.myVotes.notes[submission.id] ?? "" }
    }

    private var cover: some View {
        AsyncImage(url: submission.source?.artworkURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(Color(hex: submission.coverColorHex))
        }
        .frame(width: 210, height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
        .onTapGesture(perform: onOpen)
    }

    private var titles: some View {
        VStack(spacing: 4) {
            Text(submission.track)
                .font(.todDisplay(22))
                .foregroundStyle(Color.todText)
                .multilineTextAlignment(.center)
            Text(round == .revealed
                 ? "\(submission.artist) · von \(store.voterName(submission.posterID))"
                 : submission.artist)
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
        }
    }

    // MARK: Rating, while the day runs

    @ViewBuilder
    private var ratingControls: some View {
        if isOwn {
            Text("Dein Song — für den eigenen votet man nicht.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextFaint)
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(Rating.allCases, id: \.self) { r in
                        let isPicked = rating == r
                        Button(r.label) {
                            Task { await store.castVote(r, for: submission.id, note: note) }
                        }
                        .font(.todMono(11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(isPicked ? Color.todAccent : Color.todSurface2)
                        .foregroundStyle(isPicked ? .white : Color.todTextDim)
                        .clipShape(Capsule())
                    }
                }

                Button(store.myVotes.hiddenGemID == submission.id
                       ? "💎 Hidden Gem gesetzt"
                       : "💎 Als Hidden Gem markieren") {
                    Task { await store.toggleHiddenGem(submission.id) }
                }
                .font(.todBody(12))
                .foregroundStyle(
                    store.myVotes.hiddenGemID == submission.id ? Color.todAccent2 : Color.todTextFaint
                )

                // Only once there is a rating to explain: a reason on its own
                // has nothing to attach to, and the store would have no vote
                // to write it into.
                if let rating {
                    TextField("Warum? (sehen alle morgen)", text: $note, axis: .vertical)
                        .font(.todBody(13))
                        .foregroundStyle(Color.todText)
                        .lineLimit(1...3)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.todLine, lineWidth: 0.5)
                        )
                        .onSubmit {
                            Task { await store.castVote(rating, for: submission.id, note: note) }
                        }
                }
            }
        }
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
                }
            }

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
