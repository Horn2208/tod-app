import Foundation
import Testing
@testable import TodApp

@MainActor
@Suite
struct PreviewPlayerTests {
    /// A file that is not there fails the item the way a dropped connection does.
    private let broken = CatalogSong(
        id: "broken", title: "Nights", artist: "Frank Ocean",
        previewURL: URL(fileURLWithPath: "/nonexistent/preview.m4a"))

    private func failure(of player: PreviewPlayer) async -> String? {
        for _ in 0..<50 where player.failure == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return player.failure
    }

    /// Once the button stayed dead after a failed load, until another song was
    /// chosen. A press now loads the song afresh.
    @Test
    func aPressAfterAFailedLoadTriesAgain() async {
        let player = PreviewPlayer()
        player.load(broken)
        #expect(await failure(of: player) != nil)

        player.togglePlay(broken)
        #expect(player.failure == nil)
        #expect(!player.isPaused)
    }

    @Test
    func aSongWithoutAPreviewStaysSilent() {
        let player = PreviewPlayer()
        let silent = CatalogSong(id: "silent", title: "Nights", artist: "Frank Ocean")
        player.togglePlay(silent)
        #expect(player.failure != nil)
        #expect(player.isPaused)
    }
}
