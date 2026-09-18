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
    @State private var showingSongPicker = false
    /// Die ID des heute geposteten Songs, den die aktuelle Nachricht erwährt.
    @State private var selectedSongID: Int?
    /// Set by a tap on a mentioned song from today or yesterday: that round's
    /// feed, at its card.
    @State private var feedTarget: FeedTarget?
    /// Set by a tap on a mentioned song older than that, which no feed shows.
    @State private var openSong: Submission?

    /// Die Submission, die gerade erwähnt wird — nil wenn keine ausgewählt.
    private var mentionedSubmission: Submission? {
        guard let id = selectedSongID else { return nil }
        return current.submissions.first { $0.id == id }
    }

    /// Die heutigen Songs der Gruppe zum Auswählen.
    private var todaysSongs: [Submission] {
        let today = Date()
        return current.submissions.filter {
            Calendar.current.isDate($0.postedAt, inSameDayAs: today)
        }
    }

    /// Der Store-Copy nach dem Laden, der bis dahin übergeben wird.
    private var current: Group { store.currentGroup ?? group }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                roundStrip
                messages
            }
            .dismissesKeyboardOnTap()
            inputBar
        }
        .leavesRoomForMiniPlayer()
        .background(Color.todBackground)
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { LeaderboardView() } label: {
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
        .task(id: store.currentGroupID) { await store.loadMyVotes() }
        .sheet(isPresented: $isShowingActions) {
            BattleSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.todBackground)
        }
        .sheet(isPresented: $showingSongPicker) {
            songPicker
                .presentationDetents([.medium])
                .presentationBackground(Color.todBackground)
        }
        .navigationDestination(item: $feedTarget) { target in
            SongFeedView(round: target.round, startAt: target.submissionID)
        }
        .sheet(item: $openSong) { submission in
            SongDetailView(submission: submission)
                .presentationDetents([.large])
                .presentationBackground(Color.todBackground)
        }
        .onChange(of: selectedSongID) { _, _ in
            // Wenn ein Song gewählt wurde, den Text-Fokus behalten.
        }
    }

    // MARK: - Song-Picker

    private var songPicker: some View {
        NavigationStack {
            List(todaysSongs) { submission in
                Button {
                    selectedSongID = submission.id
                    showingSongPicker = false
                } label: {
                    HStack {
                        AsyncImage(url: submission.source?.artworkURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.todSurface3
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(submission.track)
                                .font(.todBody(14))
                                .foregroundStyle(Color.todText)
                            Text(submission.artist)
                                .font(.todMono(11))
                                .foregroundStyle(Color.todTextFaint)
                        }
                    }
                }
            }
            .navigationTitle("Song erwähnen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Abbrechen") { showingSongPicker = false }
                        .font(.todBody(15, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
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
                    messageRow(message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        // The newest message is the one to see; a real chat is longer than
        // the screen.
        .defaultScrollAnchor(.bottom)
        .refreshable { await store.refresh() }
    }

    /// A message on its sender's side: its text, and under it the song it
    /// mentions. Both, because "hör dir den an" says why the song is there.
    private func messageRow(_ message: ChatMessage) -> some View {
        let content = ChatMention.content(of: message, in: current.submissions)
        let isMine = message.isFromCurrentUser
        return HStack {
            if isMine { Spacer() }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if let text = content.text {
                    Text(text)
                        .font(.todBody(14))
                        .padding(10)
                        .background(isMine ? Color.todAccent.opacity(0.85) : Color.todSurface2)
                        .foregroundStyle(Color.todText)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let song = content.song {
                    Button { open(song) } label: { songCard(song) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Spoken.song(track: song.track, artist: song.artist))
                        .accessibilityHint("Öffnet den Song")
                }
            }
            if !isMine { Spacer() }
        }
    }

    /// Where the round of the song is still on screen, it opens there, at its
    /// card: today's in the running feed, yesterday's in the reveal. The chat
    /// has already made its group the current one, which is what both feeds
    /// show. Anything older is in neither and opens on its own.
    private func open(_ song: Submission) {
        switch ChatMention.target(for: song) {
        case .today(let submissionID):
            feedTarget = FeedTarget(round: .running, submissionID: submissionID)
        case .yesterday(let submissionID):
            feedTarget = FeedTarget(round: .revealed, submissionID: submissionID)
        case .older:
            openSong = song
        }
    }

    /// Kleine eingebettete Song-Karte für eine Erwähnung.
    private func songCard(_ submission: Submission) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: submission.source?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.todSurface3
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(submission.track)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todText)
                Text(submission.artist)
                    .font(.todMono(11))
                    .foregroundStyle(Color.todTextFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        // Narrower than the chat: stretched across it, the card sat on neither
        // side and hid whose message it belongs to.
        .frame(maxWidth: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.todLine, lineWidth: 0.5))
        // The whole card answers a tap, not only its picture and words.
        .contentShape(RoundedRectangle(cornerRadius: 14))
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

            // 🎵-Button: Song zum Verlinken auswählen
            Button {
                showingSongPicker = true
            } label: {
                Image(systemName: "music.note")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.todAccent)
                    .frame(width: 34, height: 34)
                    .background(Color.todSurface2, in: Circle())
            }
            .accessibilityLabel("Song erwähnen")

            TextField("Nachricht", text: $draft)
                .textFieldStyle(.plain)
                .font(.todBody(14))
                .foregroundStyle(Color.todText)
                .padding(10)
                .background(Color.todSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("Senden") {
                let text = draft
                let songID = selectedSongID
                draft = ""
                selectedSongID = nil
                Task { await store.sendMessage(text, mentionedSubmissionID: songID) }
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
                // Decoration: the title underneath says what this card is.
                .accessibilityHidden(true)
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
        // "Heute bewerten, 0 von 4" as one stop, not two.
        .accessibilityElement(children: .combine)
    }
}

/// What the "+" opens. Premium decides which half of this is shown -- shown
/// locked rather than hidden, because nobody buys a feature they never saw.
private struct BattleSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showReminderSent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                SwiftUI.Group {
                    if store.profile.isPremium {
                        BattleView()
                    } else {
                        locked
                    }
                }
                if store.profile.isPremium {
                    Button("Erinnerung an alle senden") {
                        if store.sendReminderBroadcast() {
                            showReminderSent = true
                        }
                    }
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todAccent)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Erinnerung an alle Gruppenmitglieder senden")
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
        .alert("Erinnerung gesendet", isPresented: $showReminderSent) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Die Erinnerung wurde an alle Mitglieder der Gruppe gesendet.")
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.todAccent2)
                // The line under it already says this is locked.
                .accessibilityHidden(true)
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
