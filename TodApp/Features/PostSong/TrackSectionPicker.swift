import SwiftUI

/// The prototype's waveform composer: drag a window over the track to pick the
/// stretch you want people to hear. Gesture only -- there is no audio behind
/// it, and Spotify stopped handing out preview URLs to new apps, so the
/// playhead is deliberately cosmetic.
struct TrackSectionPicker: View {
    let candidate: TrackCandidate
    @Binding var section: TrackSection

    /// Remembers where the window sat when a drag began, so moving it applies a
    /// delta instead of snapping its start to the finger.
    @State private var sectionAtDragStart: TrackSection?

    private static let barCount = 48
    private static let waveHeight: CGFloat = 64
    private static let handleTouchWidth: CGFloat = 28

    private var total: Double {
        if let seconds = candidate.durationSeconds, seconds > 0 { return Double(seconds) }
        return TrackSection.assumedDuration
    }

    private var lengthIsAssumed: Bool {
        (candidate.durationSeconds ?? 0) <= 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Track-Abschnitt wählen")
                .font(.todMono(11, weight: .semibold))
                .foregroundStyle(Color.todTextFaint)

            GeometryReader { geometry in
                waveform(width: geometry.size.width)
            }
            .frame(height: Self.waveHeight)

            Text(hint)
                .font(.todBody(12))
                .foregroundStyle(Color.todTextDim)

            // The prototype put the length badge inside the window. That works
            // for its 3:42 track; on a five-minute song 30 seconds is a tenth of
            // the width and the badge does not fit. It reads here instead.
            HStack {
                Text("Start: \(timestamp(section.start))")
                Spacer()
                Text("\(Int(section.duration.rounded())) Sek")
                    .foregroundStyle(Color.todAccent2)
                Spacer()
                Text("Ende: \(timestamp(section.end))")
            }
            .font(.todMono(11))
            .foregroundStyle(Color.todTextDim)
        }
    }

    private var hint: String {
        lengthIsAssumed
            ? "Ziehe den Clip zu deinem Lieblingsbereich. Die Länge ist geschätzt — dieser Dienst nennt sie nicht."
            : "Ziehe den Clip zu deinem Lieblingsbereich."
    }

    @ViewBuilder
    private func waveform(width: CGFloat) -> some View {
        let startX = position(of: section.start, in: width)
        let endX = position(of: section.end, in: width)

        ZStack(alignment: .topLeading) {
            bars

            RoundedRectangle(cornerRadius: 8)
                .fill(Color.todAccent.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.todAccent, lineWidth: 2)
                )
                .frame(width: max(endX - startX, 4), height: Self.waveHeight)
                .offset(x: startX)
                .gesture(windowDrag(width: width))

            handle(at: startX, width: width, edge: .start)
            handle(at: endX, width: width, edge: .end)
        }
        .contentShape(Rectangle())
    }

    private var bars: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(
                Array(WaveformShape.bars(count: Self.barCount, seed: candidate.id).enumerated()),
                id: \.offset
            ) { _, height in
                Capsule()
                    .fill(Color.todSurface3)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.waveHeight * height)
            }
        }
        .frame(height: Self.waveHeight)
    }

    private enum Edge { case start, end }

    private func handle(at x: CGFloat, width: CGFloat, edge: Edge) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.todAccent)
            .frame(width: 10, height: Self.waveHeight)
            .overlay(
                Capsule()
                    .fill(Color.todBackground.opacity(0.5))
                    .frame(width: 2, height: 16)
            )
            // A 10pt bar is too thin to hit; the touch area is wider than it looks.
            .contentShape(
                Rectangle().size(width: Self.handleTouchWidth, height: Self.waveHeight)
                    .offset(x: -(Self.handleTouchWidth - 10) / 2)
            )
            .offset(x: x - 5)
            .gesture(handleDrag(width: width, edge: edge))
    }

    private func handleDrag(width: CGFloat, edge: Edge) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let seconds = self.seconds(at: value.location.x + (edge == .start ? -5 : 5), in: width)
                switch edge {
                case .start: section.moveStart(to: seconds, in: total)
                case .end: section.moveEnd(to: seconds, in: total)
                }
            }
    }

    private func windowDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let anchor = sectionAtDragStart ?? section
                if sectionAtDragStart == nil { sectionAtDragStart = section }
                let shift = Double(value.translation.width / max(width, 1)) * total
                section.move(toStart: anchor.start + shift, in: total)
            }
            .onEnded { _ in sectionAtDragStart = nil }
    }

    private func position(of seconds: Double, in width: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(seconds / total) * width
    }

    private func seconds(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * total
    }

    private func timestamp(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
