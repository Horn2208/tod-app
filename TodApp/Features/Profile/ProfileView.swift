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

    @State private var name = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isConfirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                picture
                nameField
                premium
                account
            }
            .padding()
        }
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
        VStack(spacing: 10) {
            ProfileAvatar(profile: store.profile, size: 104)

            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                Text(store.profile.imageData == nil ? "Bild wählen" : "Bild ändern")
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
                Text("Spotify")
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

    private var accountDescription: String {
        guard store.isSignedIn else {
            return "Ohne Verbindung kannst du dich umsehen, aber nicht suchen, posten oder abspielen."
        }
        return store.capabilities.canStartAtPosition
            ? "Premium-Account — die App spielt gewählte Abschnitte genau dort ab, auch die von Leuten ohne Premium."
            : "Kein Premium-Account — suchen, posten und einen Abschnitt wählen geht. Abspielen kann ihn, wer Premium hat; du hörst hier den 30-Sekunden-Ausschnitt."
    }
}
