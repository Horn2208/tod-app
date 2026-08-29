import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store

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
                        Button("+ Song posten") {}
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
            .padding()
        }
        .background(Color.todBackground)
        .navigationTitle("Heute")
    }
}

private struct AvatarBadge: View {
    let member: Member

    var body: some View {
        Circle()
            .fill(member.hasPostedToday ? Color.todGood.opacity(0.25) : Color.todSurface2)
            .overlay(
                Text(member.isCurrentUser ? "DU" : member.name)
                    .font(.todMono(12, weight: .semibold))
                    .foregroundStyle(Color.todText)
            )
            .overlay(Circle().stroke(member.isCurrentUser ? Color.todAccent : .clear, lineWidth: 2))
            .frame(width: 40, height: 40)
    }
}

struct TodPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.todBody(15, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.todAccent.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(Color.todBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
