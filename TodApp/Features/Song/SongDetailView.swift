import SwiftUI

/// One song with everything that belongs to it: the player at the top, what
/// people said underneath, and the field to say something at the bottom.
///
/// Reached from three places -- Home, the story row, and a revealed round --
/// which is why it takes a submission rather than reading "the current one".
/// The story row in particular spans every group, so the song on screen need
/// not be in the group that happens to be selected.
struct SongDetailView: View {
    let submission: Submission

    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    /// A comment on its way up, shown faded under the others until the
    /// server has it. On a failure its words go back into the field rather
    /// than being lost (the brief's second audit, B3).
    @State private var sending: String?
    /// The own comment "Löschen" was chosen for, until it is confirmed.
    @State private var deletingComment: Comment?
    @State private var reporting: ReportDraft?

    /// Read back from the store on every redraw rather than kept from the
    /// value this view was handed: a comment lands in the repository, and the
    /// copy passed in at presentation time would never show it.
    private var current: Submission {
        store.groups.flatMap(\.submissions).first { $0.id == submission.id } ?? submission
    }

    private var group: Group? { store.group(containing: submission.id) }

    private var canSend: Bool {
        // One at a time: a second send would take the first one's place.
        sending == nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    player
                    if store.mayDelete(current) {
                        WithdrawSongButton(submission: current) { dismiss() }
                            .padding(.horizontal)
                    } else if let group, store.mayReport(current.posterID) {
                        Button {
                            reporting = ReportDraft(
                                groupID: group.id, target: .submission(current.id),
                                personID: current.posterID,
                                personName: group.members.first { $0.id == current.posterID }?.name ?? GroupAssembly.unknownName,
                                what: "Song „\(current.track)“",
                                excerpt: "\(current.track) – \(current.artist)")
                        } label: {
                            Label("Song melden", systemImage: "exclamationmark.bubble")
                                .font(.todBody(12))
                                .foregroundStyle(Color.todTextFaint)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                    }
                    comments
                }
                .padding(.bottom, 16)
            }
            .dismissesKeyboardOnTap()
            replyField
        }
        // The cover's own colour from the top, fading into the app's ground:
        // every song looks like itself here, as on Home, rather than all of
        // them wearing one pink.
        .background {
            CoverTint(artworkURL: current.coverURL, fallbackHex: current.coverColorHex) { tint in
                LinearGradient(
                    colors: [tint.opacity(0.75), tint.opacity(0.25), Color.todBackground],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.7))
            }
            .background(Color.todBackground)
            .ignoresSafeArea()
        }
        // Every place that opens a song does it as a sheet, so closing when
        // idle lives here once rather than at five call sites. A comment
        // being written keeps it open.
        .closesWhenIdle(held: !draft.isEmpty)
        .confirmationDialog(
            "Kommentar löschen?",
            isPresented: Binding(get: { deletingComment != nil }, set: { if !$0 { deletingComment = nil } }),
            titleVisibility: .visible,
            presenting: deletingComment
        ) { comment in
            Button("Löschen", role: .destructive) {
                Task { await store.deleteComment(comment.id, on: submission.id) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { comment in
            Text("„\(CommentExcerpt.of(comment.text))“ unter \(current.track) verschwindet für alle.")
        }
        .reportFlow($reporting)
    }

    // MARK: - Player

    /// One instance, inline -- never inside the comment list. Each
    /// `TrackEmbedView` is its own web process, so a player per row would be a
    /// process per row.
    ///
    /// A song posted without a link goes in with `source: nil`: Apple's catalog
    /// may still have it under its title, and only when it does not is there
    /// nothing to play.
    private var player: some View {
        TrackPlayerSheet(
            candidateTitle: current.track,
            artist: current.artist,
            source: current.source,
            section: current.section,
            durationSeconds: current.durationSeconds,
            appleMusicID: current.appleMusicID,
            isrc: current.isrc,
            coverColorHex: current.coverColorHex,
            submissionID: current.id
        )
    }

    // MARK: - Comments

    private var comments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(countLabel)
                .font(.todBody(16, weight: .bold))
                .foregroundStyle(Color.todText)
                .accessibilityAddTraits(.isHeader)

            ForEach(current.comments) { comment in
                CommentRow(
                    comment: comment, author: author(of: comment),
                    onDelete: store.mayDelete(comment) ? { deletingComment = comment } : nil,
                    onReport: store.mayReport(comment.authorID) ? { report(comment) } : nil)
            }

            if let sending {
                VStack(alignment: .leading, spacing: 3) {
                    Text("wird gesendet …")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                    Text(sending)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todTextDim)
                }
                .padding(.leading, 44)
                .opacity(0.6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Dein Kommentar wird gesendet: \(sending)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    private var countLabel: String {
        switch current.comments.count {
        case 0: "Noch nichts gesagt"
        case 1: "1 Kommentar"
        case let count: "\(count) Kommentare"
        }
    }

    /// The author as a group member, so the shared avatar shows the same face
    /// here as everywhere else. Someone who has since left the group still gets
    /// a circle rather than a gap, built from what the comment itself carries.
    private func author(of comment: Comment) -> Member {
        group?.members.first { $0.id == comment.authorID }
            ?? Member(
                id: comment.authorID,
                name: comment.authorName,
                isCurrentUser: comment.authorID == store.profile.id,
                postedDates: []
            )
    }

    private func report(_ comment: Comment) {
        guard let group else { return }
        reporting = ReportDraft(
            groupID: group.id, target: .comment(comment.id), personID: comment.authorID,
            personName: comment.authorName, what: "Kommentar von \(comment.authorName)",
            excerpt: comment.text)
    }

    // MARK: - Reply

    private var replyField: some View {
        HStack(spacing: 10) {
            TextField("Sag was dazu", text: $draft, axis: .vertical)
                .font(.todBody(14))
                .foregroundStyle(Color.todText)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.todSurface2)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                let text = draft
                // Cleared before the write, not after: the field belongs to
                // this view and the round trip through the repository is long
                // enough to type into twice.
                draft = ""
                sending = text
                Task {
                    let sent = await store.addComment(text, to: submission.id)
                    sending = nil
                    // Not lost: back into the field, ahead of anything typed
                    // since.
                    if !sent { draft = draft.isEmpty ? text : text + " " + draft }
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(canSend ? Color.todAccent : Color.todSurface3)
            }
            .disabled(!canSend)
            .accessibilityLabel("Kommentar abschicken")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.todLine).frame(height: 0.5)
        }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let author: Member
    /// Set for one's own comments: a long press offers to delete it.
    var onDelete: (() -> Void)?
    /// Set for everyone else's: a long press offers to report it.
    var onReport: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarBadge(member: author, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(author.isCurrentUser ? "Du" : comment.authorName)
                        .font(.todBody(13, weight: .bold))
                        .foregroundStyle(Color.todText)
                    Text(CommentTime.label(for: comment.postedAt))
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                }
                Text(comment.text)
                    .font(.todBody(14))
                    .foregroundStyle(Color.todTextDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        // `.ignore` rather than `.combine`: the initials in the circle are
        // not part of what was said.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Spoken.comment(
            author: author.isCurrentUser ? "Du" : comment.authorName,
            time: CommentTime.label(for: comment.postedAt),
            text: comment.text))
        .contentShape(Rectangle())
        .contextMenu {
            if let onDelete {
                Button("Kommentar löschen", systemImage: "trash", role: .destructive, action: onDelete)
            }
            if let onReport {
                Button("Kommentar melden", systemImage: "exclamationmark.bubble", action: onReport)
            }
        }
        .accessibilityActions {
            if let onDelete {
                Button("Kommentar löschen", action: onDelete)
            }
            if let onReport {
                Button("Kommentar melden", action: onReport)
            }
        }
    }
}

/// The first words of a comment, for the confirmation that names it.
enum CommentExcerpt {
    static func of(_ text: String, limit: Int = 40) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return trimmed.prefix(limit).trimmingCharacters(in: .whitespaces) + " …"
    }
}

/// Takes one's own song of today back, after asking with its name. Shown
/// only while the round runs (`OwnContent.mayDelete`).
struct WithdrawSongButton: View {
    let submission: Submission
    /// What happens once it is gone -- a sheet with only this song closes.
    var onWithdrawn: (() -> Void)?

    @Environment(AppStore.self) private var store
    @State private var isConfirming = false

    var body: some View {
        Button { isConfirming = true } label: {
            Label("Song zurückziehen", systemImage: "arrow.uturn.backward")
                .font(.todBody(13, weight: .bold))
                .foregroundStyle(Color.todAccent2)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "\(submission.track) zurückziehen?",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("Zurückziehen", role: .destructive) {
                Task {
                    if await store.deleteSubmission(submission.id) { onWithdrawn?() }
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Song verschwindet aus der heutigen Runde, mit allen Bewertungen und Kommentaren dazu. Du kannst danach einen anderen posten.")
        }
    }
}
