import SwiftUI

/// The app's whole bottom chrome, replacing the system tab bar: Home on the
/// left, Gruppen on the right, and the mini player as a wider glass pill
/// between them -- all three on one row, at the same height.
///
/// Before this, Home and Gruppen sat together in the system tab bar and the
/// mini player floated as its own card above it. The redesign brief (17.
/// September) asked for one row instead, with the pill as the visually
/// biggest, most important piece in the middle.
struct RootNavBar: View {
    @Environment(NowPlaying.self) private var nowPlaying
    let selectedPage: RootTabView.Page
    let onSelectPage: (RootTabView.Page) -> Void
    /// Passed straight through to the mini player -- see `MiniPlayerBar`.
    let post: Submission?
    let onOpenPlayer: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            navButton(systemImage: "house.fill", label: "Home", isSelected: selectedPage == .home) {
                onSelectPage(.home)
            }

            // No content when nothing plays (`MiniPlayerBar` renders empty
            // then) -- `maxWidth: .infinity` still claims the space between
            // the two buttons, so they stay put at the edges either way.
            // Nothing playing: no room between them, and the two buttons sit
            // together in the middle. When a song starts they move apart and
            // the pill opens between them. The mini player stays in the row
            // either way -- it is what notices that something plays.
            MiniPlayerBar(post: post, onOpen: onOpenPlayer)
                .frame(maxWidth: nowPlaying.isCardShown ? .infinity : 0)
                .frame(height: RootNavBar.itemHeight)

            navButton(systemImage: "person.2.fill", label: "Gruppen", isSelected: selectedPage == .gruppen) {
                onSelectPage(.gruppen)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: nowPlaying.isCardShown)
    }

    /// The height of all three: the two round buttons and the pill between.
    static let itemHeight: CGFloat = 56
    /// The room screens keep clear at their bottom: the row, the 8 points
    /// under it, and 8 of air above.
    static let height: CGFloat = itemHeight + 16

    private func navButton(
        systemImage: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSelected ? Color.todAccent : Color.todText)
                .frame(width: RootNavBar.itemHeight, height: RootNavBar.itemHeight)
                // Glass either way, like the pill between them; the chosen
                // page is said by the accent on the symbol and the rim.
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.todAccent : Color.todLine,
                        lineWidth: isSelected ? 1.5 : 0.5))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
