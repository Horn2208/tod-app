import Foundation
import Testing
@testable import TodApp

@Suite
struct ITunesCatalogTests {
    private func catalog(status: Int = 200, body: String, box: RequestBox = RequestBox()) -> ITunesCatalog {
        ITunesCatalog(country: "de") { request in
            box.store(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    /// Trimmed from a real answer: one song, one music video.
    private let body = """
    {"resultCount":2,"results":[
    {"kind":"song","trackId":1499378607,"trackName":"Blinding Lights","artistName":"The Weeknd",
     "trackTimeMillis":200046,
     "previewUrl":"https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview211/x.m4a",
     "trackViewUrl":"https://music.apple.com/de/album/blinding-lights/1499378108?i=1499378607"},
    {"kind":"music-video","trackId":1,"trackName":"Blinding Lights","artistName":"The Weeknd"}
    ]}
    """

    @Test
    func asksTheStorefrontForSongsByTitleAndArtist() async throws {
        let box = RequestBox()
        _ = try await catalog(body: body, box: box).search(title: "Blinding Lights", artist: "The Weeknd")

        let items = URLComponents(url: try #require(box.value?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "term", value: "Blinding Lights The Weeknd")))
        #expect(items.contains(URLQueryItem(name: "entity", value: "song")))
        #expect(items.contains(URLQueryItem(name: "country", value: "de")))
    }

    @Test
    func readsASongAndDropsWhatIsNotOne() async throws {
        let songs = try await catalog(body: body).search(title: "Blinding Lights", artist: "The Weeknd")

        #expect(songs.count == 1)
        #expect(songs.first?.id == "1499378607")
        #expect(songs.first?.durationSeconds == 200)
        #expect(songs.first?.previewURL?.absoluteString.hasSuffix("x.m4a") == true)
    }

    @Test
    func looksASongUpByItsStoredID() async throws {
        let box = RequestBox()
        let song = try await catalog(body: body, box: box).song(id: "1499378607")

        #expect(song?.title == "Blinding Lights")
        #expect(box.value?.url?.path == "/lookup")
    }

    @Test
    func aRefusedRequestIsAnError() async {
        await #expect(throws: TodAppError.self) {
            try await catalog(status: 503, body: "").search(title: "x", artist: "y")
        }
    }
}
