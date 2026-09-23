import Foundation

/// Who hears a picked section from its start. Only a whole song starts there,
/// and in the app that is Apple Music's with a subscription -- Spotify's embed
/// plays signed out, its excerpt only (`SpotifyEmbedPlayer`).
/// Everyone else gets the service's fixed short preview, wherever that lies.
///
/// Said once, calmly, on the posting screen, so a poster knows before posting
/// rather than finding out from someone else.
enum SectionReach {
    /// The line under the section picker, by where the song comes from. Nil
    /// for SoundCloud: its widget plays every song from the start for everyone,
    /// and the player above the picker says so already.
    static func note(for service: MusicService?) -> String? {
        switch service {
        case .spotify:
            "Diesen Punkt hören andere mit Apple-Music-Abo, wenn Apple den Song hat. Sonst läuft die kurze Standard-Vorschau."
        case nil:
            "Diesen Punkt hören andere nur mit Apple-Music-Abo. Ohne Abo läuft Apples kurze Standard-Vorschau."
        case .soundcloud:
            nil
        }
    }
}
