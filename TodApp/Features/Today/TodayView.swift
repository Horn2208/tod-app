import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var isPosting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let group = store.currentGroup {
                    Text(group.name)
                        .font(.todDisplay(22))
                        .foregroundStyle(Color.todText)

                    HStack(spacing: 10) {
                        ForEach(group.members) { member in
                            AvatarBadge(member: member)
                        }
                    }

                    if let me = group.members.first(where: { $0.isCurrentUser }), !me.hasPostedToday {
                        Text("Du hast heute noch nicht gepostet.")
                            .font(.todBody(13))
                            .foregroundStyle(Color.todTextDim)
                        Button("+ Song posten") { isPosting = true }
                            .buttonStyle(TodPrimaryButtonStyle())
                    } else {
                        Text("✓ Gepostet")
                            .font(.todBody(13.5, weight: .bold))
                            .foregroundStyle(Color.todGood)
                    }
                } else {
                    ProgressView()
                }
            }
            // Without this the VStack only claims its intrinsic width, and the
            // layout silently depends on TodPrimaryButtonStyle's maxWidth to
            // stretch it -- which disappears once the user has already posted.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Heute")
        .sheet(isPresented: $isPosting) { PostSongView() }
    }
}

struct TodPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration)
    }

    /// A nested view, because `isEnabled` reaches a button style only through a
    /// real view's environment -- reading it on the style itself never sees it,
    /// which is how a disabled button ended up looking pressable.
    private struct StyledLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.todBody(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(background)
                .foregroundStyle(isEnabled ? Color.todBackground : Color.todTextFaint)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private var background: Color {
            guard isEnabled else { return .todSurface2 }
            return Color.todAccent.opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}
