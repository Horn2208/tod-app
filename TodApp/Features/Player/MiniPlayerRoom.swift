import SwiftUI

extension View {
    /// Keeps this screen's bottom clear of the mini player while its card shows.
    ///
    /// The card floats over the tab view. A safe-area inset on the tab's
    /// navigation stack would have made room automatically, but it does not reach
    /// the screens pushed onto that stack -- measured: the feed's progress sat
    /// under the card -- so each screen with something at its bottom asks for
    /// the room itself.
    func leavesRoomForMiniPlayer() -> some View {
        modifier(MiniPlayerRoom())
    }
}

private struct MiniPlayerRoom: ViewModifier {
    @Environment(NowPlaying.self) private var nowPlaying

    /// The card's 68 points, the 8 it keeps below itself, and 8 of air above.
    static let height: CGFloat = 84

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, nowPlaying.isCardShown ? Self.height : 0)
            .animation(.snappy, value: nowPlaying.isCardShown)
    }
}
