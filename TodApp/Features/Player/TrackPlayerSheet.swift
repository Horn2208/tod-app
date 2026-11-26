import SwiftUI

struct TrackPlayerSheet: View {
    let candidateTitle: String
    let artist: String
    /// Nil for a song posted without a link. Apple's catalog is then the only
    /// way to hear it, and the title and artist are all it has to go on.
    let source: TrackSource?
    /// The stretch the poster picked out. Its start is where the player
    /// begins with Apple Music's whole song. Spotify's embed plays only its
    /// excerpt, and the player says when the start is not in it. See
    /// `SectionStart`.
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
    @Environment(\.openURL) private var openURL
    @Environment(AppStore.self) private var store
    @Environment(CatalogResolver.self) private var catalog
    @Environment(AppleMusicAccess.self) private var appleMusic
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(AppleMusicPlayer.self) private var wholeSong
    @Environment(PreviewPlayer.self) private var preview
    @Environment(SpotifyRemote.self) private var spotifyRemote
    @Environment(NowPlaying.self) private var nowPlaying
    @Environment(SoundCloudEmbedPlayer.self) private var soundCloud
    @State private var embedFailed = false
    /// What the catalog said about this track. Nil while it has not answered.
    @State private var catalogOutcome: CatalogResolver.Outcome?
    /// The section start last seen, so the picker appearing is not taken for
    /// a move.
    @State private var seenSectionStart: Double?

    /// Which player a track gets -- the one place a view's choice depends on
    /// the service, because the answer is a fact about the service.
    ///
    /// A Spotify track plays Apple's preview when the catalog has the same
    /// recording: native, no web view, no login. With no match it falls back
    /// to Spotify's embed, driven by this app's own controls and always signed
    /// out, so its 30-second excerpt (`SpotifyEmbedPlayer`). SoundCloud has
    /// neither a catalog match nor an API to drive, and keeps its widget. A post
    /// without a link has only Apple: with a match it plays, without one there
    /// is nothing to play at all.
    ///
    /// Whole songs from Apple Music outrank all of that once the listener's
    /// subscription plays them: only they start at the picked section natively.
    ///
    /// A listener connected to Spotify hears Spotify's own preview of a
    /// Spotify song rather than Apple's twin (`prefersSpotify`, the user's
    /// wish, 7. Oktober): the song as it was posted, from the service they
    /// use. Everyone else keeps Apple's.
    enum Player: Equatable { case waiting, appleMusic, applePreview, own, widget, none }

    static func player(
        for service: MusicService?,
        catalog: CatalogResolver.Outcome?,
        appleMusicWholeSongs: Bool = false,
        prefersSpotify: Bool = false
    ) -> Player {
        switch service {
        case .soundcloud:
            return .widget
        case .spotify:
            // Whole songs first. While the catalog is still answering, wait:
            // the embed would otherwise show for a moment and then be swapped
            // out.
            if appleMusicWholeSongs {
                switch catalog {
                case nil: return .waiting
                case .found?: return .appleMusic
                case .notInCatalog?: break
                }
            }
            // Connected to Spotify: Spotify's preview, without waiting for
            // Apple's catalog to answer.
            if prefersSpotify { return .own }
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
        case .own, .widget: return playsWholeSong ? position : nil
        case .applePreview, .none, .waiting: return nil
        }
    }

    /// Whether the catalog is asked at all. Only SoundCloud
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
            appleMusicWholeSongs: appleMusic.playsWholeSongs,
            prefersSpotify: store.isSpotifyConnected)
    }

    private var waveformSeed: String { source?.serviceTrackID ?? catalogKey }

    /// The length the picker lays out: the song's, or an assumed one when the
    /// service did not say (`TrackSection.assumedDuration`).
    private var songLength: Double {
        guard let durationSeconds, durationSeconds > 0 else { return TrackSection.assumedDuration }
        return Double(durationSeconds)
    }

    private var playhead: Double? {
        // The Spotify app plays the whole song: its position is the song's.
        if let source, spotifyRemote.isCurrent(source) { return spotifyRemote.position }
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
        case .widget:
            return Self.songPosition(
                on: route, isThisTrack: source != nil && soundCloud.source == source,
                position: soundCloud.position, playsWholeSong: !soundCloud.failed)
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

    /// Listening rather than picking a section: the full view, after the
    /// reference design -- cover, title, waveform, three buttons, volume, the
    /// services' pills. Picking a section while posting keeps the compact form.
    private var isFullView: Bool { sectionEditing == nil }

    /// The pills below the player: Apple Music once the catalog knows the song,
    /// and the service the post came from.
    private var platformLinks: [PlatformLinks.Link] {
        PlatformLinks.links(
            service: source?.service, servicePage: source?.pageURL,
            appleMusicPage: catalogOutcome?.song?.pageURL)
    }

    /// The cover for the full view. Apple's is asked for large; the post's own
    /// comes first, since it is the one everybody else sees on the card.
    private var coverURL: URL? {
        ArtworkSize.large(source?.artworkURL ?? catalogOutcome?.song?.artworkURL, side: 600)
    }

    /// Whether this app itself makes the sound, so the phone's volume is the
    /// one to show. SoundCloud's widget has its own.
    private var playsInApp: Bool {
        switch route {
        case .appleMusic, .applePreview, .own: true
        case .waiting, .widget, .none: false
        }
    }

    /// Whether the song on this sheet is the one sounding, by whichever
    /// route it plays.
    private var isPlayingHere: Bool {
        if let source, spotifyRemote.isCurrent(source) { return !spotifyRemote.isPaused }
        switch route {
        case .appleMusic: return catalogOutcome?.song.map { wholeSong.isPlaying($0.id) } ?? false
        case .applePreview: return catalogOutcome?.song.map { preview.isPlaying($0.id) } ?? false
        case .own: return source.map(embed.isPlaying) ?? false
        case .widget: return source.map(soundCloud.isPlaying) ?? false
        case .waiting, .none: return false
        }
    }

    private var nowPlayingItem: NowPlaying.Item {
        NowPlaying.Item(
            title: candidateTitle, artist: artist, source: source,
            section: sectionEditing?.wrappedValue ?? section, durationSeconds: durationSeconds,
            appleMusicID: appleMusicID ?? catalogOutcome?.song?.id, isrc: isrc,
            coverColorHex: coverColorHex)
    }

    var body: some View {
        SwiftUI.Group {
            if isFullView {
                fullView
            } else {
                compactView
            }
        }
        // The mini player can open this song again even without a post
        // (`MiniPlayerTarget`): what started is remembered as it was.
        .onChange(of: isPlayingHere) { _, playing in
            if playing { nowPlaying.item = nowPlayingItem }
        }
        // Moving the window while the whole song plays jumps to its new start,
        // so the pick can be judged by ear. Once the drag has settled, not on
        // every point of it.
        //
        // With Spotify (`startsInSpotifyOnPlay`), a move is a press on play
        // from the new start: the whole song in the Spotify app, started or
        // moved there.
        .task(id: sectionEditing?.wrappedValue.start) {
            guard let start = sectionEditing?.wrappedValue.start else { return }
            let previous = seenSectionStart
            seenSectionStart = start
            guard let previous, previous != start else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            if let source, startsInSpotifyOnPlay || spotifyRemote.isCurrent(source) {
                playInSpotify(source, from: start)
                return
            }
            guard playhead != nil else { return }
            switch route {
            case .appleMusic where !wholeSong.isPaused: wholeSong.seek(to: start)
            case .own where !embed.isPaused: embed.seek(to: start)
            case .widget where !soundCloud.isPaused: soundCloud.seek(to: start)
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

    /// The song on show: cover, title, the player, the phone's volume, and the
    /// ways out to the services. No background of its own -- the screen that
    /// holds it paints the cover's colour behind it.
    private var fullView: some View {
        VStack(spacing: 18) {
            cover

            VStack(spacing: 4) {
                // One line; a long title runs sideways rather than wrapping.
                MarqueeText(text: candidateTitle, font: .todDisplay(24))
                if !artist.isEmpty {
                    Text(artist)
                        .font(.todBody(15))
                        .foregroundStyle(Color.todTextDim)
                }
            }
            .multilineTextAlignment(.center)
            // Title and artist are one line of speech, not two stops.
            .accessibilityElement(children: .combine)

            routePlayer

            if playsInApp {
                SystemVolumeSlider()
            }

            platformPills
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// Picking a section while posting: title, the picker, and a small player.
    private var compactView: some View {
        // Centred like the full view and the rest of the app, only smaller:
        // no cover and no full player while a section is being picked.
        VStack(alignment: .center, spacing: 16) {
            VStack(alignment: .center, spacing: 4) {
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
                    playhead: playhead,
                    reachNote: SectionReach.note(for: source?.service))
            }

            routePlayer

            platformPills

            Spacer()
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding()
    }

    /// Large, square, with a soft shadow; the post's colour until it loads, and
    /// for good when there is no cover.
    private var cover: some View {
        // The hero: a square about 70 per cent of the screen's width. The
        // square comes first and the picture fills it -- a picture sized
        // first stretches the frame to its own shape.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .containerRelativeFrame(.horizontal) { width, _ in width * 0.7 }
            .overlay {
                CrossfadeCover(url: coverURL, placeholder: Color(hex: coverColorHex ?? "#2f2f33"))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .padding(.top, 8)
        // The title right below says what this is.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var platformPills: some View {
        let links = platformLinks
        if !links.isEmpty {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    ForEach(links) { link in
                        if link.kind == .spotify, let source, wholeSongInSpotify {
                            PlatformPill(link: link) { startWholeSongInSpotify(source, from: section?.start) }
                        } else {
                            PlatformPill(link: link)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if wholeSongInSpotify, let failure = spotifyRemote.failure {
                    Text(failure)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextFaint)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    /// Whether "Spotify öffnen" also starts the whole song at the picked
    /// section (`SpotifyWholeSong`) -- a connected Premium account.
    private var wholeSongInSpotify: Bool {
        SpotifyWholeSong.offers(service: source?.service, capabilities: store.capabilities)
    }

    /// Whether the big play button itself starts the song in the Spotify app
    /// (`SpotifyWholeSong.startsOnPlay`).
    private var startsInSpotifyOnPlay: Bool {
        SpotifyWholeSong.startsOnPlay(
            offers: wholeSongInSpotify,
            isAppInstalled: spotifyRemote.isAppInstalled,
            appleMusicWholeSongs: appleMusic.playsWholeSongs,
            route: route)
    }

    @ViewBuilder
    private var routePlayer: some View {
        // Playing in the Spotify app, through App Remote: this player shows
        // and steers Spotify's, whatever route the song would take here.
        if let source, spotifyRemote.isCurrent(source) {
            SpotifyRemotePlayer(source: source, waveformSeed: waveformSeed, showsWaveform: sectionEditing == nil)
        } else if let source, startsInSpotifyOnPlay {
            // Premium and the Spotify app: play here means the whole song
            // there, from the section -- no need to find the pill first.
            SpotifyAppStartPlayer(
                waveformSeed: waveformSeed,
                showsWaveform: sectionEditing == nil,
                section: section,
                duration: songLength,
                start: { from in startWholeSongInSpotify(source, from: from) })
        } else {
            routePlayerHere
        }
    }

    @ViewBuilder
    private var routePlayerHere: some View {
        switch route {
        case .waiting:
            // The catalog answers within a fraction of a second. Saying so
            // beats flashing Spotify's player and then swapping it out.
            Text("Player lädt …")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextFaint)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
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
            if let source {
                // SoundCloud hidden, under the app's own controls; SoundCloud's
                // own widget only when the hidden one was refused the track.
                if soundCloud.source == source, soundCloud.failed {
                    soundCloudWidget(source)
                } else {
                    SoundCloudOwnPlayer(
                        source: source, uploader: artist, waveformSeed: waveformSeed, section: section,
                        submissionID: submissionID, showsWaveform: sectionEditing == nil)
                }
            }
        case .none:
            nothingToPlay
        }
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
                PlayerHintLine(hint: .widgetFromStart)
            }
        }
    }

    /// "Spotify öffnen" for a connected Premium account: the Spotify app
    /// opens on the song, and the song starts there, whole, at the picked
    /// section (`SpotifyWholeSong`). What plays here stops first: two things
    /// sounding at once is never what a tap means.
    ///
    /// The app is opened before the command is sent. Paused in the
    /// background, iOS freezes it within moments, and a frozen app starts
    /// nothing: Spotify accepted the command and nothing was heard (measured
    /// on a phone, 24 September). In front it can -- and the command follows
    /// from here, in the seconds iOS gives this app after it leaves the screen.
    private func startWholeSongInSpotify(_ source: TrackSource, from start: Double?) {
        embed.pause()
        preview.pause()
        wholeSong.pause()
        soundCloud.pause()
        // Spotify's App Remote: opens the Spotify app on the song, starts it,
        // comes back here and moves it to the section (`SpotifyRemote`).
        nowPlaying.submissionID = submissionID
        spotifyRemote.play(source, from: start) {
            openURL(source.pageURL)
        }
    }

    /// Play from `start` in the Spotify app: moved there when Spotify already
    /// has the song, started there otherwise.
    private func playInSpotify(_ source: TrackSource, from start: Double) {
        guard spotifyRemote.isCurrent(source), spotifyRemote.isConnected else {
            return startWholeSongInSpotify(source, from: start)
        }
        spotifyRemote.seek(to: start)
        if spotifyRemote.isPaused { spotifyRemote.togglePause() }
    }

    static func timestamp(_ seconds: Double) -> String {
        Spoken.time(seconds)
    }
}

private struct EmbedFallback: View {
    let source: TrackSource

    var body: some View {
        HStack(spacing: 12) {
            CrossfadeCover(url: source.artworkURL, placeholder: Color.todSurface2)
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

/// A way out to a service's own app: a capsule with a thin rim, not a filled
/// button -- the play button stays the one thing on the screen that is.
private struct PlatformPill: View {
    let link: PlatformLinks.Link
    /// Done instead of following the link, when set.
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button(action: action) { pill }
                .buttonStyle(.plain)
        } else {
            Link(destination: link.url) { pill }
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            mark
            Text(link.label)
                .font(.todBody(13, weight: .semibold))
        }
        .foregroundStyle(Color.todText)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 1))
    }

    /// The services' own icons (`BrandIcon`); SoundCloud's still a stand-in.
    @ViewBuilder
    private var mark: some View {
        switch link.kind {
        case .appleMusic:
            BrandIcon(brand: .appleMusic, size: 18)
                .accessibilityHidden(true)
        case .spotify:
            BrandIcon(brand: .spotify, size: 18)
                .accessibilityHidden(true)
        case .soundcloud:
            BrandIcon(brand: .soundCloud, size: 18)
                .accessibilityHidden(true)
        }
    }
}
