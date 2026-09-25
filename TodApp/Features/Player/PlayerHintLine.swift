import SwiftUI

/// A limit of the service in one short line, the full explanation behind an
/// (i) that opens it as a popover (`PlayerHint`).
struct PlayerHintLine: View {
    let hint: PlayerHint
    @State private var isExplaining = false

    var body: some View {
        HStack(spacing: 6) {
            Text(hint.short)
                .font(.todMono(12, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)
            Button { isExplaining = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.todTextDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -12)
            .accessibilityLabel("Mehr dazu")
            .popover(isPresented: $isExplaining) {
                // A fixed width: with only a maximum the popover measures the
                // text as one long line and cuts the wrapped lines off.
                Text(hint.detail)
                    .font(.todBody(14))
                    .foregroundStyle(Color.todText)
                    .multilineTextAlignment(.leading)
                    .frame(width: 260, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(hint.detail)
    }
}

/// One line of text that scrolls sideways when it does not fit, instead of
/// wrapping or being cut; still, and cut, with Reduce Motion on.
struct MarqueeText: View {
    let text: String
    let font: Font
    var color: Color = .todText

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Points per second, and the pause at each end.
    private static let speed: CGFloat = 30
    private static let pause: Double = 1.5
    private static let gap: CGFloat = 40

    var body: some View {
        GeometryReader { box in
            let overflows = textWidth > box.size.width
            HStack(spacing: Self.gap) {
                label
                if overflows && !reduceMotion { label }
            }
            .fixedSize()
            .offset(x: overflows && !reduceMotion ? offset : 0)
            .frame(width: box.size.width, alignment: overflows ? .leading : .center)
            .clipped()
            .task(id: overflows && !reduceMotion ? textWidth : -1) {
                guard overflows, !reduceMotion else { offset = 0; return }
                let distance = textWidth + Self.gap
                while !Task.isCancelled {
                    offset = 0
                    try? await Task.sleep(for: .seconds(Self.pause))
                    withAnimation(.linear(duration: Double(distance / Self.speed))) { offset = -distance }
                    try? await Task.sleep(for: .seconds(Double(distance / Self.speed)))
                }
            }
        }
        .frame(height: lineHeight)
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.onAppear { textWidth = proxy.size.width }
                    .onChange(of: text) { textWidth = proxy.size.width }
            })
    }

    private var lineHeight: CGFloat { 32 }
}
