import SwiftUI

/// The group's hub. Tapping a group in the feed opens this rather than a menu
/// of screens: the chat is where the group actually is, and everything else
/// about the group hangs off it -- the round above the messages, the
/// leaderboard in the navigation bar, a battle behind the "+".
struct ChatView: View {
    @Environment(AppStore.self) private var store
    let group: Group

    @State private var draft = ""
    @State private var isShowingActions = false

    /// The store's copy once it has caught up, the one passed in until then --
    /// so the first frame after a tap is not empty.
    private var current: Group { store.currentGroup ?? group }

    var body: some View {
        VStack(spacing: 0) {
            roundStrip
            messages
            inputBar
        }
        .background(Color.todBackground)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { LeaderboardView() } label: {
                    // Gold, and a crown rather than a list icon: the brief
                    // asked for this one to stand apart from the ordinary chat
                    // actions, and gold is what this app already awards with.
                    Image(systemName: "crown.fill")
                        .foregroundStyle(Color.todAccent2)
                }
                .accessibilityLabel("Rangliste")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { GroupSettingsView() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Color.todTextDim)
                }
                .accessibilityLabel("Gruppeneinstellungen")
            }
        }
        .onAppear { store.selectGroup(group.id) }
        // The round strip counts what you have rated, which is what loading the
        // votes decides -- the same reason Voting and Reveal ask for them.
        .task(id: store.currentGroupID) { await store.loadMyVotes() }
        .sheet(isPresented: $isShowingActions) {
            BattleSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.todBackground)
        }
    }

    // MARK: - The round, above the talk

    private var roundStrip: some View {
        HStack(spacing: 10) {
            NavigationLink { SongFeedView(round: .running) } label: {
                RoundCard(
                    icon: "hand.thumbsup.fill",
                    title: "Heute bewerten",
                    detail: votingDetail,
                    tint: .todAccent
                )
            }
            NavigationLink { SongFeedView(round: .revealed) } label: {
                RoundCard(
                    icon: "sparkles",
                    title: "Reveal",
                    detail: revealDetail,
                    tint: .todAccent2
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var votingDetail: String {
        let total = store.votableSubmissions.count
        guard total > 0 else { return "noch nichts gepostet" }
        return "\(store.myVotes.ratings.count) von \(total)"
    }

    private var revealDetail: String {
        let count = store.revealedSubmissions.count
        return count == 0 ? "noch nichts aufgedeckt" : "\(count) Songs von gestern"
    }

    // MARK: - Messages

    private var messages: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(current.chatMessages) { message in
                    HStack {
                        if message.isFromCurrentUser { Spacer() }
                        Text(message.text)
                            .font(.todBody(14))
                            .padding(10)
                            .background(message.isFromCurrentUser ? Color.todAccent.opacity(0.85) : Color.todSurface2)
                            .foregroundStyle(Color.todText)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        if !message.isFromCurrentUser { Spacer() }
                    }
                }
            }
            // Claim the full width explicitly; do not rely on a child
            // (button, spacer) happening to stretch the container.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { isShowingActions = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.todAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.todSurface2, in: Circle())
            }
            .accessibilityLabel("Battle")

            TextField("Nachricht", text: $draft)
                .textFieldStyle(.plain)
                .font(.todBody(14))
                .foregroundStyle(Color.todText)
                .padding(10)
                .background(Color.todSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("Senden") {
                let text = draft
                draft = ""
                Task { await store.sendMessage(text) }
            }
            .font(.todBody(14, weight: .bold))
            .foregroundStyle(Color.todAccent)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .background(.bar)
    }
}

/// One of the two ways into the round, side by side above the messages.
private struct RoundCard: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(tint)
            Text(title)
                .font(.todBody(14, weight: .bold))
                .foregroundStyle(Color.todText)
            Text(detail)
                .font(.todMono(11))
                .foregroundStyle(Color.todTextFaint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
    }
}

/// What the "+" opens. Premium decides which half of this is shown -- shown
/// locked rather than hidden, because nobody buys a feature they never saw.
private struct BattleSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SwiftUI.Group {
                if store.profile.isPremium {
                    BattleView()
                } else {
                    locked
                }
            }
            .navigationTitle("Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                        .font(.todBody(15, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.todAccent2)
            Text("Battle gehört zu Tod Premium")
                .font(.todBody(16, weight: .bold))
                .foregroundStyle(Color.todText)
            Text("Alles andere — posten, bewerten, Reveal, Rangliste, Chat — bleibt frei. Premium lässt sich im Profil einschalten, solange es hier nichts zu kaufen gibt.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.todBackground)
    }
}
