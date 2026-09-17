import Foundation

/// Who hears a picked section from its start. Only a whole song starts there:
/// Spotify's with Premium in the app, Apple Music's with a subscription.
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
            "Diesen Punkt hören andere nur mit Spotify Premium oder Apple-Music-Abo. Ohne Abo läuft die kurze Standard-Vorschau des Dienstes."
        case nil:
            "Diesen Punkt hören andere nur mit Apple-Music-Abo. Ohne Abo läuft Apples kurze Standard-Vorschau."
        case .soundcloud:
            nil
        }
    }
}
