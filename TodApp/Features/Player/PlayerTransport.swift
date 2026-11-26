import SwiftUI

/// The controls both own players share: a waveform that shows progress and
/// takes a drag to seek, one round button, and the time.
struct Transport: View {
    let waveformSeed: String
    /// Off while posting: the section picker above is the waveform then, and
    /// the progress goes round the button instead.
    let showsWaveform: Bool
    let progress: Double
    let isPlaying: Bool
    let position: Double
    let duration: Double
    let isEnabled: Bool
    let toggle: () -> Void
    /// A fraction of the length, 0 to 1. The player turns it into seconds.
    let seek: (Double) -> Void
    /// Seconds to move by, back (negative) or forward.
    let skip: (Double) -> Void
    /// The five-second step under a dragging finger, for the tick it feels.
    @State private var scrubStep: Int?
    /// Counts on between the player's reports, so the waveform glides.
    @State private var clock = PlaybackClock()
    /// The two 15-second buttons. Off for Spotify, whose guidelines ask for
    /// play and pause only.
    var showsSkips = true

    var body: some View {
        if showsWaveform {
            fullControls
        } else {
            compactControls
        }
    }

    /// The reference design: waveform, the time centred under it, and three
    /// buttons -- the play button large and filled, the two skips small and
    /// grey, so there is no doubt which one matters.
    private var fullControls: some View {
        VStack(spacing: 14) {
            waveform

            Text("\(TrackPlayerSheet.timestamp(position)) / \(TrackPlayerSheet.timestamp(duration))")
                .font(.todMono(12))
                .foregroundStyle(Color.todTextDim)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Spoken.playback(position: position, duration: duration))

            HStack(spacing: 40) {
                if showsSkips {
                    skipButton(by: -PlaybackSkip.step, symbol: "gobackward.15", label: "15 Sekunden zurück")
                }

                Button(action: toggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.todBackground)
                        .frame(width: 76, height: 76)
                        .background(Color.todAccent, in: Circle())
                        .shadow(color: Color.todAccent.opacity(0.4), radius: 14, y: 6)
                }
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.4)
                .accessibilityLabel(isPlaying ? "Pause" : "Abspielen")

                if showsSkips {
                    skipButton(by: PlaybackSkip.step, symbol: "goforward.15", label: "15 Sekunden vor")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func skipButton(by seconds: Double, symbol: String, label: String) -> some View {
        Button { skip(seconds) } label: {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.todTextDim)
                .frame(width: 48, height: 48)
        }
        // Only once something plays: there is nowhere to skip to before.
        .disabled(!isEnabled || duration <= 0)
        .opacity(isEnabled && duration > 0 ? 1 : 0.4)
        .accessibilityLabel(label)
    }

    /// While posting: the picker above is the waveform, and the progress goes
    /// round the button.
    private var compactControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button(action: toggle) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.todBackground)
                        .frame(width: 46, height: 46)
                        .background(Color.todAccent, in: Circle())
                        .padding(showsWaveform ? 0 : 5)
                        .overlay {
                            if !showsWaveform {
                                Circle()
                                    .trim(from: 0, to: progress)
                                    .stroke(Color.todAccent2, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .padding(1.5)
                            }
                        }
                }
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1 : 0.4)
                .accessibilityLabel(isPlaying ? "Pause" : "Abspielen")

                Text("\(TrackPlayerSheet.timestamp(position)) / \(TrackPlayerSheet.timestamp(duration))")
                    .font(.todMono(12))
                    .foregroundStyle(Color.todTextFaint)
                    // "0:30 / 3:20" read out as it stands is a slash in the
                    // middle of two numbers.
                    .accessibilityLabel(Spoken.playback(position: position, duration: duration))
            }
            // Centred, like the rest of the section-picking screen.
            .frame(maxWidth: .infinity)
        }
    }

    /// The shape is generated from the track id, not measured from the audio
    /// -- see `Waveform`. What it shows truthfully is where playback has
    /// reached, and dragging across it moves there. Lit up to the playhead in
    /// the accent's gradient, quiet after it, with a soft edge between
    /// (`WaveformFill`) rather than a cut.
    private var waveform: some View {
        let bars = Waveform.bars(forTrack: waveformSeed)

        return GeometryReader { geo in
            // Redrawn every frame while playing, from the clock rather than the
            // last report -- SoundCloud reports about once a second, and a fill
            // that follows the reports moves in steps. Paused, it stands still
            // and draws nothing new.
            TimelineView(.animation(paused: !isPlaying)) { context in
                Rectangle()
                    .fill(litGradient(progress: liveProgress(at: context.date)))
            }
            .mask {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
                        Capsule()
                            .frame(maxWidth: .infinity)
                            .frame(height: max(3, geo.size.height * height))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                // `minimumDistance: 0` so a plain tap seeks too -- on a bar
                // this thin, most attempts to jump somewhere are taps.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geo.size.width > 0 else { return }
                        scrubStep = ScrubTick.step(fraction: value.location.x / geo.size.width, duration: duration)
                    }
                    .onEnded { value in
                        scrubStep = nil
                        guard geo.size.width > 0 else { return }
                        seek(min(max(value.location.x / geo.size.width, 0), 1))
                    }
            )
        }
        .frame(height: 42)
        .onChange(of: progress, initial: true) { report() }
        .onChange(of: isPlaying) { report() }
        // A light tick at each five seconds the finger crosses.
        .sensoryFeedback(.selection, trigger: scrubStep) { old, new in old != nil && new != nil }
        // Forty bars and a drag gesture are nothing at all to VoiceOver. One
        // element instead, carrying the position as its value, with swipe up
        // and down moving five seconds at a time.
        .accessibilityElement()
        .accessibilityLabel("Wiedergabe")
        .accessibilityValue(Spoken.playback(position: position, duration: duration))
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = 5 / duration
            switch direction {
            case .increment: seek(min(progress + step, 1))
            case .decrement: seek(max(progress - step, 0))
            @unknown default: break
            }
        }
    }

    private func report() {
        clock.report(position: progress * duration, isPlaying: isPlaying, at: Date())
    }

    /// Where the fill stands at `date`: the clock's count while playing, the
    /// reported progress otherwise and while the length is unknown.
    private func liveProgress(at date: Date) -> Double {
        guard isPlaying, duration > 0 else { return progress }
        let position = clock.estimate(at: date, isPlaying: true, duration: duration)
        return min(max(position / duration, 0), 1)
    }

    private func litGradient(progress: Double) -> LinearGradient {
        let stops = WaveformFill.stops(progress: progress)
        let played = stops.filter(\.isPlayed)
        return LinearGradient(
            stops: stops.map { stop in
                // The lit part runs from the accent into its second shade,
                // the rest is the quiet surface colour.
                let color: Color = if !stop.isPlayed {
                    .todSurface3
                } else if stop == played.first, played.count > 1 {
                    .todAccent
                } else {
                    .todAccent2
                }
                return Gradient.Stop(color: color, location: stop.location)
            },
            startPoint: .leading,
            endPoint: .trailing)
    }
}
