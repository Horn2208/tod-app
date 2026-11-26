import MediaPlayer
import SwiftUI

/// The phone's own volume, between a quiet and a loud speaker.
///
/// `MPVolumeView` is the only way an app may move the system volume, and the
/// system volume is what all three players come out of -- Apple Music, Apple's
/// preview and Spotify's web view alike. It draws nothing in the simulator,
/// where there is no volume to show.
struct SystemVolumeSlider: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
            VolumeView()
                .frame(height: 34)
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.todTextFaint)
        // The system slider announces itself; the two speakers are decoration.
        .accessibilityElement(children: .contain)
    }

    private struct VolumeView: UIViewRepresentable {
        func makeUIView(context: Context) -> MPVolumeView {
            let view = MPVolumeView(frame: .zero)
            view.tintColor = UIColor(Color.todAccent)
            return view
        }

        func updateUIView(_ uiView: MPVolumeView, context: Context) {}
    }
}
