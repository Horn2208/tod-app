import ImageIO
import SwiftUI

/// Hands its content the colour a song's glow is painted in: the colour
/// derived from the track until the cover has been read, the cover's own once
/// it has (`ArtworkColor`). Without artwork it stays with the derived one.
///
/// A cover read before starts with its colour straight away
/// (`CoverPalette.cachedGlow`), and a new cover keeps the old colour until its
/// own is known, then blends across -- so switching groups on Home carries the
/// glow over instead of dropping to the derived colour first.
struct CoverTint<Content: View>: View {
    let artworkURL: URL?
    let fallbackHex: String
    let content: (Color) -> Content

    @State private var fromCover: ArtworkColor.RGB?

    init(artworkURL: URL?, fallbackHex: String, @ViewBuilder content: @escaping (Color) -> Content) {
        self.artworkURL = artworkURL
        self.fallbackHex = fallbackHex
        self.content = content
        _fromCover = State(initialValue: artworkURL.flatMap { CoverPalette.shared.cachedGlow(for: $0) })
    }

    var body: some View {
        content(fromCover.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
                ?? Color(hex: fallbackHex))
            .animation(.easeInOut(duration: 0.5), value: fromCover)
            .animation(.easeInOut(duration: 0.5), value: fallbackHex)
            .task(id: artworkURL) {
                guard let artworkURL else {
                    fromCover = nil
                    return
                }
                fromCover = await CoverPalette.shared.glow(for: artworkURL)
            }
    }
}

/// Reads each cover once. Home and the feed ask for the same covers over and
/// over; the answer does not change, so it is kept -- also when a cover has no
/// colour at all. Only a failed download is tried again.
@MainActor
final class CoverPalette {
    static let shared = CoverPalette()

    private var readings: [URL: Task<ArtworkColor.RGB?, Error>] = [:]
    /// What finished readings found, to be had without waiting.
    private var settled: [URL: ArtworkColor.RGB] = [:]

    func glow(for url: URL) async -> ArtworkColor.RGB? {
        let reading = readings[url] ?? Task { try await Self.read(url) }
        readings[url] = reading
        do {
            let glow = try await reading.value
            if let glow { settled[url] = glow }
            return glow
        } catch {
            readings[url] = nil
            return nil
        }
    }

    /// The colour of a cover read before, at once; nil when it has not been
    /// read yet or has no colour.
    func cachedGlow(for url: URL) -> ArtworkColor.RGB? {
        settled[url]
    }

    @concurrent
    private nonisolated static func read(_ url: URL) async throws -> ArtworkColor.RGB? {
        // The same session as `AsyncImage`, so a cover already on screen
        // comes from the cache rather than the network.
        let (data, _) = try await URLSession.shared.data(from: url)
        return ArtworkColor.dominant(in: pixels(in: data)).map(ArtworkColor.glow(for:))
    }

    /// The cover shrunk to a 16×16 grid -- plenty to tell its colour, and
    /// cheap enough to do for every card.
    nonisolated static func pixels(in data: Data, side: Int = 16) -> [ArtworkColor.RGB] {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: side * 4,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return [] }

        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }

        return stride(from: 0, to: bytes.count, by: 4).compactMap { i in
            let alpha = Double(bytes[i + 3]) / 255
            // Mostly transparent pixels carry no colour worth counting.
            guard alpha > 0.5 else { return nil }
            return ArtworkColor.RGB(
                red: Double(bytes[i]) / 255 / alpha,
                green: Double(bytes[i + 1]) / 255 / alpha,
                blue: Double(bytes[i + 2]) / 255 / alpha)
        }
    }
}
