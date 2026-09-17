import AuthenticationServices
import SwiftUI

/// The way into the app: an account, made with Sign in with Apple.
///
/// Spotify used to be this door, which meant no Spotify, no app. It is now a
/// connection in the profile -- for Spotify search and whole Spotify songs --
/// and nobody needs it to join a group.
struct SignInView: View {
    @Environment(AppStore.self) private var store
    /// The nonce of the attempt in progress. Its hash goes to Apple, the
    /// nonce itself to the server, which checks the two belong together.
    @State private var nonce = ""
    @State private var isSigningIn = false

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

            SignInWithAppleButton(.continue) { request in
                nonce = AppleSignIn.makeNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AppleSignIn.hashed(nonce)
            } onCompletion: { result in
                handle(result)
            }
            // White on the dark ground, as Apple's guidelines ask.
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(Capsule())
            .disabled(isSigningIn)
            .overlay {
                if isSigningIn { ProgressView().tint(Color.todBackground) }
            }

            // Said before signing in, so nobody wonders where Spotify went.
            Text("Spotify verbindest du danach im Profil, wenn du willst. Ohne Spotify hörst du die 30-Sekunden-Vorschau.")
                .font(.todBody(12))
                .foregroundStyle(Color.todTextFaint)
                .multilineTextAlignment(.center)

            if let error = store.lastError {
                Text(PostSongModel.message(for: error))
                    .font(.todBody(12))
                    .foregroundStyle(Color.todAccent2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.todBackground)
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8)
            else {
                store.lastError = .accountSignInFailed
                return
            }
            let name = AppleSignIn.displayName(from: credential.fullName)
            isSigningIn = true
            Task {
                await store.signInWithApple(idToken: idToken, nonce: nonce, name: name)
                isSigningIn = false
            }
        case .failure(let error):
            // Closing Apple's sheet is a decision, not an error.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            store.lastError = .accountSignInFailed
        }
    }
}
