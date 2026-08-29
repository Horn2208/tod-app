import SwiftUI

struct VotingView: View {
    @Environment(AppStore.self) private var store
    @State private var ratings: [Int: Rating] = [:]
    @State private var hiddenGemID: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(store.currentGroup?.submissions ?? []) { submission in
                    SubmissionVoteCard(
                        submission: submission,
                        rating: ratings[submission.id],
                        isHiddenGem: hiddenGemID == submission.id,
                        onRate: { ratings[submission.id] = $0 },
                        onGem: { hiddenGemID = hiddenGemID == submission.id ? nil : submission.id }
                    )
                }
            }
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Voten")
        .safeAreaInset(edge: .bottom) {
            Button("Vote abschicken") {
                Task { await store.submitVotes() }
            }
            .buttonStyle(TodPrimaryButtonStyle())
            .padding()
            .disabled((store.currentGroup?.submissions.count ?? 0) != ratings.count)
        }
    }
}

private struct SubmissionVoteCard: View {
    let submission: Submission
    let rating: Rating?
    let isHiddenGem: Bool
    let onRate: (Rating) -> Void
    let onGem: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: submission.coverColorHex))
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading) {
                    Text(submission.track).font(.todBody(15, weight: .bold)).foregroundStyle(Color.todText)
                    Text(submission.artist).font(.todBody(13)).foregroundStyle(Color.todTextDim)
                }
                Spacer()
            }

            HStack(spacing: 6) {
                ForEach(Rating.allCases, id: \.self) { r in
                    Button(r.label) { onRate(r) }
                        .font(.todMono(11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(rating == r ? Color.todAccent : Color.todSurface2)
                        .foregroundStyle(rating == r ? .white : Color.todTextDim)
                        .clipShape(Capsule())
                }
            }

            Button(isHiddenGem ? "💎 Hidden Gem gesetzt" : "💎 Als Hidden Gem markieren", action: onGem)
                .font(.todBody(12))
                .foregroundStyle(isHiddenGem ? Color.todAccent2 : Color.todTextFaint)
        }
        .padding()
        .background(isHiddenGem ? Color.todAccent2.opacity(0.1) : Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
