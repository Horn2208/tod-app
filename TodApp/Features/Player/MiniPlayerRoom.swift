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

private struct MiniPlayerRoom: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, RootNavBar.height)
    }
}
