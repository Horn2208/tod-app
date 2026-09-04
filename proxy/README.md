---
tags: [todapp, proxy]
---

# Musik-Proxy

Hält das Spotify-Client-Secret, damit die App es nicht tun muss. Eine IPA lässt
sich auspacken, ein Worker-Secret nicht — deshalb ist die Verteilung gesperrt,
solange die App das Secret selbst trägt.

Die Funktion beantwortet genau eine Sache:

```
GET /search?q=<query>   ->  Spotifys eigener Suchkörper, unverändert
```

Unverändert, weil die App damit bei einem Mapper und einer aufgezeichneten
Fixture bleibt, statt ein zweites Wire-Format synchron halten zu müssen.

## Warum der Endpunkt öffentlich ist

Ein Schlüssel, mit dem die App sich beim Proxy ausweisen würde, wäre aus der IPA
genauso extrahierbar wie das Secret, das er ersetzen soll — er würde nichts
gewinnen, nur Arbeit machen. Tragbar ist das, weil der Endpunkt so wenig kann:
nur Track-Suche, zehn Treffer, begrenzte Query-Länge. Der schlimmste Fall ist
fremde Track-Suche, nicht die Wiederverwendung einer Kontozugangsdatei. Wenn das
nicht mehr reicht, gehört Cloudflares Rate Limiting davor.

## Deployen

```bash
cd proxy
npx wrangler login
npx wrangler secret put SPOTIFY_CLIENT_ID
npx wrangler secret put SPOTIFY_CLIENT_SECRET
npx wrangler deploy
```

`wrangler secret put` fragt den Wert interaktiv ab; er landet nie in einer Datei
im Repo. `wrangler.toml` enthält deshalb bewusst keine Zugangsdaten.

**Das Secret dabei rotieren.** Das bisherige lag auf Entwicklerrechnern und in
gebauten App-Binaries. Im
[Spotify-Dashboard](https://developer.spotify.com/dashboard) ein neues erzeugen
und nur noch dieses in den Worker geben.

## Testen

```bash
cd proxy
npm test
```

Dreizehn Tests, keine Abhängigkeiten, kein Netz — Node bringt den Runner mit.
`npm install` ist nicht nötig; `wrangler` braucht nur der Deploy.

## Die App umstellen

Erst wenn der Worker steht. In `AppStore.defaultMusicSearch()` wird aus dem
Spotify-Repository das Proxy-Repository:

```swift
static func defaultMusicSearch() -> MusicSearchRepository {
    guard let base = Bundle.main.object(forInfoDictionaryKey: "MusicProxyBaseURL") as? String,
          let url = URL(string: base) else {
        return FailingMusicSearchRepository(error: .searchUnavailable)
    }
    return ProxyMusicSearchRepository(baseURL: url)
}
```

Die Proxy-URL ist kein Geheimnis und gehört als Klartext in `project.yml` unter
`info.properties` (`MusicProxyBaseURL`), nicht in `Secrets.xcconfig`. Danach
können `SpotifyCredentials`, `SpotifyTokenProvider`, `SpotifySearchRepository`
und die beiden `Spotify*`-Schlüssel aus der Info.plist verschwinden — mitsamt
ihren Tests. `SpotifyResponseMapper` bleibt: er verarbeitet weiterhin denselben
Körper, nur kommt er jetzt vom Proxy.
