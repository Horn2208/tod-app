import PhotosUI
import SwiftUI

/// Who you are in this app, the music services you connected, and the door
/// out of your account.
///
/// The sign-out used to sit in a "Mehr" tab of its own -- a whole reiter for a
/// single button, kept only because nothing else offered a way out. It belongs
/// with the account it ends.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(AppleMusicAccess.self) private var appleMusic
    @Environment(\.openURL) private var openURL

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isConfirmingSpotifyDisconnect = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                picture
                nameField
                premium
                spotifyCard
                appleMusicCard
                reminders
                signOutButton
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
        .task { await store.refreshReminderAuthorization() }
        .task(id: pickedPhoto) {
            guard let pickedPhoto,
                  let data = try? await pickedPhoto.loadTransferable(type: Data.self)
            else { return }
            await store.updateProfile(name: name, imageData: data)
        }
        // Saved once typing pauses, not on every keystroke: each save is a
        // request now. The store drops a blank or unchanged name, so clearing
        // the field to retype keeps the old name until there is a new one.
        .task(id: name) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await store.updateProfile(name: name, imageData: nil)
        }
        // Closing within the pause must not lose the last word.
        .onDisappear {
            let name = name
            Task { await store.updateProfile(name: name, imageData: nil) }
        }
        .confirmationDialog(
            "Spotify trennen?",
            isPresented: $isConfirmingSpotifyDisconnect,
            titleVisibility: .visible
        ) {
            Button("Trennen", role: .destructive) {
                Task { await store.disconnectSpotify() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Eine laufende Wiedergabe wird gestoppt und die Spotify-Sitzung gelöscht. Deine Gruppen bleiben.")
        }
        .confirmationDialog(
            "Abmelden?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Abmelden", role: .destructive) {
                dismiss()
                Task { await store.signOut() }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if store.account?.isAnonymous == true {
                // Nothing to sign back in with: this is goodbye to the account.
                Text("Du bist ohne Anmeldung unterwegs. Nach dem Abmelden kommst du nicht mehr in dieses Konto, deine Gruppen und Songs darin sind für dich dann weg.")
            } else {
                Text("Du meldest dich auf diesem iPhone ab, Spotify wird dabei getrennt. Deine Gruppen und Songs bleiben erhalten.")
            }
        }
    }

    // MARK: - Picture

    private var picture: some View {
        // Worked out here: the picker's label runs in a Sendable closure,
        // which may not reach into the store.
        let label = store.profile.imageData == nil ? "Bild wählen" : "Bild ändern"
        return VStack(spacing: 10) {
            ProfileAvatar(profile: store.profile, size: 104)
                // Your own initials or picture, with the name field and the
                // button that changes it directly underneath.
                .accessibilityHidden(true)

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

    // MARK: - Spotify

    /// The one Spotify sign-in. It used to be two -- search and posting through
    /// the system browser, whole songs through a second login inside the app --
    /// because the system browser shares no cookies with the app's web views.
    /// The sign-in runs in the app's own web view now, so one login gives search
    /// its token and the player its session.
    private var spotifyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spotify")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text(store.isSpotifyConnected ? "Verbunden" : "Nicht verbunden")
                    .font(.todBody(13.5, weight: .bold))
                    .foregroundStyle(store.isSpotifyConnected ? Color.todGood : Color.todTextFaint)
            }
            // "Spotify, Nicht verbunden" in one go.
            .accessibilityElement(children: .combine)

            // Explains up front why the section picker behaves the way it does
            // for this account, instead of the reason surfacing later as a
            // dead-end tap -- same idea as the Premium note on SignInView.
            Text(accountDescription)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)

            if store.isSpotifyConnected {
                Button("Spotify trennen") { isConfirmingSpotifyDisconnect = true }
                    .buttonStyle(TodPrimaryButtonStyle())
                    .padding(.top, 6)
            } else {
                Button("Spotify verbinden") {
                    Task { await store.connectSpotify() }
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

    // MARK: - Apple Music

    /// Whole songs from the picked section, for anyone with a subscription.
    /// Connected here rather than asked for at launch: the system prompt comes
    /// once, so it should come when someone has asked for what it guards.
    private var appleMusicCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Apple Music")
                    .font(.todBody(15, weight: .bold))
                    .foregroundStyle(Color.todText)
                Spacer()
                Text(appleMusicStatus)
                    .font(.todBody(13.5, weight: .bold))
                    .foregroundStyle(appleMusic.playsWholeSongs ? Color.todGood : Color.todTextFaint)
            }
            .accessibilityElement(children: .combine)

            Text(appleMusicDescription)
                .font(.todBody(13))
                .foregroundStyle(Color.todTextDim)

            switch appleMusic.standing {
            case .notAsked:
                Button("Mit Apple Music verbinden") {
                    Task { await appleMusic.connect() }
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 6)
            case .denied:
                // iOS asks only once; after a "no" the switch lives in Settings.
                Button("iOS-Einstellungen öffnen") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(TodPrimaryButtonStyle())
                .padding(.top, 6)
            case .previewsOnly, .wholeSongs:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.todSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Someone may have subscribed, or flipped the switch in Settings,
        // since the profile was last open.
        .task { await appleMusic.refresh() }
    }

    private var appleMusicStatus: String {
        switch appleMusic.standing {
        case .notAsked: "Nicht verbunden"
        case .denied: "Ausgeschaltet"
        case .previewsOnly: "Ohne Abo"
        case .wholeSongs: "Ganze Songs"
        }
    }

    private var appleMusicDescription: String {
        switch appleMusic.standing {
        case .notAsked:
            "Mit einem Apple-Music-Abo hörst du ganze Songs, ab dem Abschnitt, den die postende Person gewählt hat. Ohne Abo bleibt es bei der 30-Sekunden-Vorschau."
        case .denied:
            "Apple Music ist für TodApp in den iOS-Einstellungen ausgeschaltet. Bis dahin spielt der Player die Vorschau."
        case .previewsOnly:
            "Verbunden, aber ohne Abo, das ganze Songs abspielt. Der Player bleibt bei der 30-Sekunden-Vorschau."
        case .wholeSongs:
            "Songs laufen ganz, ab dem Abschnitt, den die postende Person gewählt hat."
        }
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
            .accessibilityElement(children: .combine)

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

    // MARK: - Sign-out

    /// Quiet and last: leaving is rare, and nothing above should read as a
    /// step towards it.
    private var signOutButton: some View {
        VStack(spacing: 4) {
            Button("Abmelden") { isConfirmingSignOut = true }
                .font(.todBody(15, weight: .bold))
                .foregroundStyle(Color.todTextDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            if store.account?.isAnonymous == true {
                Text("Ohne Anmeldung: Dein Konto gibt es nur auf diesem iPhone.")
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var accountDescription: String {
        guard store.isSpotifyConnected else {
            return "Ohne Spotify hörst du die 30-Sekunden-Vorschau. Verbunden suchst und postest du Songs über Spotify, und mit Spotify Premium kann der Player ganze Songs abspielen, wenn Spotify sie freigibt."
        }
        // Says what the login is for, not what it guarantees: whether a whole
        // song comes is Spotify's decision, and the player says per song when
        // it only got the excerpt.
        return "Über Spotify laufen Suchen, Posten von Spotify-Songs und der Spotify-Player. Ob ein ganzer Song kommt, zeigt der Player bei jedem Song selbst an."
    }
}
