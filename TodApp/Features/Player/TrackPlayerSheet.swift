import SwiftUI

struct TrackPlayerSheet: View {
    let candidateTitle: String
    let artist: String
    let source: TrackSource
    /// The stretch the poster picked out. Decoration until a provider that can
    /// start at a position is behind the account -- that is the one thing that
    /// changes what this section actually means.
    var section: TrackSection? = nil
    var capabilities: MusicProviderCapabilities = .none
    let provider: any MusicProvider
    /// `AppStore`'s mirror of what the provider is actually playing right
    /// now -- not a local flag. The provider can stop this on its own (its
    /// end-of-section timer), and only it knows when that happens; a flag
    /// this view flipped itself would keep claiming "Stopp" after the music
    /// had already ended.
    var currentlyPlaying: TrackSource? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var embedFailed = false
    @State private var playbackError: String?

    /// True only while THIS track -- not some other one in a list of several --
    /// is the one the provider reports playing.
    private var isPlaying: Bool { currentlyPlaying == source }

    /// Which player a track gets, decided purely from what the signed-in
    /// account can do -- never from `source.service`. A provider that can
    /// start at a position gets our own player and no embed at all; anything
    /// else (no sign-in, a free account, a provider that can play but not
    /// seek) keeps today's embed, which always starts from the beginning
    /// regardless of what was picked.
    enum Mode: Equatable { case native, embed }

    static func mode(for capabilities: MusicProviderCapabilities) -> Mode {
        capabilities.canStartAtPosition ? .native : .embed
    }

    private var mode: Mode { Self.mode(for: capabilities) }

    // NOT a capability decision -- both stay `source.service == .spotify`
    // deliberately. These are presentation facts about a specific service
    // (its widget's height, the real name of the destination it links to),
    // not decisions about what an account may do.
    private var embedHeight: CGFloat {
        // Spotify's compact player is shorter than SoundCloud's widget.
        source.service == .spotify ? 152 : 166
    }

    private var linkLabel: String {
        source.service == .spotify ? "In Spotify öffnen" : "In SoundCloud öffnen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidateTitle)
                    .font(.todDisplay(20))
                    .foregroundStyle(Color.todText)
                if !artist.isEmpty {
                    Text(artist)
                        .font(.todBody(14))
                        .foregroundStyle(Color.todTextDim)
                }
            }

            switch mode {
            case .native: nativePlayer
            case .embed: embedPlayer
            }

            Link(destination: source.pageURL) {
                Text(linkLabel)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todBackground)
        // NOT `.presentationDetents`/`.presentationBackground` here: those
        // target "the enclosing sheet" (per SwiftUI's own docs) regardless of
        // how deep this view sits in the hierarchy. PostSongView embeds this
        // view INLINE inside its own already-presented sheet, and those two
        // modifiers would hijack and forcibly resize/collapse THAT sheet the
        // instant a candidate is selected. Apply them at the call site that
        // actually presents this view as a sheet (RevealView) instead.
    }

    // MARK: - Native player

    /// Our own player: the track's artwork as the main element, a play
    /// control that becomes a stop while playing, the picked section named,
    /// and an honest word about where the sound actually comes out.
    @ViewBuilder
    private var nativePlayer: some View {
        VStack(alignment: .leading, spacing: 12) {
            AsyncImage(url: source.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color.todSurface2)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let section {
                Text("Abschnitt \(Self.timestamp(section.start))–\(Self.timestamp(section.end))")
                    .font(.todMono(12, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
            }

            Button {
                Task { await togglePlayback() }
            } label: {
                Label(
                    isPlaying ? "Stopp" : "Abspielen",
                    systemImage: isPlaying ? "stop.fill" : "play.fill"
                )
            }
            .buttonStyle(TodPrimaryButtonStyle())

            if let playbackError {
                Text(playbackError)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            }

            // Said plainly, in the player itself: someone who presses play
            // and hears nothing from their phone needs to know why. This is
            // the known, accepted cost of this design -- there is no fallback
            // to the embed when nothing answers here.
            Text("Die Wiedergabe läuft über Spotify Connect auf dem Gerät, auf dem du gerade Spotify offen hast — nicht in dieser App.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)
        }
    }

    /// Only asks the provider to change state; never sets `isPlaying` itself
    /// -- that would be exactly the guess this view used to make and the
    /// provider then contradicted. `currentlyPlaying` flowing back down from
    /// `AppStore` is what actually flips the button, on both success and the
    /// provider's own later say-so.
    private func togglePlayback() async {
        playbackError = nil
        if isPlaying {
            await provider.stop()
            return
        }
        do {
            try await provider.play(source, from: section)
        } catch {
            playbackError = PostSongModel.message(for: error)
        }
    }

    // MARK: - Embed player

    /// Unchanged from before this task: Spotify's or SoundCloud's own widget,
    /// which plays a preview picked by the service, not the section picked
    /// here. When a section exists, that gap is said out loud instead of
    /// left to look like the picker simply did nothing.
    @ViewBuilder
    private var embedPlayer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A failed embed used to leave a blank white rectangle standing.
            // The artwork plus the link below is what the spec asks for instead.
            if embedFailed {
                EmbedFallback(source: source)
                    .frame(height: embedHeight)
            } else {
                TrackEmbedView(source: source, didFail: $embedFailed)
                    .frame(height: embedHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if section != nil {
                Text("Der gewählte Abschnitt ist ein Hinweis für die Gruppe — abgespielt werden kann er über diesen Zugang nicht.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private struct EmbedFallback: View {
    let source: TrackSource

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: source.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color.todSurface2)
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Der Player lädt gerade nicht.")
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todText)
                Text(source.service == .spotify
                     ? "Über den Link darunter geht der Song in Spotify auf."
                     : "Über den Link darunter geht der Song in SoundCloud auf.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextDim)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
