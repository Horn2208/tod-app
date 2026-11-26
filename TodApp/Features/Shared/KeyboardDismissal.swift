import SwiftUI
import UIKit

/// Tap to close the keyboard, wherever one appears: a tap anywhere in an area
/// marked with `dismissesKeyboardOnTap()` closes it, a drag in its scroll view
/// pulls it down, and a tap on a text field leaves it open.
///
/// Fields inside such an area mark themselves with `keepsKeyboardOnTap()`.
/// Without that, a tap into a field would open the keyboard and close it in the
/// same moment -- the area's tap sees the touch as well.
extension View {
    func dismissesKeyboardOnTap() -> some View {
        modifier(KeyboardDismissArea())
    }

    func keepsKeyboardOnTap() -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: KeptFieldFrames.self,
                    value: [proxy.frame(in: .named(KeyboardDismissArea.space))]
                )
            }
        }
    }
}

private struct KeptFieldFrames: PreferenceKey {
    static let defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

private struct KeyboardDismissArea: ViewModifier {
    static let space = "keyboardDismissArea"

    /// A plain box, not state: the frames move with every scrolled point and
    /// are only read when a tap lands, so storing them must not redraw the area.
    @State private var kept = FrameBox()

    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .onPreferenceChange(KeptFieldFrames.self) { [kept] frames in
                MainActor.assumeIsolated { kept.frames = frames }
            }
            .simultaneousGesture(
                SpatialTapGesture(coordinateSpace: .named(Self.space)).onEnded { tap in
                    guard !kept.frames.contains(where: { $0.contains(tap.location) }) else { return }
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            )
            // Outermost, so the fields and the tap both measure against it.
            .coordinateSpace(.named(Self.space))
    }
}

@MainActor
private final class FrameBox {
    var frames: [CGRect] = []
}
