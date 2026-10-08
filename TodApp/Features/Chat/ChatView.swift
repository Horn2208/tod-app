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
    /// The message "Löschen" was chosen for, until it is confirmed.
    @State private var deleting: ChatMessage?
    @State private var reporting: ReportDraft?
    @State private var blocking: BlockDraft?
    @Environment(\.dismiss) private var dismiss

    /// Die Submission, die gerade erwähnt wird — nil wenn keine ausgewählt.
    private var mentionedSubmission: Submission? {
        guard let id = selectedSongID else { return nil }
        return current.submissions.first { $0.id == id }
    }

    /// Die heutigen Songs der Gruppe zum Auswählen.
    private var todaysSongs: [Submission] {
        RoundVisibility.runningSubmissions(from: current.submissions)
    }

    /// Der Store-Copy nach dem Laden, der bis dahin übergeben wird. By id,
    /// not `currentGroup`: once this group is left, that is another group.
    private var current: Group { store.groups.first { $0.id == group.id } ?? group }

    /// False once this user has left the group or it was deleted.
    private var isStillMember: Bool {
        !store.hasLoadedGroups || store.groups.contains { $0.id == group.id }
    }

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
        // Left or deleted, from the settings above this screen: back to the
        // list, and the settings close with this.
        .onChange(of: isStillMember) { _, isMember in
            if !isMember { dismiss() }
        }
        .confirmationDialog(
            "Nachricht löschen?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { message in
            Button("Löschen", role: .destructive) {
                Task { await store.deleteMessage(message.id) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { message in
            Text("„\(ChatLayout.excerpt(of: message))“ verschwindet für alle in \(current.name).")
        }
        .reportFlow($reporting)
        .blockConfirmation($blocking)
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
                        AsyncImage(url: submission.coverURL) { image in
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
            let messages = current.chatMessages
            let decorations = ChatLayout.decorations(for: messages)
            let songs = ChatMention.index(current.submissions)
            // Lazy: up to 200 messages, each a glass bubble, built only as
            // they scroll into view.
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(zip(messages, decorations)), id: \.0.id) { message, decoration in
                    if let time = decoration.separator {
                        Text(ChatLayout.timeLabel(for: time))
                            .font(.todMono(11))
                            .foregroundStyle(Color.todTextFaint)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    messageRow(message, decoration: decoration, songs: songs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        // The newest message is the one to see; a real chat is longer than
        // the screen.
        .defaultScrollAnchor(.bottom)
        // Seen while open: the groups list drops its dot (`ChatReadMarks`).
        .onChange(of: current.chatMessages.last?.id, initial: true) { _, last in
            if let last { ChatReadMarks.markSeen(last, in: current.id) }
        }
        .refreshable { await store.refresh() }
    }

    /// A message on its sender's side: its text, and under it the song it
    /// mentions. Both, because "hör dir den an" says why the song is there.
    ///
    /// Someone else's run of messages carries their name above the first
    /// bubble and their avatar beside the last (`ChatLayout`).
    private func messageRow(
        _ message: ChatMessage, decoration: ChatLayout.Decoration, songs: [Int: Submission]
    ) -> some View {
        let content = ChatMention.content(of: message, in: songs)
        let isMine = message.isFromCurrentUser
        return HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer()
            } else {
                // The avatar's room is kept on every bubble of the run, so
                // they line up; only the last one shows it.
                SwiftUI.Group {
                    if decoration.showsAvatar {
                        AvatarBadge(member: author(of: message), size: 28)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                if decoration.showsName {
                    Text(message.authorName)
                        .font(.todBody(12, weight: .bold))
                        .foregroundStyle(Color.todTextDim)
                        .padding(.leading, 12)
                        .accessibilityHidden(true)
                }
                if let text = content.text {
                    // Rounded with depth, like the other cards: one's own in
                        // the accent's gradient, the others' in glass.
                    Text(text)
                        .font(.todBody(14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .foregroundStyle(Color.todText)
                        .background {
                            let bubble = RoundedRectangle(cornerRadius: 18, style: .continuous)
                            if isMine {
                                bubble.fill(LinearGradient(
                                    colors: [Color.todAccent, Color.todAccent.opacity(0.75)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                            } else {
                                bubble.fill(.ultraThinMaterial)
                                    .overlay(bubble.strokeBorder(Color.todLine, lineWidth: 0.5))
                            }
                        }
                        // Depth for one's own only: a shadow under every
                        // glass bubble is a second off-screen pass each.
                        .shadow(color: .black.opacity(isMine ? 0.2 : 0), radius: 6, y: 3)
                        // Who and when, read with the words: a run's later
                        // bubbles carry no name on screen, but VoiceOver
                        // still has to say whose they are.
                        .accessibilityLabel(spokenSender(of: message) + text)
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
        .contextMenu {
            if store.mayDelete(message) {
                Button("Nachricht löschen", systemImage: "trash", role: .destructive) {
                    deleting = message
                }
            } else if let authorID = message.authorID, store.mayReport(authorID) {
                Button("Melden", systemImage: "exclamationmark.bubble") {
                    reporting = ReportDraft(
                        groupID: current.id, target: .chatMessage(message.id), personID: authorID,
                        personName: message.authorName, what: "Nachricht von \(message.authorName)",
                        excerpt: message.text)
                }
                Button("\(message.authorName) blockieren", systemImage: "hand.raised", role: .destructive) {
                    blocking = BlockDraft(id: authorID, name: message.authorName)
                }
            }
        }
    }

    /// "Lena, 14:05: " -- or "Du: " for one's own.
    private func spokenSender(of message: ChatMessage) -> String {
        let name = message.isFromCurrentUser ? "Du" : message.authorName
        guard let sent = message.sentAt else { return "\(name): " }
        return "\(name), \(ChatLayout.timeLabel(for: sent)): "
    }

    /// The sender as a group member, for the avatar; someone who has left
    /// still gets a circle with their initials.
    private func author(of message: ChatMessage) -> Member {
        current.members.first { $0.id == message.authorID }
            ?? Member(id: message.authorID ?? message.authorName, name: message.authorName,
                      isCurrentUser: false, postedDates: [])
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
            AsyncImage(url: submission.coverURL) { image in
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
                // "Erinnerung an alle senden" is gone until there is real
                // push: it reported "gesendet" while nothing was sent (the
                // brief's audit, 8. Oktober). It comes back with APNs.
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
