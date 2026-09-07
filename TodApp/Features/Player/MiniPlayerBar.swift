import SwiftUI

/// A thin bar that appears only while something is playing. Tapping it opens
/// the full song view; the button stops playback. It reads the store's mirror
/// of the provider's playback state rather than keeping its own idea of what
/// is playing -- a view that guesses is exactly the bug this app already had.
struct MiniPlayerBar: View {
    @Environment(AppStore.self) private var store
    let onOpen: () -> Void

    var body: some View {
        if let playing = store.currentlyPlaying {
            HStack(spacing: 12) {
                AsyncImage(url: playing.artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.todSurface3)
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Spielt gerade")
                    .font(.todBody(13))
                    .foregroundStyle(Color.todTextDim)

                Spacer()

                Button {
                    Task { await store.stopPlayback() }
                } label: {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(Color.todText)
                        .padding(8)
                }
                .accessibilityLabel("Wiedergabe pausieren")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.todLine).frame(height: 0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
    }
}
