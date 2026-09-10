import SwiftUI

/// Home. Two things matter here: the song you put up today, and how many days
/// in a row you have managed it. Everything else is a tab away.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var isPosting = false
    @State private var isPlayingSheetOpen = false

    private var group: Group? { store.currentGroup }
    private var me: Member? { group.flatMap(HomeToday.me) }
    private var mySong: Submission? {
        group.flatMap { HomeToday.mySubmission(in: $0, userID: store.profile.id) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if group != nil {
                    streak
                    if let song = mySong {
                        songCard(song)
                    } else {
                        postPrompt
                    }
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Home")
        .sheet(isPresented: $isPosting) { PostSongView() }
        .sheet(isPresented: $isPlayingSheetOpen) {
            if let song = mySong {
                SongDetailView(submission: song)
                    .presentationDetents([.large])
                    .presentationBackground(Color.todBackground)
            }
        }
    }

    // MARK: - Streak

    private var streak: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // SF Symbols rather than emoji: an emoji brings its own colour
                // and its own look per platform, and the streak has a token of
                // its own to wear.
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.todStreak)
                Text("\(me?.currentStreak ?? 0)")
                    .font(.todDisplay(56))
                    .foregroundStyle(Color.todStreak)
            }
            Text(streakWording)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
    }

    private var streakWording: String {
        switch me?.currentStreak ?? 0 {
        case 0: "Noch keine Serie. Heute fängt eine an."
        case 1: "Tag in Folge"
        default: "Tage in Folge"
        }
    }

    // MARK: - Dein Song

    private func songCard(_ song: Submission) -> some View {
        VStack(spacing: 14) {
            AsyncImage(url: song.source?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color(hex: song.coverColorHex))
            }
            .frame(width: 220, height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            VStack(spacing: 4) {
                Text(song.track)
                    .font(.todDisplay(24))
                    .foregroundStyle(Color.todText)
                    .multilineTextAlignment(.center)
                Text(song.artist)
                    .font(.todBody(15))
                    .foregroundStyle(Color.todTextDim)
            }

            if let section = song.section {
                Text("Abschnitt \(timestamp(section.start))–\(timestamp(section.end))")
                    .font(.todMono(11))
                    .foregroundStyle(Color.todTextFaint)
            }

            // One way in for both: behind this sits the song with its player
            // and everything said about it. The label names whichever is
            // actually there, so a song without a link promises no playback.
            Button(song.source != nil ? "Anhören" : "Kommentare") { isPlayingSheetOpen = true }
                .buttonStyle(TodPrimaryButtonStyle())
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
        // The song's own colour, blurred out behind the card, so today's post
        // looks like itself rather than like every other card in the app.
        .background(
            Color(hex: song.coverColorHex)
                .blur(radius: 60)
                .opacity(0.55)
                .padding(-30)
        )
    }

    private func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: - Noch nichts gepostet

    private var postPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.system(size: 38))
                .foregroundStyle(Color.todAccent)
            Text("Heute noch nichts von dir")
                .font(.todDisplay(22))
                .foregroundStyle(Color.todText)
            Text("Ein Song pro Tag. Deine Gruppe wartet.")
                .font(.todBody(14))
                .foregroundStyle(Color.todTextDim)
                .multilineTextAlignment(.center)
            Button("+ Song posten") { isPosting = true }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24).strokeBorder(Color.todLine, lineWidth: 0.5)
        )
    }
}

struct TodPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// A nested view, because `isEnabled` reaches a button style only through a
    /// real view's environment -- reading it on the style itself never sees it,
    /// which is how a disabled button ended up looking pressable.
    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.todBody(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(background)
                .foregroundStyle(isEnabled ? Color.todBackground : Color.todTextFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private var background: Color {
            guard isEnabled else { return .todSurface2 }
            return Color.todAccent.opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
