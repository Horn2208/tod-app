import SwiftUI

/// The one waveform on the posting screen: the whole song as a line of bars,
/// the window over it that picks the stretch people will hear, and -- while a
/// whole song plays -- where playback stands. It replaced two waveforms that
/// sat on top of each other, one for listening and one for picking.
///
/// The bars are the player's own (`Waveform`, same seed), so the song looks the
/// same here as it does later to everyone listening. They are drawn, not
/// measured: no service hands out samples.
struct TrackSectionPicker: View {
    /// The song's length in seconds, or an assumed one (`lengthIsAssumed`).
    let total: Double
    let lengthIsAssumed: Bool
    let waveformSeed: String
    @Binding var section: TrackSection
    /// Where playback stands in the song, in seconds. Nil when that is not
    /// known -- a preview is a fixed excerpt Apple does not place.
    var playhead: Double? = nil
    /// Who will hear the pick from its start (`SectionReach`). Nil says nothing.
    var reachNote: String? = nil

    /// Remembers where the window sat when a drag began, so moving it applies a
    /// delta instead of snapping its start to the finger.
    @State private var sectionAtDragStart: TrackSection?

    private static let waveHeight: CGFloat = 64
    private static let handleTouchWidth: CGFloat = 28

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
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
            // Start, length and end are one reading, not three.
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity)

            // Always there and always the same, not flashed on each drag: a
            // property of the services, not a warning about this pick.
            if let reachNote {
                Text(reachNote)
                    .font(.todBody(12))
                    .foregroundStyle(Color.todTextFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
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

            if let playhead {
                Capsule()
                    .fill(Color.todText)
                    .frame(width: 2, height: Self.waveHeight + 8)
                    .offset(x: position(of: playhead, in: width) - 1, y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

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
        let heights = Waveform.bars(forTrack: waveformSeed)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                let played = playhead.map {
                    SectionTimeline.isPlayed(bar: index, of: heights.count, playhead: $0, total: total)
                } ?? false
                Capsule()
                    .fill(played ? AnyShapeStyle(Self.playedStyle) : AnyShapeStyle(Color.todSurface3))
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.waveHeight * height)
            }
        }
        .frame(height: Self.waveHeight)
        // Decoration: the shape comes from the track id, not from the audio.
        .accessibilityHidden(true)
    }

    /// The same fill as the player's waveform for what has been heard.
    private static let playedStyle = LinearGradient(
        colors: [Color.todAccent, Color.todAccent2],
        startPoint: .leading,
        endPoint: .trailing
    )

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
            // A 10pt bar behind a drag gesture is nothing VoiceOver can find
            // or move. One element per edge instead, carrying its time as the
            // value, five seconds to a step.
            .accessibilityElement()
            .accessibilityLabel(edge == .start ? "Abschnitt-Start" : "Abschnitt-Ende")
            .accessibilityValue(Spoken.time(edge == .start ? section.start : section.end))
            .accessibilityAdjustableAction { direction in
                let step: Double
                switch direction {
                case .increment: step = 5
                case .decrement: step = -5
                @unknown default: return
                }
                switch edge {
                case .start: section.moveStart(to: section.start + step, in: total)
                case .end: section.moveEnd(to: section.end + step, in: total)
                }
            }
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
        CGFloat(SectionTimeline.fraction(of: seconds, in: total)) * width
    }

    private func seconds(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(x / width) * total
    }

    private func timestamp(_ seconds: Double) -> String {
        Spoken.time(seconds)
    }
}
