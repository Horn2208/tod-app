import SwiftUI

struct SignInView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 6) {
                Text("TodApp")
                    .font(.todDisplay(34))
                    .foregroundStyle(Color.todText)
                // The name spelled out, kept in the wordmark's register --
                // small and tracked -- so the sentence below still reads as the
                // pitch rather than as a second tagline competing with it.
                Text("Track of the day")
                    .font(.todBody(12, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(Color.todTextDim)
            }

            Text("Täglich ein Song mit deiner Gruppe.")
                .font(.todBody(15))
                .foregroundStyle(Color.todTextDim)

            Spacer()

            VStack(spacing: 10) {
                Button("Mit Spotify anmelden") {
                    Task { await store.signIn() }
                }
                .buttonStyle(TodPrimaryButtonStyle())

                SoonButton(title: "Mit Apple Music anmelden")
                SoonButton(title: "Ohne Musikdienst weiter")
            }

            // Said before signing in rather than discovered afterwards at a
            // button that answers 403.
            Text("Zum Abspielen ganzer Songs und gewählter Abschnitte wird Spotify Premium benötigt. Ohne Premium kannst du suchen, posten und voten.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextFaint)
                .multilineTextAlignment(.center)

            if let error = store.lastError {
                Text(PostSongModel.message(for: error))
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.todBackground)
    }
}

/// A door that is planned but not built yet. Disabled rather than absent: the
/// screen's job is to show which ways in are coming, and a button that accepts
/// a tap and then does nothing teaches people the app is broken.
///
/// Named for the service where one exists, and "Musikdienst" where none does --
/// the way in without a provider must not be called "ohne Spotify", or it needs
/// renaming the day Apple Music arrives.
private struct SoonButton: View {
    let title: String

    var body: some View {
        Button {
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Text("bald")
                    .font(.todMono(10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.todSurface3, in: Capsule())
            }
        }
        .buttonStyle(TodPrimaryButtonStyle())
        .disabled(true)
        .accessibilityLabel("\(title), bald verfügbar")
    }
}
