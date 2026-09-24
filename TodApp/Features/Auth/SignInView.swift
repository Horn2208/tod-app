import AuthenticationServices
import SwiftUI

/// The way into the app: an account, three ways to make one. Apple; Spotify,
/// which also connects the player; or none, which makes an account on this
/// phone alone. Each ends in an account because the server gives nothing to
/// nobody -- they differ in what it can be found again with.
struct SignInView: View {
    @Environment(AppStore.self) private var store
    /// The nonce of the attempt in progress. Its hash goes to Apple, the
    /// nonce itself to the server, which checks the two belong together.
    @State private var nonce = ""
    /// The way in being tried, so its button shows the wait and the others
    /// hold still.
    @State private var signingIn: Way?

    private enum Way { case apple, spotify, withoutAccount }

    /// Spotify's own green, with black text as their guidelines put it.
    private static let spotifyGreen = Color(hex: "#1ED760")

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

            VStack(spacing: 12) {
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
                .overlay {
                    if signingIn == .apple { ProgressView().tint(Color.todBackground) }
                }

                // Spotify's own icon beside the words. On its green only the
                // one-colour icon may stand (Spotify's design guidelines),
                // black like the type; 22 pt, above the 21 px minimum.
                Button { start(.spotify) } label: {
                    HStack(spacing: 11) {
                        Image("SpotifyIconBlack")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text("Mit Spotify fortfahren")
                    }
                }
                    .buttonStyle(StartPill(fill: Self.spotifyGreen, text: .black, isWaiting: signingIn == .spotify))

                Button("Ohne Anmeldung weiter") { start(.withoutAccount) }
                    .buttonStyle(StartPill(fill: .todAccent, text: .todBackground, isWaiting: signingIn == .withoutAccount))
            }
            .disabled(signingIn != nil)

            // Said before choosing, because it cannot be undone afterwards.
            Text("Ohne Anmeldung gibt es dein Konto nur auf diesem iPhone. Spotify verbindest du auch später im Profil.")
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
            signingIn = .apple
            Task {
                await store.signInWithApple(idToken: idToken, nonce: nonce, name: name)
                signingIn = nil
            }
        case .failure(let error):
            // Closing Apple's sheet is a decision, not an error.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            store.lastError = .accountSignInFailed
        }
    }

    private func start(_ way: Way) {
        store.lastError = nil
        signingIn = way
        Task {
            switch way {
            case .spotify: await store.signInWithSpotify()
            case .withoutAccount: await store.continueWithoutAccount()
            case .apple: break
            }
            signingIn = nil
        }
    }
}

/// The start screen's buttons: pills the height of Apple's, so the three ways
/// in read as one choice.
private struct StartPill: ButtonStyle {
    let fill: Color
    let text: Color
    let isWaiting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.todBody(19, weight: .semibold))
            .foregroundStyle(text)
            .opacity(isWaiting ? 0 : 1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(fill.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(Capsule())
            .overlay {
                if isWaiting { ProgressView().tint(text) }
            }
    }
}
