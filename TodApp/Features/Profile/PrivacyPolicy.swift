import Foundation

/// TodApp's privacy policy, written from what the app actually does: which
/// data, where it goes, why, and how to get rid of it. Shown in the profile;
/// the App Store also wants it at a public web address.
///
/// Two things only the owner can fill in are placeholders until then --
/// `isComplete` stays false, and a test says so, so a half-finished policy
/// does not go out unnoticed.
enum PrivacyPolicy {
    /// The person responsible under the GDPR, with a postal address.
    static let controller = "[Name und Anschrift eintragen]"
    /// Where people write to with questions and requests.
    static let contact = "[E-Mail-Adresse eintragen]"
    static let updated = "24. September 2026"

    static var isComplete: Bool {
        !(controller + contact).contains("eintragen]")
    }

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }

    static let sections: [Section] = [
        Section(title: "Wer verantwortlich ist", body: """
        Verantwortlich für die Verarbeitung deiner Daten in TodApp ist \(controller). \
        Bei Fragen zum Datenschutz oder um deine Rechte auszuüben, schreib an \(contact).
        """),
        Section(title: "Was TodApp speichert", body: """
        Für dein Konto: eine Konto-ID und, je nach Anmeldung, die E-Mail-Adresse, die Apple \
        oder Spotify uns dabei übermitteln (bei Apple auf Wunsch eine anonyme Weiterleitungsadresse). \
        Ohne Anmeldung gibt es nur die Konto-ID. \
        Für dein Profil: deinen Namen und, wenn du eins hochlädst, dein Profilbild. \
        In deinen Gruppen: die Gruppen selbst mit Namen, Symbol und Bild, deine geposteten Songs \
        (Titel, Künstler, Cover-Adresse, Link oder Apple-Music-ID, gewählter Abschnitt, Zeitpunkt), \
        deine Bewertungen, Hidden Gems, Kommentare und Chat-Nachrichten.
        """),
        Section(title: "Wozu", body: """
        Ausschließlich, um die App zu betreiben: damit du dich anmelden kannst und deine Gruppe \
        deine Songs, Bewertungen und Nachrichten sieht. Rechtsgrundlage ist die Erfüllung des \
        Nutzungsvertrags (Art. 6 Abs. 1 lit. b DSGVO). Es gibt keine Werbung, kein Tracking, \
        keine Analyse-Werkzeuge und keinen Verkauf von Daten.
        """),
        Section(title: "Wo die Daten liegen", body: """
        Konto und Gruppendaten liegen bei Supabase (Supabase Inc.) als Auftragsverarbeiter, in einem \
        Rechenzentrum in der EU (Irland). Sehen können sie nur die Mitglieder der jeweiligen Gruppe; \
        das ist in der Datenbank selbst durchgesetzt.
        """),
        Section(title: "Apple", body: """
        Mit „Mit Apple fortfahren“ meldest du dich über Apple an. Suchst du ohne Spotify nach Songs, \
        gehen deine Suchbegriffe an Apples öffentlichen Musikkatalog. Verbindest du Apple Music, \
        fragt TodApp dein Abo ab und spielt Songs über Apple Music; das regelt Apples eigene \
        Datenschutzerklärung.
        """),
        Section(title: "Spotify", body: """
        Mit „Mit Spotify fortfahren“ oder der Spotify-Verbindung im Profil meldest du dich bei Spotify an. \
        TodApp erhält dann Zugriff auf Suche und, mit Premium, auf die Wiedergabe in deiner Spotify-App. \
        Die Zugangsschlüssel bleiben auf deinem iPhone (im Schlüsselbund). Fügst du einen Spotify-Link \
        ein, ruft TodApp dessen öffentliche Angaben (Titel, Künstler, Länge, Cover) bei Spotify ab. \
        Spotifys Player in der App läuft ohne deine Anmeldung. Für Spotify gilt Spotifys eigene \
        Datenschutzerklärung.
        """),
        Section(title: "Auf deinem iPhone", body: """
        Erinnerungen plant TodApp nur auf deinem Gerät; dafür werden keine Daten verschickt. \
        Die Anmeldung und die Spotify-Verbindung liegen im Schlüsselbund deines iPhones.
        """),
        Section(title: "Wie lange", body: """
        Solange dein Konto besteht. Im Profil kannst du es jederzeit löschen: Dann werden Konto, \
        Profil, Bild, deine Songs, Bewertungen, Hidden Gems, Kommentare und Nachrichten gelöscht. \
        Gruppen, die du gegründet hast, bleiben für die anderen Mitglieder bestehen.
        """),
        Section(title: "Deine Rechte", body: """
        Du hast das Recht auf Auskunft, Berichtigung, Löschung, Einschränkung der Verarbeitung, \
        Datenübertragbarkeit und Widerspruch. Schreib dafür an \(contact). Außerdem kannst du dich \
        bei einer Datenschutz-Aufsichtsbehörde beschweren, etwa der deines Wohnorts.
        """),
    ]
}
