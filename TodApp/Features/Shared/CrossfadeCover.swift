import SwiftUI
import UIKit

/// A cover that changes without a gap: when the address changes, the old
/// picture stays until the new one has loaded, and then the new one fades in
/// over it. `AsyncImage` starts from its placeholder every time, which on Home
/// flashed the post's flat colour between two covers when the group changed.
///
/// A cover loaded before shows at once, from `CoverImages`.
struct CrossfadeCover: View {
    let url: URL?
    /// The post's own colour, for as long as there is no picture at all.
    let placeholderHex: String

    @State private var shown: Shown?

    private struct Shown {
        let url: URL
        let image: UIImage
    }

    init(url: URL?, placeholderHex: String) {
        self.url = url
        self.placeholderHex = placeholderHex
        _shown = State(initialValue: url.flatMap { url in
            CoverImages.shared.cached(url).map { Shown(url: url, image: $0) }
        })
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color(hex: placeholderHex))
            if let shown {
                Image(uiImage: shown.image)
                    .resizable()
                    .scaledToFill()
                    // A new identity per picture, so the new one fades in
                    // over the old rather than replacing it on the spot.
                    .id(shown.url)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: shown?.url)
        .task(id: url) {
            guard let url else {
                shown = nil
                return
            }
            guard shown?.url != url else { return }
            if let image = await CoverImages.shared.image(for: url) {
                guard !Task.isCancelled else { return }
                shown = Shown(url: url, image: image)
            } else if !Task.isCancelled {
                // No picture for this song: its colour, not the last song's cover.
                shown = nil
            }
        }
    }
}

/// Covers loaded once and kept in memory, so going back to a group shows its
/// cover straight away. `NSCache` lets the system take them back when memory
/// runs short.
@MainActor
final class CoverImages {
    static let shared = CoverImages()

    private let cache = NSCache<NSURL, UIImage>()

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cached(url) { return cached }
        guard let image = try? await Self.load(url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Off the main thread, decoded there too: a 600-pixel cover decoded on
    /// first draw would cost the frame the fade starts in.
    @concurrent
    private nonisolated static func load(_ url: URL) async throws -> UIImage? {
        // The same session as `CoverPalette`, so a cover read for its colour
        // comes from the cache here.
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)?.preparingForDisplay()
    }
}
