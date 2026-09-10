import SwiftUI

struct RevealView: View {
    @Environment(AppStore.self) private var store
    @State private var playing: Submission?

    var body: some View {
        // Yesterday's round, never today's. What is still being voted on has no
        // scores to show, and showing the songs alone would only invite the
        // question of where the numbers are.
        let submissions = store.revealedSubmissions
        let scores = store.roundScores

        ScrollView {
            VStack(spacing: 12) {
                if submissions.isEmpty {
                    NothingRevealedNotice()
                } else {
                    RoundResultHeader(scores: scores, submissions: submissions)
                }

                ForEach(submissions) { submission in
                    SubmissionRevealRow(
                        submission: submission,
                        score: scores.first { $0.submissionID == submission.id },
                        onPlay: { playing = submission }
                    )
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Reveal")
        // The result belongs to the selected group, and it is the revealed day's
        // -- both are what loading the votes decides.
        .task(id: store.currentGroupID) {
            await store.loadMyVotes()
        }
        .sheet(item: $playing) { submission in
            // `.large` only: this sheet holds a player, a comment list and a
            // field to type into. At `.medium` the keyboard would leave the
            // reply field nowhere to go.
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
    }
}

/// The round's top of the table. A tie has no single winner to crown, so every
/// tied song is named instead of picking one arbitrarily.
private struct RoundResultHeader: View {
    let scores: [RoundScore]
    let submissions: [Submission]

    var body: some View {
        let leaders = scores.leaders

        VStack(alignment: .leading, spacing: 10) {
            Text(leaders.count > 1 ? "Tagessieger von gestern — Gleichstand" : "Tagessieger von gestern")
                .font(.todMono(12, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            if leaders.isEmpty {
                Text("Noch kein Sieger — keine Wertung liegt über null.")
                    .font(.todBody(14))
                    .foregroundStyle(Color.todTextDim)
            } else {
                ForEach(leaders) { score in
                    if let winner = submissions.first(where: { $0.id == score.submissionID }) {
                        HStack(spacing: 10) {
                            Text(leaders.count > 1 ? "🤝" : "🏆").font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(winner.track)
                                    .font(.todBody(16, weight: .bold))
                                    .foregroundStyle(Color.todText)
                                Text("\(winner.artist) · von \(winner.posterID)")
                                    .font(.todBody(12))
                                    .foregroundStyle(Color.todTextDim)
                            }
                            Spacer()
                            ScoreBadge(score: score)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.todAccent.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Not a loading state: a round is revealed the day after it ran, so a group
/// that posted nothing yesterday genuinely has nothing to show. The screen says
/// which day is coming rather than falling back to an older one.
private struct NothingRevealedNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Noch nichts aufgedeckt")
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(Color.todText)
            Text("Aufgedeckt wird die Runde von gestern. Was heute gepostet wird, siehst du morgen.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ScoreBadge: View {
    let score: RoundScore

    /// "1 pts" reads like a typo, and a round often turns on a single point.
    private var pointsLabel: String {
        abs(score.points) == 1 ? "\(score.points) pt" : "\(score.points) pts"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(pointsLabel)
                .font(.todMono(13, weight: .semibold))
                .foregroundStyle(Color.todAccent2)
            // The gem is a nod, not a score -- it is counted next to the points,
            // never added into them.
            if score.hiddenGemCount > 0 {
                Text("💎 \(score.hiddenGemCount)")
                    .font(.todMono(11))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
    }
}

private struct SubmissionRevealRow: View {
    static func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    let submission: Submission
    let score: RoundScore?
    let onPlay: () -> Void

    var body: some View {
        HStack {
            AsyncImage(url: submission.source?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(hex: submission.coverColorHex))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.track).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                Text(submission.artist).font(.todBody(13)).foregroundStyle(Color.todTextDim)
                if let section = submission.section {
                    Text("Abschnitt \(Self.timestamp(section.start))–\(Self.timestamp(section.end))")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                }
            }
            if submission.source != nil {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Color.todAccent)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(submission.posterID)
                    .font(.todMono(12)).foregroundStyle(Color.todAccent2)
                if let score {
                    ScoreBadge(score: score)
                }
            }
        }
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Opens whether or not the song can be played -- what is behind this
        // row is the song and its comments, not only a player.
        .onTapGesture(perform: onPlay)
    }
}
