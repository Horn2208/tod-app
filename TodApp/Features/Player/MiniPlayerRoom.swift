import SwiftUI

extension View {
    /// Keeps this screen's bottom clear of `RootNavBar`, which floats over
    /// the tab view at all times now that it replaces the system tab bar.
    ///
    /// The bar floats over the tab view. A safe-area inset on the tab's
    /// navigation stack would have made room automatically, but it does not
    /// reach the screens pushed onto that stack -- measured: the feed's
    /// progress sat under the card -- so each screen with something at its
    /// bottom asks for the room itself.
    func leavesRoomForMiniPlayer() -> some View {
        modifier(MiniPlayerRoom())
    }
}

extension EnvironmentValues {
    /// Whether the keyboard is up. `RootNavBar` steps aside then, and the
    /// room kept for it goes too (`RootTabView` sets it).
    @Entry var isKeyboardUp = false
    /// Whether this root page is the one on screen, with nothing presented
    /// over it from the root (`RootTabView`). Home holds its ranking overlay
    /// back until it is.
    @Entry var isFrontmostPage = true
}

private struct MiniPlayerRoom: ViewModifier {
    @Environment(\.isKeyboardUp) private var isKeyboardUp

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, isKeyboardUp ? 0 : RootNavBar.height)
    }
}
