import SwiftUI

struct PostSongView: View {
    enum Mode: String, CaseIterable { case search = "Suchen", link = "Link einfügen" }

    @Environment(AppStore.self) private var store
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
            .background(Color.todBackground)
            .navigationTitle("Song posten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Posten") {
                        guard let candidate = model?.selected else { return }
                        Task {
                            store.lastError = nil
                            await store.post(candidate: candidate, section: model?.section)
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
        .task {
            if model == nil { model = PostSongModel(provider: store.provider) }
        }
    }

    @ViewBuilder
    private func content(_ model: PostSongModel) -> some View {
        VStack(spacing: 12) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch mode {
            case .search:
                TextField("Song oder Artist", text: $queryText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.todSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .task(id: queryText) {
                        await model.queryChanged(queryText)
                    }

            case .link:
                TextField("Spotify- oder SoundCloud-Link", text: $linkFieldText)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(10)
                    .background(Color.todSurface2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .task(id: linkFieldText) {
                        await model.linkTextChanged(linkFieldText)
                    }
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

            if let selected = model.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TrackPlayerSheet(
                            candidateTitle: selected.title,
                            artist: selected.artist,
                            source: selected.source,
                            section: model.section
                        )

                        if model.section != nil {
                            TrackSectionPicker(
                                candidate: selected,
                                section: Binding(
                                    get: { model.section ?? TrackSection.initial(in: 1) },
                                    set: { model.section = $0 }
                                )
                            )
                            .padding(.horizontal)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.results) { candidate in
                            Button { model.select(candidate) } label: {
                                HStack(spacing: 10) {
                                    // The candidate has carried an artworkURL all
                                    // along; the list just never drew it.
                                    AsyncImage(url: candidate.source.artworkURL) { image in
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
                                        Text(candidate.artist)
                                            .font(.todBody(12))
                                            .foregroundStyle(Color.todTextDim)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.todSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
            Spacer(minLength: 0)
        }
    }
}
