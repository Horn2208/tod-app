import SwiftUI

/// Which group Home is showing, as the groups' own pictures rather than text
/// pills. The chosen one sits in the middle, right above its name, full size
/// and wearing the story ring; the others flank it, smaller and dimmed. A tap
/// on one, or a swipe that lands on one, brings it to the middle and chooses
/// it. The song and the streak on Home follow the selected group, so choosing
/// one here changes both.
struct GroupSwitcherBar: View {
    @Environment(AppStore.self) private var store
    /// The group in the middle of the row.
    @State private var centred: String?

    /// Every circle takes the same room, chosen or not, so whichever is in the
    /// middle is exactly in the middle. The difference is drawn, not laid out.
    private static let slot: CGFloat = 60
    private static let avatar: CGFloat = 52
    private static let smaller: CGFloat = 42

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(store.groups) { group in
                            circle(group)
                        }
                    }
                    .scrollTargetLayout()
                    .animation(.snappy, value: store.currentGroupID)
                }
                // Room on both sides, so the first and the last can reach the middle.
                .contentMargins(.horizontal, max(0, (geo.size.width - Self.slot) / 2), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centred)
            }
            .frame(height: Self.slot)
            // A swipe here moves the row, not the page.
            .claimsSidewaysSwipes()
            // The row runs out under the card's edge instead of ending in a cut.
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing)
            }

            if let current = store.currentGroup {
                Text(current.name)
                    .font(.todBody(13, weight: .bold))
                    .foregroundStyle(Color.todTextDim)
                    // The selected circle already says it.
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .todGlassCard(radius: 20)
        .onAppear { centred = store.currentGroupID }
        .onChange(of: store.currentGroupID) { _, id in
            withAnimation(.snappy) { centred = id }
        }
        // A swipe that comes to rest on another group chooses it.
        .onChange(of: centred) { _, id in
            if let id, id != store.currentGroupID { store.selectGroup(id) }
        }
    }

    private func circle(_ group: Group) -> some View {
        let isSelected = group.id == store.currentGroupID
        return Button { store.selectGroup(group.id) } label: {
            GroupAvatar(group: group, size: Self.avatar)
                // Scaled rather than resized: an emoji's font size does not
                // animate, it jumps.
                .scaleEffect(isSelected ? 1 : Self.smaller / Self.avatar)
                .opacity(isSelected ? 1 : 0.55)
                .frame(width: Self.slot, height: Self.slot)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(
                            AngularGradient(
                                colors: [.todAccent, .todAccent2, .todAccent],
                                center: .center),
                            lineWidth: 2.5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .id(group.id)
        .accessibilityLabel(group.name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
