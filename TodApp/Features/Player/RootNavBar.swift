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

    /// Across the page itself it takes more than on the bar: the page also
    /// scrolls up and down, and a finger drifting sideways while it does must
    /// not change the page.
    static let contentThreshold: Double = 60
    /// How much more sideways than up or down a swipe has to be.
    static let dominance: Double = 1.5

    /// A swipe across the page's content: the same direction as on the bar,
    /// only on the page's first level -- a screen pushed onto it (the rating
    /// feed turns its pages sideways) keeps its own swipes -- and not when it
    /// began in a row that scrolls sideways itself.
    static func page(
        afterContentSwipe dx: Double, dy: Double, from page: RootTabView.Page,
        isAtRoot: Bool, beganInSidewaysRow: Bool
    ) -> RootTabView.Page {
        guard isAtRoot, !beganInSidewaysRow,
              abs(dx) >= contentThreshold, abs(dx) >= dominance * abs(dy)
        else { return page }
        return self.page(afterSwipe: dx, from: page)
    }
}

/// Rows that scroll sideways themselves -- the group switcher on Home, the
/// story row on Gruppen -- say where they are, so a swipe inside them moves
/// the row and not the page (`RootTabView`).
struct SidewaysRowFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func claimsSidewaysSwipes() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: SidewaysRowFrames.self, value: [proxy.frame(in: .global)])
            }
        }
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
///
/// Nothing playing, the middle of the capsule is a "+" that opens "Song
/// posten" at its search (the redesign brief, 25. September, idea 3 in its
/// simple form: the search now, bookmarks maybe later).
struct RootNavBar: View {
    @Environment(NowPlaying.self) private var nowPlaying
    let selectedPage: RootTabView.Page
    let onSelectPage: (RootTabView.Page) -> Void
    /// Passed straight through to the mini player -- see `MiniPlayerBar`.
    let post: Submission?
    let onOpenPlayer: (() -> Void)?
    /// The "+" in the middle while nothing plays.
    let onPost: () -> Void

    /// The page under the finger while it slides along the capsule.
    @State private var hovered: RootTabView.Page?
    /// Where the glass pieces know each other, to flow together and apart.
    @Namespace private var glass

    /// The height of all three: the two buttons and the pill between.
    static let itemHeight: CGFloat = 56
    /// The room screens keep clear at their bottom: the row, the 8 points
    /// under it, and 8 of air above.
    static let height: CGFloat = itemHeight + 16
    /// One half of the capsule while the two sit together.
    private static let segmentWidth: CGFloat = 96
    private static let inset: CGFloat = 4
    /// The "+" between the halves.
    private static let plusWidth: CGFloat = 60

    private var isApart: Bool { nowPlaying.isCardShown }

    var body: some View {
        LiquidGlassGroup(spacing: 10) {
            HStack(spacing: isApart ? 10 : 0) {
                item(.home, systemImage: "house.fill", label: "Home")

                if !isApart {
                    plusButton
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                MiniPlayerBar(post: post, onOpen: onOpenPlayer, glass: glass)
                    .frame(maxWidth: isApart ? .infinity : 0)
                    .frame(height: Self.itemHeight)

                item(.gruppen, systemImage: "person.2.fill", label: "Gruppen")
            }
            // Together, the whole row is one piece of glass: three pieces
            // melted with `union` kept their own round ends and read as three
            // (the redesign brief, 26. September, evening, Prio 1).
            .modifier(BarGlass(isOn: !isApart, glass: glass))
            .background {
                if !isApart && !LiquidGlass.isAvailable {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Color.todLine, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                }
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
                    atX: value.location.x, barWidth: Self.segmentWidth * 2 + Self.plusWidth)
            }
            .onEnded { value in
                let page = isApart
                    ? RootNavSwipe.page(afterSwipe: value.translation.width, from: selectedPage)
                    : hovered ?? selectedPage
                hovered = nil
                if page != selectedPage { onSelectPage(page) }
            }
    }

    /// A round accent "+" in its own piece of the capsule.
    private var plusButton: some View {
        Button(action: onPost) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.todAccent))
                .frame(width: Self.plusWidth, height: Self.itemHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Song posten")
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
            // Full height together too: the glass is drawn around this frame,
            // so a shorter one made the capsule 48 points against the round
            // buttons' 56 (the redesign brief, 26. September, point 5).
            .frame(width: isApart ? Self.itemHeight : Self.segmentWidth, height: Self.itemHeight)
            .background {
                if !isApart && isSelected {
                    // The highlight inside the capsule, as the system bar
                    // draws it.
                    Capsule().fill(Color.white.opacity(0.12)).padding(Self.inset)
                }
            }
            .contentShape(Rectangle())
            .modifier(ItemGlass(isApart: isApart, isSelected: isSelected, id: "\(page)", glass: glass))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The one capsule of glass behind the whole row while it sits together.
private struct BarGlass: ViewModifier {
    let isOn: Bool
    let glass: Namespace.ID

    func body(content: Content) -> some View {
        if isOn && LiquidGlass.isAvailable {
            content.liquidGlass(in: Capsule(), id: "bar", namespace: glass)
        } else {
            content
        }
    }
}

/// A bar item's glass: apart, its own round piece with an accent rim when
/// chosen; together, none of its own -- it sits on the row's capsule
/// (`BarGlass`), and the pieces flow out of it when a song starts.
private struct ItemGlass: ViewModifier {
    let isApart: Bool
    let isSelected: Bool
    let id: String
    let glass: Namespace.ID

    func body(content: Content) -> some View {
        if !isApart {
            content
        } else if LiquidGlass.isAvailable {
            content
                .liquidGlass(in: Circle(), id: id, namespace: glass)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.todAccent, lineWidth: 1.5)
                    }
                }
        } else {
            content
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(
                    isSelected ? Color.todAccent : Color.todLine,
                    lineWidth: isSelected ? 1.5 : 0.5))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        }
    }
}
