import SwiftUI

/// Apple's Liquid Glass where the system has it (iOS 26 on), the frosted
/// material before it.
///
/// Liquid Glass is what the system tab bar was made of: it gives under a
/// finger (`interactive`), and pieces that share a `GlassEffectContainer`
/// flow into one another as they meet or part -- which is how the bottom bar's
/// capsule becomes two buttons and the player when a song starts. The frosted
/// material can only look like glass, not move like it.
extension View {
    /// Glass in `shape`. `id` lets it flow into its neighbours in the same
    /// container; `union` melts pieces with the same value into one.
    @ViewBuilder
    func liquidGlass<S: Shape>(
        in shape: S,
        id: String? = nil,
        union: String? = nil,
        namespace: Namespace.ID? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass: Glass = interactive ? .regular.interactive() : .regular
            if let namespace {
                self.glassEffect(glass, in: shape)
                    .glassEffectID(id, in: namespace)
                    .glassEffectUnion(id: union, namespace: namespace)
            } else {
                self.glassEffect(glass, in: shape)
            }
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Color.todLine, lineWidth: 0.5))
        }
    }
}

enum LiquidGlass {
    /// Whether Liquid Glass draws here; the frosted fallback needs a hand
    /// with what glass does by itself.
    static var isAvailable: Bool {
        if #available(iOS 26.0, *) { true } else { false }
    }
}

/// The container glass pieces flow within -- a plain group before iOS 26.
struct LiquidGlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// The app's glass card: thin material, a rounded shape, a hairline in
    /// `todLine`. Was the same three modifiers at every card, each free to
    /// drift from the others.
    ///
    /// `clipsContent: false` for cards whose content may reach past the
    /// corners: the material and line are drawn in the shape, the content is
    /// left alone -- as those cards did before.
    func todGlassCard(radius: CGFloat = 20, clipsContent: Bool = true) -> some View {
        modifier(GlassCard(radius: radius, clipsContent: clipsContent))
    }
}

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    let clipsContent: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        if clipsContent {
            content
                .background(.ultraThinMaterial, in: shape)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.todLine, lineWidth: 0.5))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.todLine, lineWidth: 0.5))
        }
    }
}
