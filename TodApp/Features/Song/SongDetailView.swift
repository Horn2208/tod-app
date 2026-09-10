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
    @State private var draft = ""

    /// Read back from the store on every redraw rather than kept from the
    /// value this view was handed: a comment lands in the repository, and the
    /// copy passed in at presentation time would never show it.
    private var current: Submission {
        store.groups.flatMap(\.submissions).first { $0.id == submission.id } ?? submission
    }

    private var group: Group? { store.group(containing: submission.id) }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    player
                    comments
                }
                .padding(.bottom, 16)
            }
            replyField
        }
        .background(Color.todBackground)
    }

    // MARK: - Player

    @ViewBuilder
    private var player: some View {
        if let source = current.source {
            // One instance, inline -- never inside the comment list. Each
            // `TrackEmbedView` is its own web process, so a player per row
            // would be a process per row.
            TrackPlayerSheet(
                candidateTitle: current.track,
                artist: current.artist,
                source: source,
                section: current.section,
                capabilities: store.capabilities,
                provider: store.provider,
                currentlyPlaying: store.currentlyPlaying
            )
        } else {
            // A song posted before links existed, or one whose service went
            // away. It still has a title and comments, and both are worth
            // showing -- an empty screen would be the only alternative.
            HStack(spacing: 12) {
                Rectangle()
                    .fill(Color(hex: current.coverColorHex))
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(current.track)
                        .font(.todDisplay(18))
                        .foregroundStyle(Color.todText)
                    Text(current.artist)
                        .font(.todBody(13))
                        .foregroundStyle(Color.todTextDim)
                    Text("Kein Link hinterlegt")
                        .font(.todMono(11))
                        .foregroundStyle(Color.todTextFaint)
                }
                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Comments

    private var comments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(countLabel)
                .font(.todMono(12, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            ForEach(current.comments) { comment in
                CommentRow(comment: comment, author: author(of: comment))
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
                hasPostedToday: false,
                postedDates: []
            )
    }

    // MARK: - Reply

    private var replyField: some View {
        HStack(spacing: 10) {
            TextField("Sag was dazu", text: $draft, axis: .vertical)
                .font(.todBody(14))
                .foregroundStyle(Color.todText)
                .lineLimit(1...4)
                .textFieldStyle(.plain)

            Button {
                let text = draft
                // Cleared before the write, not after: the field belongs to
                // this view and the round trip through the repository is long
                // enough to type into twice.
                draft = ""
                Task { await store.addComment(text, to: submission.id) }
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
    }
}
