import SwiftUI

/// Font roles from tod-prototype.html: Unbounded (display), Manrope (body),
/// JetBrains Mono (meta). The files are in Resources/Fonts and listed under
/// `UIAppFonts`: static weights, each with its own PostScript name, so a weight
/// is picked by name (`BrandFont`) rather than left to the system's matching --
/// a name that does not resolve falls back to the system font without a word.
extension Font {
    static func todDisplay(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(BrandFont.display(weight), size: size, relativeTo: .headline)
    }

    static func todBody(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(BrandFont.body(weight), size: size, relativeTo: .body)
    }

    static func todMono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(BrandFont.mono(weight), size: size, relativeTo: .caption)
    }

    /// Apple's New York in italic, for the few words that should read like a
    /// title on a record sleeve: song titles and headlines. A system face, so
    /// no file is bundled. Fixed size, like a cover's own lettering.
    static func todSerif(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }

    /// The same face, following Dynamic Type through a text style.
    static func todSerif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight).italic()
    }
}

extension View {
    /// A soft light around text: a tight shadow for the edge, a wide one for
    /// the halo, both in one colour. Sparingly -- like the streak's sheen, it
    /// means something only while it is rare.
    func todGlow(color: Color = .todAccent) -> some View {
        shadow(color: color.opacity(0.9), radius: 2)
            .shadow(color: color.opacity(0.55), radius: 12)
    }
}

/// Which bundled face a weight asks for. Pure, so a test can check every
/// name resolves (`BrandFontTests`).
enum BrandFont {
    /// Unbounded is bundled in bold only: the headlines are all bold.
    static func display(_ weight: Font.Weight) -> String {
        "Unbounded-Bold"
    }

    static func body(_ weight: Font.Weight) -> String {
        "Manrope-\(style(weight))"
    }

    static func mono(_ weight: Font.Weight) -> String {
        "JetBrainsMono-\(style(weight))"
    }

    /// The nearest of the four bundled weights.
    static func style(_ weight: Font.Weight) -> String {
        switch weight {
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold, .heavy, .black: "Bold"
        default: "Regular"
        }
    }

    /// Every face the app asks for, for the test that each one is there.
    static var allNames: [String] {
        let weights: [Font.Weight] = [.regular, .medium, .semibold, .bold]
        return [display(.bold)] + weights.map(body) + weights.map(mono)
    }
}

/// Motion numbers in one place (ux-motion): a press answers in ~120ms, a
/// transition takes 150-300ms, closing is quicker than opening, a list's
/// stagger is 30-60ms a row and never runs past ~300ms in all.
enum Motion {
    /// A button under the finger: springs back with a hint of overshoot.
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.8)
    /// A state change in place (a pick, a toggle, a tab).
    static let change = Animation.spring(response: 0.3, dampingFraction: 0.85)
    /// Something arriving.
    static let enter = Animation.easeOut(duration: 0.25)
    /// Something leaving: about half the way in.
    static let exit = Animation.easeIn(duration: 0.12)
    /// A tab page coming forward ("Zoom und Tiefe"): ease-out, 280ms.
    static let pageIn = Animation.easeOut(duration: 0.28)
    /// The page it replaces receding: ease-in, half the way in.
    static let pageOut = Animation.easeIn(duration: 0.14)
    /// Scale of a page that is not showing: it sits slightly behind.
    static let pageDepthScale: CGFloat = 0.96
    /// With Reduce Motion: a plain short crossfade, no scale.
    static let pageFade = Animation.easeInOut(duration: 0.15)
    /// A pick that is worth a small pop, like the hidden gem.
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Delay for row `index` of a list that comes in one by one: 45ms
    /// apart, the whole cascade capped at 300ms.
    static func stagger(_ index: Int) -> Double { min(Double(index) * 0.045, 0.3) }
}

/// A soft diagonal highlight sweeping left to right over a placeholder, once
/// per ~1.3s, linear: it is a progress indicator, not a movement to read.
/// Put it once on the whole skeleton so the sweep is shared. With Reduce
/// Motion the placeholder pulses gently instead of sweeping.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var isDim = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.35),
                                .init(color: .white.opacity(0.10), location: 0.5),
                                .init(color: .clear, location: 0.65),
                            ],
                            startPoint: UnitPoint(x: 0, y: 0),
                            endPoint: UnitPoint(x: 1, y: 0.35))
                            .frame(width: geo.size.width * 2, height: geo.size.height)
                            .offset(x: -geo.size.width * 2 + geo.size.width * 3 * phase)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .opacity(reduceMotion && isDim ? 0.6 : 1)
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { isDim = true }
                } else {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }

    /// Comes in at `step` of a short cascade (50ms apart): a fade and a
    /// small rise. Reduce Motion: a quick fade, no rise, no delay.
    func staggerIn(_ step: Int, on: Bool) -> some View { modifier(StaggerIn(step: step, on: on)) }
}

private struct StaggerIn: ViewModifier {
    let step: Int
    let on: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : 7)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.15)
                    : .easeOut(duration: 0.2).delay(Double(step) * 0.05),
                value: on)
    }
}

/// A grey block of a placeholder; the neutral fill of the theme.
struct SkeletonBlock: View {
    var radius: CGFloat = 8
    var body: some View {
        RoundedRectangle(cornerRadius: radius).fill(Color.todSurface3)
    }
}

// MARK: - Layout tokens, read from Spotify's DESIGN.md
//
// Reference: VoltAgent/awesome-design-md, design-md/spotify. What is taken:
// an 8pt base unit with a 4/8/12/16/24 scale; a tight radius scale (6 art,
// 8-20 cards, pill for buttons and search, circle for play); a bold/regular
// binary for text (weight, not size, makes the hierarchy) in a compact
// 10-24 range; one functional accent, album art as the colour; surfaces
// stepped by shade rather than lines; secondary text in a silver, never in a
// faint grey; red for the negative; a heavy shadow (0.5 black, 24 blur) for
// what floats. What is not taken: its green, its sans, its uppercase button
// labels. TodApp keeps the serif titles and the cover-driven dark look.

/// Spacing: one scale, 8pt base. `edge` is the screen's side margin, the same
/// left and right on every screen.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let edge: CGFloat = 16
    /// The least a thumb can hit (HIG).
    static let hit: CGFloat = 44
}

/// Corner radii. Pills (`Capsule`) are for buttons and search; circles for play
/// and avatars.
enum Radius {
    static let art: CGFloat = 6
    static let chip: CGFloat = 10
    static let field: CGFloat = 12
    static let card: CGFloat = 14
    static let sheet: CGFloat = 24
}

extension Color {
    /// Spotify's "negative": what is destructive or wrong. Gold (`todAccent2`)
    /// stays for the warning and the hidden gem, so red never has to share.
    static let todNegative = Color(hex: "#ef7d88")
}

extension Font {
    /// Type roles. Weight carries the hierarchy: bold or regular, semibold
    /// only for small controls.
    static var todSectionTitle: Font { .todSerif(24, weight: .bold) }
    static var todHeading: Font { .todBody(18, weight: .semibold) }
    static var todRowTitle: Font { .todBody(16, weight: .bold) }
    static var todCaption: Font { .todBody(14) }
    static var todSmall: Font { .todBody(12) }
}

extension View {
    /// The small caps label over a group or a field: mono, wide-tracked,
    /// silver -- one voice for every "what is this" line.
    func todLabel() -> some View {
        font(.todMono(11, weight: .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Color.todTextDim)
    }

    /// A block of settings or info: the next surface step up, no line.
    func todCard(padding: CGFloat = Space.l) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.todSurface, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    /// A text field: surface step, 12pt radius, no hairline, an accent ring
    /// only while it has focus (pass the state).
    func todField(focused: Bool = false) -> some View {
        padding(.horizontal, Space.l)
            .frame(minHeight: Space.hit + 4)
            .background(Color.todSurface2, in: RoundedRectangle(cornerRadius: Radius.field))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field)
                    .strokeBorder(focused ? Color.todAccent : .clear, lineWidth: 1.5))
    }

    /// What floats over a cover or a dimmed screen: Spotify's heavy shadow.
    func todElevated() -> some View {
        shadow(color: .black.opacity(0.5), radius: 24, y: 8)
    }
}

/// The quiet button next to the one primary action: a pill, outlined, 44pt
/// tall. Several on one screen do not compete; the one filled pill does.
struct TodSecondaryButtonStyle: ButtonStyle {
    var tint: Color = .todText
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.todBody(14, weight: .bold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: Space.hit)
            .padding(.horizontal, Space.l)
            .background(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension View {
    /// The tab page transition: the page that is not showing sits slightly
    /// back and faded, so switching reads as depth. Driven by `isShown`
    /// alone, so a tap mid-way just retargets the same values and never
    /// stacks. Reduce Motion: crossfade only.
    func tabPageDepth(isShown: Bool, reduceMotion: Bool) -> some View {
        scaleEffect(isShown || reduceMotion ? 1 : Motion.pageDepthScale)
            .opacity(isShown ? 1 : 0)
            .animation(reduceMotion ? Motion.pageFade : (isShown ? Motion.pageIn : Motion.pageOut), value: isShown)
    }
}
