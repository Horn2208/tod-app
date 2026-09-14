import Foundation
import MusicKit
import Observation
import os

/// Whole songs from Apple Music, starting at the section the poster picked.
///
/// Only for a listener whose subscription plays catalog songs -- see
/// `AppleMusicAccess`. The sound comes out of `ApplicationMusicPlayer`, the
/// app's own player, so the Music app's queue is left alone. None of it can be
/// heard in the simulator: catalog songs play only on a device with a
/// subscription.
///
/// One instance, app-wide, like the other two players.
@MainActor
@Observable
final class AppleMusicPlayer {
    /// The song loaded, playing or not.
    private(set) var song: CatalogSong?
    var songID: String? { song?.id }
    private(set) var isPaused = true
    /// Seconds into the whole song.
    private(set) var position: Double = 0
    private(set) var duration: Double = 0
    /// Between the press and the first sound: the song is being fetched and
    /// queued. Said on screen, so the press does not look ignored.
    private(set) var isStarting = false
    private(set) var failure: String?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    func isPlaying(_ id: String) -> Bool {
        songID == id && !isPaused
    }

    private var player: ApplicationMusicPlayer { .shared }

    /// `ApplicationMusicPlayer` is not Sendable, and awaiting its async calls
    /// from the main actor would hand it across an isolation boundary -- Swift 6
    /// refuses. These fetch the shared player where they await it instead.
    private nonisolated static func prepare() async throws {
        try await ApplicationMusicPlayer.shared.prepareToPlay()
    }

    private nonisolated static func play() async throws {
        try await ApplicationMusicPlayer.shared.play()
    }
    @ObservationIgnored private var ticker: Task<Void, Never>?
    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "applemusic")

    /// Play, pause, or -- for a song not loaded yet -- load it and play from
    /// the section's start. Loading happens on the press and never on opening
    /// a song: queueing a song replaces whatever was playing.
    func togglePlay(_ song: CatalogSong, from section: TrackSection?) {
        // A song that failed to start starts over: resuming would only call
        // play on a queue that never got the song, and the button would do
        // nothing a second time.
        guard song.id == songID, failure == nil else { return start(song, at: section?.start) }
        isPaused ? resume() : pause()
    }

    func pause() {
        player.pause()
        isPaused = true
        stopTicking()
    }

    func seek(to seconds: Double) {
        player.playbackTime = seconds
        position = seconds
    }

    private func resume() {
        Task {
            do {
                try await Self.play()
                isPaused = false
                startTicking()
            } catch {
                fail(error)
            }
        }
    }

    private func start(_ song: CatalogSong, at start: Double?) {
        stopTicking()
        self.song = song
        duration = Double(song.durationSeconds ?? 0)
        position = start ?? 0
        failure = nil
        isPaused = true
        isStarting = true
        let id = song.id

        Task {
            defer { if songID == id { isStarting = false } }
            do {
                let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
                guard let item = try await request.response().items.first else {
                    if songID == id { failure = "Apple Music hat diesen Song nicht mehr." }
                    return
                }
                // Another song may have been pressed while this one was fetched.
                guard songID == id else { return }
                // The entry carries the start itself, so the song begins where the
                // poster put it rather than at zero and then jumping.
                player.queue = ApplicationMusicPlayer.Queue([MusicPlayer.Queue.Entry(item, startTime: start)])
                try await Self.prepare()
                guard songID == id else { return }
                try await Self.play()
                if let length = item.duration { duration = length }
                isPaused = false
                startTicking()
                Self.log.notice("play \(id, privacy: .public) from \(start ?? 0)")
            } catch {
                guard songID == id else { return }
                fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        failure = "Apple Music konnte den Song gerade nicht abspielen."
        isPaused = true
        stopTicking()
        Self.log.error("failed \(self.songID ?? "-", privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    /// Reads where playback is, four times a second, while it runs. A status
    /// that is not "playing" counts only on the second look in a row: right
    /// after `play()` the player can still report paused for a moment, and one
    /// look would stop the clock on a song that is just starting.
    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            var quietLooks = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.position = self.player.playbackTime
                if self.player.state.playbackStatus == .playing {
                    quietLooks = 0
                } else {
                    quietLooks += 1
                    if quietLooks >= 2 {
                        self.isPaused = true
                        self.ticker = nil
                        return
                    }
                }
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }
}
