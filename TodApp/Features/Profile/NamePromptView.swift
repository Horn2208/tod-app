import SwiftUI

/// Asked once, on the first sign-in: the server names a new account "Neu"
/// when it has nothing better, and the friends should not see that.
struct NamePromptView: View {
    @Environment(AppStore.self) private var store
    @State private var name = ""

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Wie sollen dich deine Freunde nennen?")
                .font(.todBody(22, weight: .bold))
                .foregroundStyle(Color.todText)
                .multilineTextAlignment(.center)
            TextField("Dein Name", text: $name)
                .font(.todBody(16))
                .foregroundStyle(Color.todText)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.todLine, lineWidth: 0.5))
                .onChange(of: name) { _, new in
                    if new.count > UserProfile.maxNameLength {
                        name = String(new.prefix(UserProfile.maxNameLength))
                    }
                }
                .onSubmit(save)
            Button("Weiter", action: save)
                .font(.todBody(16, weight: .bold))
                .foregroundStyle(Color.todText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.todAccent, in: RoundedRectangle(cornerRadius: 12))
                .opacity(UserProfile.needsName(name) ? 0.4 : 1)
                .disabled(UserProfile.needsName(name))
            Spacer()
            Spacer()
        }
        .padding(24)
        .background(Color.todBackground.ignoresSafeArea())
    }

    private func save() {
        guard !UserProfile.needsName(name) else { return }
        let chosen = trimmed
        Task { await store.updateProfile(name: chosen, imageData: nil) }
    }
}
