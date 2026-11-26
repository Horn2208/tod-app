# TodApp

Prototyp einer iOS-App in SwiftUI: Gruppen teilen Songs, bewerten sie und vergleichen sich in einer Rangliste.

Stand dieses Branches: Die App läuft vollständig mit Demo-Daten im Arbeitsspeicher. Es gibt kein Backend und keine Anmeldung, nach einem Neustart sind Änderungen weg.

## Funktionen

Oben wechselst du zwischen zwei Demo-Gruppen. Darunter liegen sechs Tabs:

- **Heute:** Mitglieder der Gruppe und wer heute schon gepostet hat
- **Voten:** Songs von „Aussetzer“ bis „Banger“ bewerten und einen als „Hidden Gem“ markieren
- **Reveal:** Songs der Gruppe zusammen mit der Person, die sie gepostet hat
- **Rangliste:** Punktestand der Mitglieder
- **Chat:** Gruppenchat, neue Nachrichten bleiben bis zum Beenden der App
- **Battle:** Anzeige eines laufenden Battles zwischen zwei Songs

Noch ohne Funktion oder unvollständig:

- Die Knöpfe „+ Song posten“ und „Battle starten“ lösen noch nichts aus.
- Einzelne Bewertungen und die Hidden-Gem-Auswahl bleiben nur in der Ansicht und werden nicht gespeichert.

## Technik

- Swift 6 und SwiftUI, ab iOS 17
- Zustand in einem `@Observable`-`AppStore`
- Datenzugriff über Repository-Protokolle, umgesetzt von `InMemoryRepository`
- Projektbeschreibung für XcodeGen in `project.yml`, das erzeugte `TodApp.xcodeproj` liegt bei
- Tests mit Swift Testing in `TodAppTests/`
- Keine externen Pakete

## Lokal bauen

Voraussetzung: Xcode mit Swift 6 (Xcode 16 oder neuer).

1. Repository klonen und `TodApp.xcodeproj` öffnen.
2. Schema `TodApp` und einen iOS-Simulator wählen.
3. Mit ⌘R starten, mit ⌘U testen.

Auf der Kommandozeile:

```sh
xcodebuild -project TodApp.xcodeproj -scheme TodApp \
  -destination 'generic/platform=iOS Simulator' build
```

Nach Änderungen an `project.yml` das Projekt mit [XcodeGen](https://github.com/yonaskolb/XcodeGen) neu erzeugen:

```sh
xcodegen
```

### Demomodus

Ein eigener Schalter ist nicht nötig: Die App startet immer mit den Demo-Daten aus `TodApp/Core/Repositories/InMemoryRepository.swift`.
