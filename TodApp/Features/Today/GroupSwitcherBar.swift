import SwiftUI

/// Which group Home is showing, as the groups' own pictures rather than text
/// pills. The chosen one is full size and wears the story ring; the others sit
/// smaller and dimmed. The song and the streak on Home follow the selected
/// group, so choosing one here changes both.
struct GroupSwitcherBar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(store.groups) { group in
                        let isSelected = group.id == store.currentGroupID
                        Button { store.selectGroup(group.id) } label: {
                            GroupAvatar(group: group, size: isSelected ? 52 : 42)
                                .padding(isSelected ? 4 : 0)
                                .overlay {
                                    if isSelected {
                                        Circle().strokeBorder(
                                            AngularGradient(
                                                colors: [.todAccent, .todAccent2, .todAccent],
                                                center: .center),
                                            lineWidth: 2.5)
                                    }
                                }
                                .opacity(isSelected ? 1 : 0.55)
                                .frame(height: 60)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(group.name)
                        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 16)
                .animation(.snappy, value: store.currentGroupID)
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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.todLine, lineWidth: 0.5))
    }
}
