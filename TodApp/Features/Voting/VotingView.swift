import SwiftUI

struct VotingView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let submissions = store.currentGroup?.submissions ?? []
        let votes = store.myVotes

        ScrollView {
            VStack(spacing: 12) {
                ForEach(submissions) { submission in
                    SubmissionVoteCard(
                        submission: submission,
                        rating: votes.ratings[submission.id],
                        isHiddenGem: votes.hiddenGemID == submission.id,
                        isOwn: store.isOwn(submission),
                        isLocked: votes.hasSubmitted,
                        onRate: { rating in
                            Task { await store.castVote(rating, for: submission.id) }
                        },
                        onGem: {
                            Task { await store.toggleHiddenGem(submission.id) }
                        }
                    )
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
            VoteSubmitBar(
                hasSubmitted: votes.hasSubmitted,
                rated: votes.ratings.count,
                total: store.votableSubmissions.count,
                onSubmit: { Task { await store.submitVotes() } }
            )
        }
    }
}

/// Either the way out of the round, or the confirmation that it is closed --
/// never a button that looks pressable after the vote is in.
private struct VoteSubmitBar: View {
    let hasSubmitted: Bool
    let rated: Int
    let total: Int
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if hasSubmitted {
                Text("Abgeschickt — dein Vote steht.")
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todAccent2)
                Text("Das Ergebnis siehst du im Reveal-Tab.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
            } else {
                Button("Vote abschicken", action: onSubmit)
                    .buttonStyle(TodPrimaryButtonStyle())
                    .disabled(rated != total || total == 0)
                if rated != total {
                    Text("\(rated) von \(total) bewertet")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                }
            }
        }
        .padding()
    }
}

private struct SubmissionVoteCard: View {
    let submission: Submission
    let rating: Rating?
    let isHiddenGem: Bool
    let isOwn: Bool
    let isLocked: Bool
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
                            .disabled(isLocked)
                            // Once the round is in, the choice you made stays
                            // legible and the ones you passed over recede.
                            .opacity(isLocked && !isPicked ? 0.35 : 1)
                    }
                }

                // After submitting, only a gem that was actually set is worth
                // showing -- an invitation would be a button that cannot be pressed.
                if isHiddenGem {
                    Button("💎 Hidden Gem gesetzt", action: onGem)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todAccent2)
                        .disabled(isLocked)
                } else if !isLocked {
                    Button("💎 Als Hidden Gem markieren", action: onGem)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextFaint)
                }
            }
        }
        .padding()
        .background(isHiddenGem ? Color.todAccent2.opacity(0.1) : Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
