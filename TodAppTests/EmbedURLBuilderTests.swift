import Foundation
import Testing
@testable import TodApp

@Suite
struct EmbedURLBuilderTests {
    @Test
    func buildsSpotifyEmbedURL() {
        let source = TrackSource(
            service: .spotify,
            serviceTrackID: "abc123",
            pageURL: URL(string: "https://open.spotify.com/track/abc123")!,
            artworkURL: nil
        )

        let url = EmbedURLBuilder.embedURL(for: source)

        #expect(url.absoluteString == "https://open.spotify.com/embed/track/abc123?theme=0")
    }

    @Test
    func buildsSoundCloudWidgetURLWithBrandColour() throws {
        let page = URL(string: "https://soundcloud.com/artist/some-track")!
        let source = TrackSource(
            service: .soundcloud, serviceTrackID: page.absoluteString,
            pageURL: page, artworkURL: nil
        )

        let url = EmbedURLBuilder.embedURL(for: source)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.host == "w.soundcloud.com")
        #expect(items.contains { $0.name == "url" && $0.value == page.absoluteString })
        #expect(items.contains { $0.name == "color" && $0.value == "#b3527a" })
        #expect(items.contains { $0.name == "visual" && $0.value == "false" })
        #expect(items.contains { $0.name == "hide_related" && $0.value == "true" })
    }

    @Test
    func encodesSoundCloudPermalinkExactlyOnceForWidgetQuery() {
        let page = URL(string: "https://soundcloud.com/artist/track%20with%20spaces")!
        let source = TrackSource(
            service: .soundcloud, serviceTrackID: page.absoluteString,
            pageURL: page, artworkURL: nil
        )

        let url = EmbedURLBuilder.embedURL(for: source)

        #expect(
            url.absoluteString == "https://w.soundcloud.com/player/?url=https%3A%2F%2Fsoundcloud.com%2Fartist%2Ftrack%20with%20spaces&color=%23b3527a&visual=false&hide_related=true"
        )
    }
}
