import SwiftUI

struct PostSongView: View {
    enum Mode: String, CaseIterable { case search = "Suchen", link = "Link einfügen" }

    @Environment(AppStore.self) private var store
    @Environment(CatalogResolver.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @State private var model: PostSongModel?
    @State private var mode: Mode = .search

    // Bound directly to the TextField so typing never waits on a hop through
    // `Task { await model.queryChanged(...) }` -- that indirection made the
    // bound property update asynchronously and dropped/lagged keystrokes when
    // tried in the simulator. `.task(id:)` re-runs whenever this local value
    // changes and drives the model from there instead.
    @State private var queryText = ""
    @State private var linkFieldText = ""
    /// The group the song goes to: the chosen one, unless picked otherwise
    /// here -- posting into the wrong one was easy with nothing saying which
    /// (the brief's second audit, B1).
    @State private var targetGroupID: String?
    /// While the post is on its way: the button is shut against a second tap,
    /// which met the one-song-a-day rule and showed an error after success.
    @State private var isSending = false

    private var targetGroup: Group? {
        store.groups.first { $0.id == targetGroupID } ?? store.currentGroup
    }

    var body: some View {
        NavigationStack {
            // `Group` here must be SwiftUI's, not the app's own `Group` model
            // (TodApp/Core/Models/Group.swift) -- both are visible in this
            // module and the bare name resolves to the model type, which
            // does not conform to `View`.
            SwiftUI.Group {
                if let model {
                    content(model)
                } else {
                    ProgressView()
                }
            }
            // Once a song is chosen, its cover's colour from the top, as on
            // the song's own page; the app's ground until then.
            .background {
                if let selected = model?.selected {
                    CoverTint(artworkURL: selected.coverURL, fallbackHex: CoverColor.hex(forTrack: selected.id)) { tint in
                        LinearGradient(
                            colors: [tint.opacity(0.6), tint.opacity(0.2), Color.todBackground],
                            startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
                    }
                    .background(Color.todBackground)
                    .ignoresSafeArea()
                    .transition(.opacity)
                } else {
                    Color.todBackground.ignoresSafeArea()
                }
            }
            .animation(.easeInOut(duration: 0.4), value: model?.selected?.id)
            .navigationTitle("Song posten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                            .accessibilityLabel("Wird gepostet")
                    } else {
                        Button("Posten") {
                            guard let candidate = model?.selected else { return }
                            isSending = true
                            Task {
                                defer { isSending = false }
                                store.lastError = nil
                                await store.post(
                                    candidate: candidate,
                                    section: model?.section,
                                    // A hit from Apple's search knows its id;
                                    // otherwise whatever the player found while
                                    // the song was open here -- no second lookup.
                                    appleMusicID: candidate.appleMusicID ?? catalog.settled(for: CatalogKey.of(
                                        source: candidate.source,
                                        title: candidate.title,
                                        artist: candidate.artist))?.song?.id,
                                    to: targetGroup?.id)
                                // `AppStore.run` catches a repository failure into
                                // `lastError` rather than throwing back here, so a
                                // failed post must be checked explicitly -- dismissing
                                // unconditionally would look like a successful post
                                // that silently vanished.
                                if store.lastError == nil { dismiss() }
                            }
                        }
                        .disabled(model?.selected == nil)
                    }
                }
            }
        }
        .task {
            // Without a Spotify connection the search goes to Apple's catalog,
            // which needs no account: everyone can find a song.
            if model == nil {
                model = PostSongModel(
                    provider: store.provider,
                    fallbackSearch: { term in
                        try await ITunesCatalog().search(term: term).map(TrackCandidate.init(appleSong:))
                    },
                    // Not in the App Store build: see `SoundCloudSearchPolicy`.
                    soundCloudSearch: { term in
                        guard SoundCloudSearchPolicy.isAllowed(in: await AppDistribution.current()) else { return [] }
                        return try await SoundCloudSearchClient().search(term)
                    })
            }
        }
        // An error from somewhere else in the app is not this sheet's to show.
        .onAppear { store.lastError = nil }
    }

    /// One hit: cover, title and artist, in glass like the app's other cards,
    /// and the bookmark to note it for later. Two buttons side by side, not
    /// one inside the other: the row picks the song, the bookmark only notes it.
    private func resultRow(_ candidate: TrackCandidate, in model: PostSongModel) -> some View {
        HStack(spacing: 4) {
            pickButton(candidate, in: model)
            bookmarkButton(candidate)
        }
        .padding(.leading, 10)
        .padding(.vertical, 4)
        .padding(.trailing, 2)
        // Glass, like the app's other cards.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.todLine, lineWidth: 0.5))
    }

    private func pickButton(_ candidate: TrackCandidate, in model: PostSongModel) -> some View {
        Button { model.select(candidate) } label: {
            HStack(spacing: 10) {
                // The candidate has carried an artworkURL all
                // along; the list just never drew it.
                AsyncImage(url: candidate.coverURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.todSurface3)
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title)
                        .font(.todBody(14, weight: .bold))
                        .foregroundStyle(Color.todText)
                        // A two-line title ("… (Major Lazer
                        // Remix) [feat. …]") centred itself
                        // over a left-aligned artist.
                        .multilineTextAlignment(.leading)
                    Text(candidate.artist)
                        .font(.todBody(12))
                        .foregroundStyle(Color.todTextDim)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // One hit, one name -- cover, title and artist
        // otherwise arrive as three separate readings.
        .accessibilityLabel(Spoken.song(
            track: candidate.title, artist: candidate.artist))
    }

    /// Notes the song for later without posting it, or forgets it again --
    /// the same button in the hits and under "Gemerkt".
    private func bookmarkButton(_ candidate: TrackCandidate) -> some View {
        let isSaved = store.isSaved(candidate)
        return Button {
            withAnimation(.snappy) { store.toggleSaved(candidate) }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isSaved ? Color.todAccent : Color.todTextDim)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .sensoryFeedback(.selection, trigger: isSaved)
        .accessibilityLabel(isSaved ? "Aus „Gemerkt“ entfernen" : "Für später merken")
    }

    /// The songs noted for later, while the search field is empty: pick one
    /// to post it, or take it off the list with its bookmark.
    @ViewBuilder
    private func savedSection(in model: PostSongModel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "bookmark.fill")
                .accessibilityHidden(true)
            Text("Gemerkt")
        }
        .font(.todMono(12, weight: .semibold))
        .foregroundStyle(Color.todTextFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)

        if store.savedSongs.isEmpty {
            Text("Tipp bei einem Treffer auf das Lesezeichen, dann steht der Song hier, bis du ihn postest.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(store.savedSongs) { saved in
                resultRow(saved.candidate, in: model)
                    .transition(.opacity)
            }
        }
    }

    /// Where the song goes. With more than one group, a menu to change it.
    @ViewBuilder
    private var targetLine: some View {
        if let target = targetGroup {
            HStack(spacing: 6) {
                Text("Posten in:")
                    .foregroundStyle(Color.todTextDim)
                if store.groups.count > 1 {
                    Menu {
                        ForEach(store.groups) { group in
                            Button(group.name) { targetGroupID = group.id }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(target.name).fontWeight(.bold)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(Color.todAccent)
                    }
                    .accessibilityLabel("Posten in \(target.name), ändern")
                } else {
                    Text(target.name)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.todText)
                }
                Spacer(minLength: 0)
            }
            .font(.todBody(14))
        }
    }

    /// Search or paste a link: the app's own switch, the way the rating card
    /// draws its choice -- equal fields, the chosen one in the accent.
    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { option in
                let isChosen = mode == option
                Button {
                    withAnimation(.snappy) { mode = option }
                } label: {
                    Text(option.rawValue)
                        .font(.todBody(14, weight: .semibold))
                        .foregroundStyle(isChosen ? Color.todBackground : Color.todTextDim)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isChosen ? Color.todAccent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(PressScale())
                .accessibilityAddTraits(isChosen ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.todLine, lineWidth: 0.5))
    }

    @ViewBuilder
    private func content(_ model: PostSongModel) -> some View {
        VStack(spacing: 12) {
            targetLine
                .padding(.horizontal)

            modeSwitch
                .padding(.horizontal)

            switch mode {
            case .search:
                TextField("Song oder Artist", text: $queryText)
                    .textFieldStyle(.plain)
                    // Return ends editing, so the keyboard goes and the hits
                    // underneath come into view; the key says what it does.
                    .submitLabel(.search)
                    .padding(10)
                    .background(Color.todSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .task(id: queryText) {
                        await model.queryChanged(queryText)
                    }
                    .keepsKeyboardOnTap()

            case .link:
                TextField("Spotify- oder SoundCloud-Link", text: $linkFieldText)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.todSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .task(id: linkFieldText) {
                        await model.linkTextChanged(linkFieldText)
                    }
                    .keepsKeyboardOnTap()
            }

            if let message = model.errorMessage {
                Text(message)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            // A failed post lands in `store.lastError`, not in the model's own
            // `errorMessage` -- without reading it here the sheet would just
            // sit there unchanged after "Posten", with no clue anything went
            // wrong.
            if let lastError = store.lastError {
                Text(PostSongModel.message(for: lastError))
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            if model.isSearching { ProgressView().padding(.top, 4) }

            // Searched, and nothing came back: said, with the other way in.
            if mode == .search, model.foundNothing {
                VStack(spacing: 10) {
                    Text("Nichts gefunden. Versuch es mit Titel und Künstler, oder füg einen Link ein.")
                        .font(.todBody(14))
                        .foregroundStyle(Color.todTextDim)
                        .multilineTextAlignment(.center)
                    Button("Link einfügen") {
                        withAnimation(.snappy) { mode = .link }
                    }
                    .font(.todBody(14, weight: .semibold))
                    .foregroundStyle(Color.todAccent)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }

            if let selected = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // The way back to the hits, other than the search field.
                        Button {
                            withAnimation(.snappy) { model.clearSelection() }
                        } label: {
                            Label("Anderen Song wählen", systemImage: "chevron.backward")
                                .font(.todBody(13, weight: .semibold))
                                .foregroundStyle(Color.todAccent)
                        }
                        .padding(.horizontal)
                        // The section picker is the player's waveform here: one
                        // line for listening and picking, not two stacked.
                        TrackPlayerSheet(
                            candidateTitle: selected.title,
                            artist: selected.artist,
                            source: selected.source,
                            section: model.section,
                            durationSeconds: selected.durationSeconds,
                            appleMusicID: selected.appleMusicID,
                            isrc: selected.isrc,
                            sectionEditing: model.section.map { current in
                                Binding(
                                    get: { model.section ?? current },
                                    set: { model.section = $0 })
                            }
                        )
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        // Nothing searched yet: what was noted for later.
                        if mode == .search, queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            savedSection(in: model)
                        }
                        ForEach(model.results) { candidate in
                            resultRow(candidate, in: model)
                        }
                        // SoundCloud's hits for the same query, as their own
                        // section: they play through SoundCloud.
                        if !model.soundCloudResults.isEmpty {
                            HStack(spacing: 6) {
                                BrandIcon(brand: .soundCloud, size: 16)
                                    .accessibilityHidden(true)
                                Text("Auf SoundCloud")
                            }
                            .font(.todMono(12, weight: .semibold))
                            .foregroundStyle(Color.todTextFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            ForEach(model.soundCloudResults) { candidate in
                                resultRow(candidate, in: model)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            Spacer(minLength: 0)
        }
        // The whole sheet below the navigation bar: a tap on a hit, the mode
        // switch or empty space closes the keyboard, a tap on a field does not.
        .dismissesKeyboardOnTap()
    }
}
