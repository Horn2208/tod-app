import SwiftUI

/// The one place in the app to leave a Spotify session. There is no settings
/// screen behind this and no account switcher -- just the account's status
/// and the door out, which is the one thing the sign-in flow was missing.
struct MoreView: View {
    @Environment(AppStore.self) private var store
    @State private var isConfirmingSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Spotify")
                        .font(.todBody(15, weight: .bold))
                        .foregroundStyle(Color.todText)
                    Spacer()
                    Text("✓ Angemeldet")
                        .font(.todBody(13.5, weight: .bold))
                        .foregroundStyle(Color.todGood)
                }

                // Explains up front why the section picker behaves differently
                // for this account, instead of the reason surfacing later as a
                // dead-end tap -- same idea as the Premium note on SignInView.
                Text(capabilityDescription)
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextDim)

                Button("Abmelden") { isConfirmingSignOut = true }
                    .buttonStyle(TodPrimaryButtonStyle())
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.todSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Mehr")
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

    private var capabilityDescription: String {
        store.capabilities.canStartAtPosition
            ? "Premium-Account — du kannst einen Abschnitt wählen, die App spielt ihn genau dort."
            : "Kein Premium-Account — du kannst suchen und posten, aber die App kann die Wiedergabe nicht steuern und keinen Abschnitt vorgeben."
    }
}
