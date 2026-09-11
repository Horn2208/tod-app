import AVFoundation
import Observation
import os

/// Plays a catalog preview natively: an `AVPlayer`, no web view, no
/// JavaScript bridge, no login.
///
/// One instance, app-wide, like `SpotifyEmbedPlayer` -- two players would talk
/// over each other. What it plays is Apple's fixed excerpt, measured at 30.0
/// seconds on four songs of 200 to 354 seconds, so a picked section is out of
/// its reach. The whole song with a seek to the section is MusicKit's job,
/// once the developer account exists.
@MainActor
@Observable
final class PreviewPlayer {
    /// The catalog song loaded, playing or not.
    private(set) var song: CatalogSong?
    var songID: String? { song?.id }
    private(set) var isPaused = true
    /// Seconds into the preview.
    private(set) var position: Double = 0
    /// The preview's own length, once the item has loaded -- not the song's.
    private(set) var duration: Double = 0
    /// Why nothing will play, said instead of a button that does nothing.
    private(set) var failure: String?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Short of the exact end on purpose: the last time update lands a
    /// fraction before it, the same trap the embed fell into.
    private var hasFinished: Bool {
        duration > 0 && position >= duration - 0.25
    }

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "preview")

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                if time.seconds.isFinite { self?.position = time.seconds }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didReachEnd() }
        }
        // Lives as long as the app; nothing to tear down.
    }

    func isPlaying(_ id: String) -> Bool {
        songID == id && !isPaused
    }

    /// Points the player at a song without starting it: opening a song must
    /// not start noise by itself.
    func load(_ song: CatalogSong) {
        guard song.id != songID else { return }
        player.pause()
        self.song = song
        isPaused = true
        position = 0
        duration = 0
        failure = nil
        statusObservation = nil

        guard let url = song.previewURL else {
            player.replaceCurrentItem(with: nil)
            failure = "Für diesen Song hat Apple Music keine Vorschau."
            return
        }
        let item = AVPlayerItem(url: url)
        let id = song.id
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let length = item.duration.seconds
            Task { @MainActor in self?.itemChanged(id: id, status: status, length: length) }
        }
        player.replaceCurrentItem(with: item)
        Self.log.notice("load \(id, privacy: .public)")
    }

    func togglePlay(_ song: CatalogSong) {
        if song.id != songID { load(song) }
        guard failure == nil, player.currentItem != nil else { return }
        guard isPaused else { return pause() }
        if hasFinished {
            player.seek(to: .zero)
            position = 0
        }
        activateSession()
        player.play()
        isPaused = false
        Self.log.notice("play \(song.id, privacy: .public) at \(self.position)")
    }

    func pause() {
        player.pause()
        isPaused = true
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        position = seconds
    }

    private func itemChanged(id: String, status: AVPlayerItem.Status, length: Double) {
        guard id == songID else { return }
        switch status {
        case .readyToPlay:
            if length.isFinite { duration = length }
            Self.log.notice("ready \(id, privacy: .public), preview \(length) s")
        case .failed:
            failure = "Die Vorschau lädt gerade nicht."
            isPaused = true
            Self.log.error("failed \(id, privacy: .public)")
        default:
            break
        }
    }

    private func didReachEnd() {
        isPaused = true
        position = duration
        Self.log.notice("end \(self.songID ?? "-", privacy: .public)")
    }

    /// `.playback`, so a preview is heard with the ring switch on silent --
    /// the default category mutes it there.
    private func activateSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Self.log.error("audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
