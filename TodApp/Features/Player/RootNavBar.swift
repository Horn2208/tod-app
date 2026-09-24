import SwiftUI

/// Where a finger on the bottom bar takes you.
enum RootNavSwipe {
    /// A swipe shorter than this is a nudge, not a wish to move.
    static let threshold: Double = 40

    /// Together, the bar is two halves; the one under the finger is the page.
    static func page(atX x: Double, barWidth: Double) -> RootTabView.Page {
        x < barWidth / 2 ? .home : .gruppen
    }

    /// Apart, a swipe moves one page along: left to Gruppen, right to Home.
    static func page(afterSwipe dx: Double, from page: RootTabView.Page) -> RootTabView.Page {
        if dx <= -threshold { return .gruppen }
        if dx >= threshold { return .home }
        return page
    }
}

/// The app's whole bottom chrome, replacing the system tab bar, in glass.
///
/// Nothing playing, it is what the system bar was: one glass capsule with
/// Home and Gruppen, and a finger can slide along it -- the highlight
/// follows, and letting go chooses. While a song plays the two move apart
/// into round glass buttons at the edges and the mini player opens between
/// them, all three one height (the redesign brief, 17. September); a swipe
/// along the row still moves between the pages.
///
/// The mini player stays in the row either way, only zero wide while nothing
/// plays: it is what notices that something does (`NowPlaying.isCardShown`).
struct RootNavBar: View {
    @Environment(NowPlaying.self) private var nowPlaying
    let selectedPage: RootTabView.Page
    let onSelectPage: (RootTabView.Page) -> Void
    /// Passed straight through to the mini player -- see `MiniPlayerBar`.
    let post: Submission?
    let onOpenPlayer: (() -> Void)?

    /// The page under the finger while it slides along the capsule.
    @State private var hovered: RootTabView.Page?

    /// The height of all three: the two buttons and the pill between.
    static let itemHeight: CGFloat = 56
    /// The room screens keep clear at their bottom: the row, the 8 points
    /// under it, and 8 of air above.
    static let height: CGFloat = itemHeight + 16
    /// One half of the capsule while the two sit together.
    private static let segmentWidth: CGFloat = 96
    private static let inset: CGFloat = 4

    private var isApart: Bool { nowPlaying.isCardShown }

    var body: some View {
        HStack(spacing: isApart ? 10 : 0) {
            item(.home, systemImage: "house.fill", label: "Home")

            MiniPlayerBar(post: post, onOpen: onOpenPlayer)
                .frame(maxWidth: isApart ? .infinity : 0)
                .frame(height: Self.itemHeight)

            item(.gruppen, systemImage: "person.2.fill", label: "Gruppen")
        }
        .padding(isApart ? 0 : Self.inset)
        .background {
            if !isApart {
                Capsule().fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
        }
        // Ahead of the buttons once the finger moves 10 points: a tap still
        // reaches them, a finger sliding along the glass chooses as it goes.
        .highPriorityGesture(slide)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy, value: isApart)
        .animation(.snappy, value: hovered)
        .animation(.snappy, value: selectedPage)
    }

    /// Together: the highlight follows the finger along the capsule, and
    /// letting go chooses, as on the system bar. Apart: a swipe along the row
    /// moves one page.
    private var slide: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isApart else { return }
                hovered = RootNavSwipe.page(
                    atX: value.location.x - Self.inset, barWidth: Self.segmentWidth * 2)
            }
            .onEnded { value in
                let page = isApart
                    ? RootNavSwipe.page(afterSwipe: value.translation.width, from: selectedPage)
                    : hovered ?? selectedPage
                hovered = nil
                if page != selectedPage { onSelectPage(page) }
            }
    }

    private func item(_ page: RootTabView.Page, systemImage: String, label: String) -> some View {
        let isSelected = (hovered ?? selectedPage) == page
        return Button { onSelectPage(page) } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: isApart ? 19 : 17, weight: .semibold))
                if !isApart {
                    Text(label)
                        .font(.todBody(11, weight: .semibold))
                }
            }
            .foregroundStyle(isSelected ? Color.todAccent : Color.todText)
            .frame(
                width: isApart ? Self.itemHeight : Self.segmentWidth,
                height: isApart ? Self.itemHeight : Self.itemHeight - 2 * Self.inset)
            .background {
                if isApart {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(
                            isSelected ? Color.todAccent : Color.todLine,
                            lineWidth: isSelected ? 1.5 : 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                } else if isSelected {
                    // The highlight inside the capsule, as the system bar
                    // draws it.
                    Capsule().fill(Color.white.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
