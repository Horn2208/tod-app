import SwiftUI

struct SignInView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("TodApp")
                .font(.todDisplay(34))
                .foregroundStyle(Color.todText)
            Text("Täglich ein Song mit deiner Gruppe.")
                .font(.todBody(15))
                .foregroundStyle(Color.todTextDim)

            Spacer()

            Button("Mit Spotify anmelden") {
                Task { await store.signIn() }
            }
            .buttonStyle(TodPrimaryButtonStyle())

            // Said before signing in rather than discovered afterwards at a
            // button that answers 403.
            Text("Zum Abspielen ganzer Songs und gewählter Abschnitte braucht es Spotify Premium. Ohne Premium kannst du suchen, posten und voten.")
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
