import SwiftUI

struct VotingView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let submissions = store.runningSubmissions
        let votes = store.myVotes

        ScrollView {
            VStack(spacing: 12) {
                if submissions.isEmpty {
                    EmptyRoundNotice()
                } else {
                    ForEach(submissions) { submission in
                        SubmissionVoteCard(
                            submission: submission,
                            rating: votes.ratings[submission.id],
                            isHiddenGem: votes.hiddenGemID == submission.id,
                            isOwn: store.isOwn(submission),
                            onRate: { rating in
                                Task { await store.castVote(rating, for: submission.id) }
                            },
                            onGem: {
                                Task { await store.toggleHiddenGem(submission.id) }
                            }
                        )
                    }
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Voten")
        // A half-finished round belongs to its group, so switching groups reloads
        // rather than showing the previous group's ratings.
        .task(id: store.currentGroupID) {
            await store.loadMyVotes()
        }
        .safeAreaInset(edge: .bottom) {
            if !submissions.isEmpty {
                RoundProgressBar(
                    rated: votes.ratings.count,
                    total: store.votableSubmissions.count
                )
            }
        }
    }
}

/// There is no button to press here any more. The round closes when the day
/// does, so the bar reports where you stand and says when it will be over --
/// a "Vote abschicken" button would now lock a round early for no reason.
private struct RoundProgressBar: View {
    let rated: Int
    let total: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(rated == total && total > 0 ? "Alles bewertet" : "\(rated) von \(total) bewertet")
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(rated == total && total > 0 ? Color.todGood : Color.todText)
            Text("Du kannst deine Wertungen den ganzen Tag ändern. Aufgedeckt wird morgen.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

/// A day on which nobody has posted yet. Says so, rather than showing an empty
/// scroll view that looks like something failed to load.
private struct EmptyRoundNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Heute noch nichts zu bewerten")
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(Color.todText)
            Text("Sobald jemand aus der Gruppe einen Song postet, taucht er hier auf.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct SubmissionVoteCard: View {
    let submission: Submission
    let rating: Rating?
    let isHiddenGem: Bool
    let isOwn: Bool
    let onRate: (Rating) -> Void
    let onGem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // The colour is the fallback, not the design: a submission that
                // knows its source shows the real cover, as Reveal already does.
                AsyncImage(url: submission.source?.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color(hex: submission.coverColorHex))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(submission.track).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                    Text(submission.artist).font(.todBody(13)).foregroundStyle(Color.todTextDim)
                }
                Spacer()
            }

            // Your own song stays in the list so the round keeps its real size,
            // but it offers nothing to press.
            if isOwn {
                Text("Dein Song — für den eigenen votet man nicht.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            } else {
                HStack(spacing: 6) {
                    ForEach(Rating.allCases, id: \.self) { r in
                        let isPicked = rating == r
                        Button(r.label) { onRate(r) }
                            .font(.todMono(11, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(isPicked ? Color.todAccent : Color.todSurface2)
                            .foregroundStyle(isPicked ? .white : Color.todTextDim)
                            .clipShape(Capsule())
                    }
                }

                Button(isHiddenGem ? "💎 Hidden Gem gesetzt" : "💎 Als Hidden Gem markieren", action: onGem)
                    .font(.todBody(12))
                    .foregroundStyle(isHiddenGem ? Color.todAccent2 : Color.todTextFaint)
            }
        }
        .padding()
        .background(isHiddenGem ? Color.todAccent2.opacity(0.1) : Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
