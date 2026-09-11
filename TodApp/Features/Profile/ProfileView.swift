import PhotosUI
import SwiftUI

/// Who you are in this app, and the one door out of a Spotify session.
///
/// The sign-out used to sit in a "Mehr" tab of its own -- a whole reiter for a
/// single button, kept only because nothing else offered a way out. It belongs
/// next to the account it ends.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotifyEmbedPlayer.self) private var embed
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isConfirmingSignOut = false
    @State private var isShowingWebLogin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                picture
                nameField
                premium
                account
                webPlayer
                reminders
            }
            .padding()
        }
        .dismissesKeyboardOnTap()
        .background(Color.todBackground)
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") { dismiss() }
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
        }
        // Seeded once rather than bound straight to the store: a field bound to
        // a value the store rejects (a blank name) would snap back under the
        // cursor mid-word.
        .onAppear { name = store.profile.name }
        .task { await embed.refreshWebSession() }
        .task { await store.refreshReminderAuthorization() }
        .sheet(isPresented: $isShowingWebLogin, onDismiss: {
            // Whatever happened on Spotify's page, the embed loaded under the
            // old state: look again, and rebuild it so the next play uses the
            // session as it is now.
            Task {
                await embed.refreshWebSession()
                embed.reloadForNewSession()
            }
        }) {
            NavigationStack { SpotifyWebLoginView() }
        }
        .task(id: pickedPhoto) {
            guard let pickedPhoto,
                  let data = try? await pickedPhoto.loadTransferable(type: Data.self)
            else { return }
            store.updateProfile(name: name, imageData: data)
        }
        .confirmationDialog(
            "Bei Spotify abmelden?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Abmelden", role: .destructive) {
                Task { await store.signOut() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Eine laufende Wiedergabe wird gestoppt und deine Sitzung gelöscht. Du musst dich danach neu anmelden.")
        }
    }

    // MARK: - Picture

    private var picture: some View {
        // Worked out here: the picker's label runs in a Sendable closure,
        // which may not reach into the store.
        let label = store.profile.imageData == nil ? "Bild wählen" : "Bild ändern"
        return VStack(spacing: 10) {
            ProfileAvatar(profile: store.profile, size: 104)

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text(label)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todAccent)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.todMono(11, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            TextField("Dein Name", text: $name)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .textInputAutocapitalization(.words)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.todLine, lineWidth: 0.5)
                )
                // Written on every keystroke, and the store drops a blank one --
                // so clearing the field to retype keeps the old name until there
                // is a new one, instead of leaving you nameless.
                .onChange(of: name) { _, new in
                    store.updateProfile(name: new, imageData: nil)
                }
                .keepsKeyboardOnTap()
        }
    }

    // MARK: - Premium

    private var premium: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { store.profile.isPremium },
                set: { store.setPremium($0) }
            )) {
                Text("Tod Premium")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
            }
            .tint(Color.todAccent2)

            // Said plainly rather than dressed up as a shop: there is nothing
            // to buy yet, and a switch that pretends otherwise would be a lie
            // about what this build does.
            Text("Schaltet Battle frei. Noch ein Schalter statt eines Kaufs — später hängt genau dieser Zustand an einem echten.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Account

    private var account: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spotify · Suchen und Posten")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text(store.isSignedIn ? "Angemeldet" : "Nicht verbunden")
                    .font(.todBody(13.5, weight: .bold))
                    .foregroundStyle(store.isSignedIn ? Color.todGood : Color.todTextFaint)
            }

            // Explains up front why the section picker behaves the way it does
            // for this account, instead of the reason surfacing later as a
            // dead-end tap -- same idea as the Premium note on SignInView.
            Text(accountDescription)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)

            if store.isSignedIn {
                Button("Abmelden") { isConfirmingSignOut = true }
                    .buttonStyle(TodPrimaryButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Whole songs in the player

    /// The second Spotify login, and why it is a separate one: search and
    /// posting sign in through the system browser, which shares no cookies
    /// with this app's web views. Whole songs need a session *in* the web
    /// view the player runs in -- this card is where it is made and ended.
    private var webPlayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spotify · Ganze Songs im Player")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text(embed.hasWebSession ? "Angemeldet" : "Nicht angemeldet")
                    .font(.todBody(13.5, weight: .bold))
                    .foregroundStyle(embed.hasWebSession ? Color.todGood : Color.todTextFaint)
            }

            // Says what the login is for, not what it guarantees: whether the
            // whole song then plays is Spotify's decision, and the player
            // tells per song when it only got the excerpt.
            Text(embed.hasWebSession
                 ? "Der Player ist bei Spotify angemeldet. Ob ein ganzer Song kommt, zeigt der Player bei jedem Song selbst an."
                 : "Ohne Anmeldung spielt der Player Spotifys 30-Sekunden-Vorschau. Für ganze Songs ab dem gewählten Abschnitt: hier mit Spotify Premium anmelden.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)

            if embed.hasWebSession {
                Button("Im Player abmelden") {
                    Task { await embed.signOutOfWebSession() }
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 6)
            } else {
                Button("Im Player bei Spotify anmelden") { isShowingWebLogin = true }
                    .buttonStyle(TodPrimaryButtonStyle())
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Reminders

    /// The two daily nudges. Switched on here rather than asked for at
    /// launch: the system prompt comes exactly once, so it should come when
    /// someone has asked for what it guards.
    private var reminders: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Erinnerungen")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text(store.reminderAuthorization == .allowed ? "An" : "Aus")
                    .font(.todBody(13.5, weight: .bold))
                    .foregroundStyle(
                        store.reminderAuthorization == .allowed ? Color.todGood : Color.todTextFaint)
            }

            Text("Um 15 Uhr, wenn du heute noch keinen Song gepostet hast, und um 20 Uhr zum Voten.")
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)

            switch store.reminderAuthorization {
            case .notDetermined:
                Button("Erinnerungen einschalten") {
                    Task { await store.enableReminders() }
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 6)
            case .allowed, .denied:
                // Once answered, iOS keeps the switch: asking again shows no
                // prompt, so the only honest button leads to where it is.
                Text(store.reminderAuthorization == .allowed
                     ? "Ausschalten kannst du sie in den iOS-Einstellungen."
                     : "Mitteilungen für TodApp sind in den iOS-Einstellungen ausgeschaltet.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var accountDescription: String {
        guard store.isSignedIn else {
            // Only what has been seen to work. Playing the 30-second excerpt
            // does without an account; posting by link probably does too --
            // Spotify's oEmbed answers without one -- but no post has gone all
            // the way through the app that way yet, so the text does not
            // promise it.
            return "Ohne Verbindung kannst du dich umsehen und hörst den 30-Sekunden-Ausschnitt. Zum Suchen brauchst du eine Spotify-Anmeldung."
        }
        // Playback no longer depends on this sign-in: Premium used to play
        // through it over Spotify Connect, and plays in the embed now, under
        // the web session below.
        return "Über diese Anmeldung laufen Suchen und Posten. Was der Player abspielt, hängt an der Anmeldung darunter."
    }
}
