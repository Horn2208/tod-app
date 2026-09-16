import SwiftUI

struct TrackPlayerSheet: View {
    let candidateTitle: String
    let artist: String
    /// Nil for a song posted without a link. Apple's catalog is then the only
    /// way to hear it, and the title and artist are all it has to go on.
    let source: TrackSource?
    /// The stretch the poster picked out. Its start is where the player
    /// begins -- when Spotify delivers the whole song; with only the excerpt,
    /// the player says the start is not in it. See `SectionStart`.
    var section: TrackSection? = nil

    /// The full song's length, when the post knows it. It lets the catalog
    /// match tell two recordings of one title apart.
    var durationSeconds: Int? = nil
    /// The Apple Music id stored with a post, so it is looked up rather than
    /// searched for again.
    var appleMusicID: String? = nil
    /// The recording's ISRC, when the post has one. It finds the Apple twin
    /// of a Spotify post exactly, where a title search can only guess.
    var isrc: String? = nil
    /// The post's cover colour, for the card shown when there is nothing to play.
    var coverColorHex: String? = nil
    /// The post this is, when it is one. Recorded when play is pressed, so the
    /// mini player can open it again.
    var submissionID: Int? = nil
    /// Set while posting: the section is being picked, and the picker becomes
    /// this player's waveform -- one waveform for listening and picking, not
    /// two stacked. Nil everywhere a song is only listened to.
    var sectionEditing: Binding<TrackSection>? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogResolver.self) private var catalog
    @Environment(AppleMusicAccess.self) private var appleMusic
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @State private var embedFailed = false
    /// What the catalog said about this track. Nil while it has not answered.
    @State private var catalogOutcome: CatalogResolver.Outcome?

    /// Which player a track gets -- the one place a view's choice depends on
    /// the service, because the answer is a fact about the service.
    ///
    /// A Spotify track plays Apple's preview when the catalog has the same
    /// recording: native, no web view, no login. With no match it falls back
    /// to Spotify's embed, driven by this app's own controls. A Spotify login
    /// in the player keeps the embed regardless -- that session may bring the
    /// whole song, which nothing from Apple can until MusicKit. SoundCloud has
    /// neither a catalog match nor an API to drive, and keeps its widget. A post
    /// without a link has only Apple: with a match it plays, without one there
    /// is nothing to play at all.
    ///
    /// Whole songs from Apple Music outrank all of that once the listener's
    /// subscription plays them: only they start at the picked section natively.
    enum Player: Equatable { case waiting, appleMusic, applePreview, own, widget, none }

    static func player(
        for service: MusicService?,
        catalog: CatalogResolver.Outcome?,
        spotifyWebSession: Bool,
        appleMusicWholeSongs: Bool = false
    ) -> Player {
        switch service {
        case .soundcloud:
            return .widget
        case .spotify:
            // Whole songs first. While the catalog is still answering, wait:
            // with a Spotify login the embed would otherwise show for a moment
            // and then be swapped out.
            if appleMusicWholeSongs {
                switch catalog {
                case nil: return .waiting
                case .found?: return .appleMusic
                case .notInCatalog?: break
                }
            }
            if spotifyWebSession { return .own }
            switch catalog {
            case nil: return .waiting
            case .found?: return .applePreview
            case .notInCatalog?: return .own
            }
        case nil:
            switch catalog {
            case nil: return .waiting
            case .found?: return appleMusicWholeSongs ? .appleMusic : .applePreview
            case .notInCatalog?: return .none
            }
        }
    }

    /// Where playback stands on the song's own timeline, in seconds, when that
    /// is known. A whole song's position is. A preview's is not -- Apple does
    /// not say where its 30 seconds lie in the song -- and neither is the
    /// position in Spotify's excerpt; drawn on the song they would point at the
    /// wrong place.
    static func songPosition(
        on route: Player, isThisTrack: Bool, position: Double, playsWholeSong: Bool
    ) -> Double? {
        guard isThisTrack else { return nil }
        switch route {
        case .appleMusic: return position
        case .own: return playsWholeSong ? position : nil
        case .applePreview, .widget, .none, .waiting: return nil
        }
    }

    /// Whether the catalog is asked at all. Still asked with a Spotify login in
    /// the player: the match is stored with a post either way. Only SoundCloud
    /// is left out -- its widget plays whatever happens, and no title match is
    /// going to be trusted to redirect a SoundCloud upload somewhere else.
    static func looksUpCatalog(for service: MusicService?) -> Bool {
        service != .soundcloud
    }

    private var catalogKey: String {
        CatalogKey.of(source: source, title: candidateTitle, artist: artist)
    }

    private var route: Player {
        Self.player(
            for: source?.service, catalog: catalogOutcome,
            spotifyWebSession: embed.hasWebSession,
            appleMusicWholeSongs: appleMusic.playsWholeSongs)
    }

    private var waveformSeed: String { source?.serviceTrackID ?? catalogKey }

    /// The length the picker lays out: the song's, or an assumed one when the
    /// service did not say (`TrackSection.assumedDuration`).
    private var songLength: Double {
        guard let durationSeconds, durationSeconds > 0 else { return TrackSection.assumedDuration }
        return Double(durationSeconds)
    }

    private var playhead: Double? {
        switch route {
        case .appleMusic:
            let song = catalogOutcome?.song
            return Self.songPosition(
                on: route, isThisTrack: song != nil && wholeSong.songID == song?.id,
                position: wholeSong.position, playsWholeSong: true)
        case .own:
            return Self.songPosition(
                on: route, isThisTrack: source != nil && embed.source == source,
                position: embed.position, playsWholeSong: embed.isSectionHearable == true)
        default:
            return nil
        }
    }

    // NOT a capability decision -- both stay `source.service == .spotify`
    // deliberately. These are presentation facts about a specific service
    // (its widget's height, the real name of the destination it links to),
    // not decisions about what an account may do.
    private var embedHeight: CGFloat {
        // Spotify's compact player is shorter than SoundCloud's widget.
        source?.service == .spotify ? 152 : 166
    }

    private var linkLabel: String {
        source?.service == .spotify ? "In Spotify öffnen" : "In SoundCloud öffnen"
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

            if let sectionEditing {
                TrackSectionPicker(
                    total: songLength,
                    lengthIsAssumed: (durationSeconds ?? 0) <= 0,
                    waveformSeed: waveformSeed,
                    section: sectionEditing,
                    playhead: playhead)
            }

            switch route {
            case .waiting:
                // The catalog answers within a fraction of a second. Saying so
                // beats flashing Spotify's player and then swapping it out.
                Text("Player lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            case .appleMusic:
                if let song = catalogOutcome?.song {
                    AppleWholeSongPlayer(
                        song: song,
                        waveformSeed: waveformSeed,
                        section: section,
                        submissionID: submissionID,
                        showsWaveform: sectionEditing == nil)
                }
            case .applePreview:
                if let song = catalogOutcome?.song {
                    ApplePreviewPlayer(
                        song: song,
                        waveformSeed: waveformSeed,
                        section: section,
                        submissionID: submissionID,
                        showsWaveform: sectionEditing == nil)
                }
            case .own:
                if let source {
                    SpotifyOwnPlayer(
                        source: source, section: section, submissionID: submissionID,
                        showsWaveform: sectionEditing == nil)
                }
            case .widget:
                if let source { soundCloudWidget(source) }
            case .none:
                nothingToPlay
            }

            if let source {
                Link(destination: source.pageURL) {
                    Text(linkLabel)
                        .font(.todBody(13, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todBackground)
        // Moving the window while the whole song plays jumps to its new start,
        // so the pick can be judged by ear. Once the drag has settled, not on
        // every point of it.
        .task(id: sectionEditing?.wrappedValue.start) {
            guard let start = sectionEditing?.wrappedValue.start, playhead != nil else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            switch route {
            case .appleMusic where !wholeSong.isPaused: wholeSong.seek(to: start)
            case .own where !embed.isPaused: embed.seek(to: start)
            default: break
            }
        }
        .task(id: catalogKey) {
            catalogOutcome = catalog.settled(for: catalogKey)
            guard catalogOutcome == nil, Self.looksUpCatalog(for: source?.service) else { return }
            catalogOutcome = await catalog.resolve(
                key: catalogKey, title: candidateTitle, artist: artist,
                durationSeconds: durationSeconds, knownID: appleMusicID, isrc: isrc)
        }
        // NOT `.presentationDetents`/`.presentationBackground` here: those
        // target "the enclosing sheet" (per SwiftUI's own docs) regardless of
        // how deep this view sits in the hierarchy. PostSongView embeds this
        // view INLINE inside its own already-presented sheet, and those two
        // modifiers would hijack and forcibly resize/collapse THAT sheet the
        // instant a candidate is selected. Apply them at the call site that
        // actually presents this view as a sheet (SongDetailView's callers) instead.
    }

    /// Nothing to play: no link, and Apple's catalog has no such song. The
    /// title and the talk under it are still worth a screen, so this says what
    /// is missing rather than leaving a gap where a player would be.
    private var nothingToPlay: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color(hex: coverColorHex ?? "#2f2f33"))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text("Nichts zum Abspielen")
                    .font(.todBody(14, weight: .bold))
                    .foregroundStyle(Color.todText)
                Text("Kein Link hinterlegt, und Apple Music kennt den Song unter diesem Titel nicht.")
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

    // MARK: - SoundCloud

    /// SoundCloud's own widget. It plays from the beginning whatever was
    /// picked, and says so rather than letting the section look ignored.
    @ViewBuilder
    private func soundCloudWidget(_ source: TrackSource) -> some View {
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
                Text("Der Abschnitt ist gesetzt. Das SoundCloud-Widget spielt den Song trotzdem von Anfang an.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        Spoken.time(seconds)
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

/// This app's own transport for a Spotify track: a progress line and one
/// button, in this app's colours, on top of an embed nobody sees. The same
/// controls for everyone -- Spotify decides whether 30 seconds or the whole
/// song comes out, and that decision follows the web view's login state, not
/// anything here.
private struct SpotifyOwnPlayer: View {
    @Environment(SpotifyEmbedPlayer.self) private var player
    @Environment(PreviewPlayer.self) private var preview
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    let source: TrackSource
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.source == source }
    private var isPlaying: Bool { isMine && !player.isPaused }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A player that is not ready must say so. Silently accepting taps
            // and doing nothing is how this looked while the controller had
            // not answered, and it is indistinguishable from a broken app.
            switch player.status {
            case .failed(let message):
                Text(message)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            case .idle, .loading:
                Text("Player lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            case .ready:
                if isMine, let error = player.embedError {
                    Text(error)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todAccent2)
                } else if isMine, player.isStarting {
                    // The tap registered; the embed is still loading the
                    // track. Said, so the button does not look ignored.
                    Text("Startet …")
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextFaint)
                }
            }

            if isMine, let section {
                if player.isSectionHearable == false {
                    // Measured, not assumed: Spotify reported a length that is
                    // the excerpt's, so the start the poster picked is not in
                    // what is playing.
                    Text("Spotify liefert hier nur die 30-Sekunden-Vorschau — der Abschnitt ab \(TrackPlayerSheet.timestamp(section.start)) ist darin nicht enthalten. Ganze Songs gibt es mit Spotify Premium und Anmeldung im Profil.")
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextFaint)
                } else {
                    Text("Abschnitt ab \(TrackPlayerSheet.timestamp(section.start))")
                        .font(.todMono(12, weight: .semibold))
                        .foregroundStyle(Color.todTextFaint)
                }
            }

            Transport(
                waveformSeed: source.serviceTrackID,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: isPlaying,
                position: isMine ? player.position : 0,
                duration: isMine ? player.duration : 0,
                isEnabled: player.status == .ready,
                toggle: {
                    PlayPress(preview: preview, wholeSong: wholeSong, embed: player, nowPlaying: nowPlaying)
                        .toggleEmbed(source, from: section, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                }
            )
        }
        // Points the shared player at this track without starting it: opening
        // a song must not start noise by itself.
        .task(id: source) {
            // Only while nothing else is playing. Loading swaps the embed's
            // track, which silences whatever it had -- so opening a second
            // song used to stop the first before play was even pressed, and
            // took the mini player with it. With something playing, the press
            // on play does the loading instead: `togglePlay` loads and plays.
            guard preview.isPaused, player.isPaused || player.source == source else { return }
            player.load(source, startAt: section?.start)
        }
    }
}

/// Apple's preview, played natively. Honest about what it is: a fixed excerpt
/// Apple chooses, so a picked section may well lie outside it.
private struct ApplePreviewPlayer: View {
    @Environment(PreviewPlayer.self) private var player
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(NowPlaying.self) private var nowPlaying
    let song: CatalogSong
    let waveformSeed: String
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.songID == song.id }
    private var failure: String? { isMine ? player.failure : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure {
                Text(failure)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            } else if isMine, player.duration == 0 {
                // The item is not ready yet -- once it took nine seconds. A
                // press in that time plays when it is; until then, say so,
                // rather than a pause symbol over silence.
                Text("Vorschau lädt …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            if let section {
                Text("Apple Music spielt hier eine Vorschau, einen festen Ausschnitt. Ob der Abschnitt ab \(TrackPlayerSheet.timestamp(section.start)) darin liegt, sagt Apple nicht.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: player.isPlaying(song.id),
                position: isMine ? player.position : 0,
                duration: isMine ? player.duration : 0,
                // A failed load is tried again on the press; only a song
                // without a preview has nothing to try.
                isEnabled: song.previewURL != nil,
                toggle: {
                    PlayPress(preview: player, wholeSong: wholeSong, embed: embed, nowPlaying: nowPlaying)
                        .togglePreview(song, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                }
            )

            // Apple's terms for previews ask for a way to the song in its store.
            if let page = song.pageURL {
                Link(destination: page) {
                    Text("In Apple Music öffnen")
                        .font(.todBody(13, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
        }
        .task(id: song.id) {
            // The same rule as the embed's: looking at a song must not silence
            // the one already playing. The play button loads it when pressed,
            // and pauses the embed then.
            guard embed.isPaused, player.isPaused || player.songID == song.id else { return }
            player.load(song)
        }
    }
}

/// The controls both own players share: a waveform that shows progress and
/// takes a drag to seek, one round button, and the time.
private struct Transport: View {
    let waveformSeed: String
    /// Off while posting: the section picker above is the waveform then, and
    /// the progress goes round the button instead.
    let showsWaveform: Bool
    let progress: Double
    let isPlaying: Bool
    let position: Double
    let duration: Double
    let isEnabled: Bool
    let toggle: () -> Void
    /// A fraction of the length, 0 to 1. The player turns it into seconds.
    let seek: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsWaveform {
                waveform
            }

            HStack(spacing: 14) {
                Button(action: toggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.todBackground)
                        .frame(width: 46, height: 46)
                        .background(Color.todAccent, in: Circle())
                        .padding(showsWaveform ? 0 : 5)
                        .overlay {
                            if !showsWaveform {
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(Color.todAccent2, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .padding(1.5)
                            }
                        }
                }
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.4)
                .accessibilityLabel(isPlaying ? "Pause" : "Abspielen")

                Text("\(TrackPlayerSheet.timestamp(position)) / \(TrackPlayerSheet.timestamp(duration))")
                    .font(.todMono(12))
                    .foregroundStyle(Color.todTextFaint)
                    // "0:30 / 3:20" read out as it stands is a slash in the
                    // middle of two numbers.
                    .accessibilityLabel(Spoken.playback(position: position, duration: duration))

                Spacer()
            }
        }
    }

    /// The shape is generated from the track id, not measured from the audio
    /// -- see `Waveform`. What it shows truthfully is where playback has
    /// reached, and dragging across it moves there.
    private var waveform: some View {
        let bars = Waveform.bars(forTrack: waveformSeed)

        return GeometryReader { geo in
            HStack(alignment: .center, spacing: 2) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, height in
                    let reached = Double(index) / Double(max(bars.count - 1, 1)) <= progress
                    Capsule()
                        .fill(reached ? AnyShapeStyle(playedStyle) : AnyShapeStyle(Color.todSurface3))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(3, geo.size.height * height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` so a plain tap seeks too -- on a bar
                // this thin, most attempts to jump somewhere are taps.
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard geo.size.width > 0 else { return }
                        seek(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 42)
        // Forty bars and a drag gesture are nothing at all to VoiceOver. One
        // element instead, carrying the position as its value, with swipe up
        // and down moving five seconds at a time.
        .accessibilityElement()
        .accessibilityLabel("Wiedergabe")
        .accessibilityValue(Spoken.playback(position: position, duration: duration))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = 5 / duration
            switch direction {
            case .increment: seek(min(progress + step, 1))
            case .decrement: seek(max(progress - step, 0))
            @unknown default: break
            }
        }
    }

    private var playedStyle: LinearGradient {
        LinearGradient(
            colors: [Color.todAccent, Color.todAccent2],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// A whole song from Apple Music, started at the picked section -- for a
/// listener whose subscription plays catalog songs; everyone else gets the
/// preview. Nothing is queued when the song opens, because queueing silences
/// whatever is playing. The press on play does it.
private struct AppleWholeSongPlayer: View {
    @Environment(AppleMusicPlayer.self) private var player
    @Environment(PreviewPlayer.self) private var preview
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(NowPlaying.self) private var nowPlaying
    let song: CatalogSong
    let waveformSeed: String
    let section: TrackSection?
    let submissionID: Int?
    let showsWaveform: Bool

    private var isMine: Bool { player.songID == song.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isMine, let failure = player.failure {
                Text(failure)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            } else if isMine, player.isStarting {
                // Fetching and queueing takes a moment. Said, so the press
                // does not look ignored.
                Text("Startet …")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
            }

            if let section {
                Text("Ganzer Song, ab \(TrackPlayerSheet.timestamp(section.start))")
                    .font(.todMono(12, weight: .semibold))
                    .foregroundStyle(Color.todTextFaint)
            }

            Transport(
                waveformSeed: waveformSeed,
                showsWaveform: showsWaveform,
                progress: isMine ? player.progress : 0,
                isPlaying: player.isPlaying(song.id),
                position: isMine ? player.position : 0,
                // The catalog knows the length before anything is queued, so
                // the clock can say it from the start.
                duration: isMine ? player.duration : Double(song.durationSeconds ?? 0),
                isEnabled: true,
                toggle: {
                    PlayPress(preview: preview, wholeSong: player, embed: embed, nowPlaying: nowPlaying)
                        .toggleWholeSong(song, from: section, post: submissionID)
                },
                seek: { fraction in
                    guard isMine, player.duration > 0 else { return }
                    player.seek(to: fraction * player.duration)
                }
            )

            if let page = song.pageURL {
                Link(destination: page) {
                    Text("In Apple Music öffnen")
                        .font(.todBody(13, weight: .bold))
                        .foregroundStyle(Color.todAccent)
                }
            }
        }
    }
}
