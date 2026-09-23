import Foundation
import Testing
@testable import TodApp

@Suite
struct SpotifyProviderPlaybackTests {
    private let source = TrackSource(
        service: .spotify,
        serviceTrackID: "4cOdK2wGLETKBW3PvgPWqT",
        pageURL: URL(string: "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT")!,
        artworkURL: nil
    )

    /// `serviceTrackID` is a full URL for a link-posted SoundCloud track --
    /// exactly what must never reach `spotify:track:\(serviceTrackID)`.
    private let soundCloudSource = TrackSource(
        service: .soundcloud,
        serviceTrackID: "https://soundcloud.com/artist/track",
        pageURL: URL(string: "https://soundcloud.com/artist/track")!,
        artworkURL: nil
    )

    private func signedIn(
        product: String = "premium",
        devices: String = #"{"devices":[{"id":"dev-1","is_active":true}]}"#,
        devicesStatus: Int = 200,
        // Defect 1: what `/v1/me/player/play` itself answers with. Every
        // existing caller wants the default success; the new status-mapping
        // tests below are the only ones that override it.
        playStatus: Int = 200,
        onRequest: (@Sendable (URLRequest) -> Void)? = nil
    ) async throws -> SpotifyProvider {
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: InMemoryTokenStore(),
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { request in
                onRequest?(request)
                let path = request.url?.path ?? ""
                let body: String
                var status = 200
                switch path {
                case "/v1/me": body = #"{"product":"\#(product)"}"#
                case "/v1/me/player/devices":
                    body = devices
                    status = devicesStatus
                case "/v1/me/player/play":
                    body = "{}"
                    status = playStatus
                default: body = "{}"
                }
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { url, _ in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    .queryItems!.first { $0.name == "state" }!.value!
                return URL(string: "todapp://auth/spotify?code=abc123&state=\(state)")!
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
        try await provider.authorize()
        return provider
    }

    /// The whole point of the section picker: 1:22 has to arrive as 82000.
    @Test
    func startsAtTheSectionStart() async throws {
        let box = RequestBox()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/play" { box.store(request) }
        })

        try await provider.play(source, from: TrackSection(start: 82, end: 112))

        let request = try #require(box.value)
        #expect(request.httpMethod == "PUT")
        let payload = try #require(
            try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        )
        #expect(payload["position_ms"] as? Int == 82_000)
        #expect(payload["uris"] as? [String] == ["spotify:track:4cOdK2wGLETKBW3PvgPWqT"])
    }

    @Test
    func withoutASectionItStartsAtZero() async throws {
        let box = RequestBox()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/play" { box.store(request) }
        })

        try await provider.play(source, from: nil)

        let payload = try JSONSerialization.jsonObject(
            with: try #require(box.value).httpBody ?? Data()
        ) as? [String: Any]
        #expect(payload?["position_ms"] as? Int == 0)
    }

    /// Spotify answers 404 NO_ACTIVE_DEVICE, which reads as "not found" and
    /// would otherwise reach the user as a generic failure.
    @Test
    func withoutAnActiveDeviceItSaysSoAndPlaysNothing() async throws {
        let played = Flag()
        let provider = try await signedIn(
            devices: #"{"devices":[]}"#,
            onRequest: { request in
                if request.url?.path == "/v1/me/player/play" { played.raise() }
            }
        )

        await #expect(throws: TodAppError.noActivePlaybackDevice) {
            try await provider.play(source, from: nil)
        }
        #expect(played.isRaised == false)
    }

    /// A 401/403 on the devices check is a rejected session, not a missing
    /// device -- telling someone in that state to open Spotify on a phone or
    /// speaker fixes nothing, they need to sign in again. Pins the shape
    /// change to `hasActiveDevice()`: it must throw `.authorizationFailed`
    /// here rather than fold this into `.noActivePlaybackDevice`.
    @Test
    func aRejectedSessionOnTheDeviceCheckIsReportedAsAnAuthorizationFailure() async throws {
        let played = Flag()
        let provider = try await signedIn(
            devicesStatus: 401,
            onRequest: { request in
                if request.url?.path == "/v1/me/player/play" { played.raise() }
            }
        )

        await #expect(throws: TodAppError.authorizationFailed) {
            try await provider.play(source, from: nil)
        }
        #expect(played.isRaised == false)
    }

    /// Pins the existing behaviour while the shape around it changes: a
    /// device list that decodes fine but reports nothing active is still
    /// "no active device", not an authorization failure.
    @Test
    func anEmptyDeviceListStillMeansNoActiveDevice() async throws {
        let played = Flag()
        let provider = try await signedIn(
            devices: #"{"devices":[]}"#,
            devicesStatus: 200,
            onRequest: { request in
                if request.url?.path == "/v1/me/player/play" { played.raise() }
            }
        )

        await #expect(throws: TodAppError.noActivePlaybackDevice) {
            try await provider.play(source, from: nil)
        }
        #expect(played.isRaised == false)
    }

    /// A free account is stopped before the request, not after Spotify's 403.
    @Test
    func aFreeAccountIsRefusedBeforeAnythingIsSent() async throws {
        let played = Flag()
        let provider = try await signedIn(product: "free", onRequest: { request in
            if request.url?.path == "/v1/me/player/play" { played.raise() }
        })

        await #expect(throws: TodAppError.playbackNotAvailable) {
            try await provider.play(source, from: nil)
        }
        #expect(played.isRaised == false)
    }

    /// The spec calls a 403 here a mistaken reading of the account rather than
    /// a transient failure, so the capability is withdrawn and the button
    /// disappears instead of failing again on the next tap.
    @Test
    func aRefusedPlaybackWithdrawsTheCapability() async throws {
        let provider = SpotifyProvider(
            clientID: "client-123",
            tokenStore: InMemoryTokenStore(),
            exchange: SpotifyTokenExchange(
                clientID: "client-123",
                redirectURI: "todapp://auth/spotify",
                performRequest: { request in
                    (
                        Data(#"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#.utf8),
                        HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!
                    )
                },
                now: { Date(timeIntervalSince1970: 0) }
            ),
            performRequest: { request in
                let path = request.url?.path ?? ""
                let status = path == "/v1/me/player/play" ? 403 : 200
                let body: String
                switch path {
                case "/v1/me": body = #"{"product":"premium"}"#
                case "/v1/me/player/devices": body = #"{"devices":[{"id":"d","is_active":true}]}"#
                default: body = "{}"
                }
                return (
                    Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!
                )
            },
            presentSignIn: { url, _ in
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                    .queryItems!.first { $0.name == "state" }!.value!
                return URL(string: "todapp://auth/spotify?code=abc123&state=\(state)")!
            },
            now: { Date(timeIntervalSince1970: 0) }
        )
        try await provider.authorize()
        #expect(await provider.capabilities.canPlayFullTracks)

        await #expect(throws: TodAppError.playbackNotAvailable) {
            try await provider.play(source, from: nil)
        }

        #expect(await provider.capabilities.canPlayFullTracks == false)
        #expect(await provider.capabilities.canStartAtPosition == false)
    }

    // MARK: - The play call's own response (Defects 1 & 2)
    //
    // Before this fix, only 403 was inspected -- every other non-2xx
    // (401, 404, 500, ...) fell through unchecked and was reported as a
    // successful play with nothing actually sounding.

    /// A 401 on the play call itself is a rejected session -- the same
    /// reading `hasActiveDevice()` already gives its own 401 above.
    @Test
    func aRejectedTokenOnThePlayCallIsReportedAsAnAuthorizationFailure() async throws {
        let provider = try await signedIn(playStatus: 401)

        await #expect(throws: TodAppError.authorizationFailed) {
            try await provider.play(source, from: nil)
        }
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        #expect(try #require(await updates.next()) == nil)
    }

    /// The device that answered the check earlier in `play(_:from:)` can
    /// still vanish in the moment between that check and this call.
    @Test
    func aVanishedDeviceOnThePlayCallIsReportedAsNoActiveDevice() async throws {
        let provider = try await signedIn(playStatus: 404)

        await #expect(throws: TodAppError.noActivePlaybackDevice) {
            try await provider.play(source, from: nil)
        }
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        #expect(try #require(await updates.next()) == nil)
    }

    /// Anything else non-2xx (a Spotify-side hiccup, say) must not be read
    /// as success either.
    @Test
    func aServerErrorOnThePlayCallIsNotReportedAsPlaying() async throws {
        let provider = try await signedIn(playStatus: 500)

        await #expect(throws: TodAppError.trackUnavailable) {
            try await provider.play(source, from: nil)
        }
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        #expect(try #require(await updates.next()) == nil)
    }

    /// Defect 2: a track from another service must never reach Spotify's
    /// play endpoint. `serviceTrackID` on a link-posted SoundCloud track is
    /// a URL, not a Spotify id -- `spotify:track:https://soundcloud.com/...`
    /// is not a URI Spotify would ever accept, and before this fix a
    /// Premium user would see it reported as playing anyway (Defect 1).
    /// This is not the branching on service identity the app forbids in
    /// views -- a provider knowing which sources it owns is exactly its job.
    @Test
    func aTrackFromAnotherServiceIsRefusedBeforeAnythingIsSent() async throws {
        let played = Flag()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/play" { played.raise() }
        })

        await #expect(throws: TodAppError.sourceFromAnotherService) {
            try await provider.play(soundCloudSource, from: nil)
        }
        #expect(played.isRaised == false)
    }

    // MARK: - Timer behaviour (not in the brief's step 1, added to cover the
    // judgement calls the task asks to verify independently).

    /// Starting a second playback must cancel the first section's stop timer,
    /// or an old section could stop a track that was just started.
    @Test
    func startingASecondPlaybackCancelsTheFirstTimer() async throws {
        let stopBox = RequestBox()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/pause" { stopBox.store(request) }
        })

        // A very short first section so its timer would fire quickly if not cancelled.
        try await provider.play(source, from: TrackSection(start: 0, end: 0.01))
        // Immediately start a second, longer section.
        try await provider.play(source, from: TrackSection(start: 0, end: 30))

        // Give the (cancelled) first timer a chance to fire if it were still alive.
        try await Task.sleep(for: .milliseconds(100))

        #expect(stopBox.value == nil)
    }

    /// `stop()` must cancel any pending stop timer, not just issue a pause
    /// request -- otherwise a stray timer could pause playback again later.
    @Test
    func stopCancelsThePendingTimer() async throws {
        let pauseCount = RequestCounter()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/pause" { pauseCount.increment() }
        })

        try await provider.play(source, from: TrackSection(start: 0, end: 0.01))
        await provider.stop()
        let afterExplicitStop = pauseCount.count

        try await Task.sleep(for: .milliseconds(100))

        #expect(afterExplicitStop == 1)
        #expect(pauseCount.count == 1)
    }

    /// Defect 3: `signOut()` used to leave the pending stop timer running
    /// with the credentials it needs already gone, so the timer's own
    /// `stop()` call found no token and silently did nothing -- the track
    /// kept playing past the section the user chose. `signOut()` must send
    /// the pause itself, while it can, and cancel the timer so it cannot
    /// fire a second, useless attempt later. Mirrors `stopCancelsThePendingTimer`
    /// above, but through `signOut()` instead of `stop()`.
    @Test
    func signOutCancelsThePendingTimer() async throws {
        let pauseCount = RequestCounter()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/pause" { pauseCount.increment() }
        })

        try await provider.play(source, from: TrackSection(start: 0, end: 0.01))
        await provider.signOut()
        let afterSignOut = pauseCount.count

        // Give the (should-be-cancelled) timer a chance to fire if it were
        // still alive -- it would find no token and do nothing, which is
        // exactly the silent failure this test guards against.
        try await Task.sleep(for: .milliseconds(100))

        #expect(afterSignOut == 1)
        #expect(pauseCount.count == 1)
    }

    /// A zero-length section must not schedule a timer that immediately fires
    /// an extra pause request.
    @Test
    func aZeroLengthSectionSchedulesNoTimer() async throws {
        let pauseCount = RequestCounter()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/pause" { pauseCount.increment() }
        })

        try await provider.play(source, from: TrackSection(start: 5, end: 5))

        try await Task.sleep(for: .milliseconds(100))

        #expect(pauseCount.count == 0)
    }

    /// "Ganz in Spotify": the song starts at the picked section and plays on
    /// past its end -- the whole song, from where the poster pointed.
    @Test
    func aWholeSongKeepsPlayingPastTheSection() async throws {
        let pauseCount = RequestCounter()
        let playBody = BodyRecorder()
        let provider = try await signedIn(onRequest: { request in
            if request.url?.path == "/v1/me/player/pause" { pauseCount.increment() }
            if request.url?.path == "/v1/me/player/play" { playBody.record(request.httpBody) }
        })

        try await provider.play(source, from: TrackSection(start: 82, end: 82.03), stopsAtSectionEnd: false)
        try await Task.sleep(for: .milliseconds(150))

        #expect(pauseCount.count == 0)
        #expect(playBody.json?["position_ms"] as? Int == 82000)
    }

    // MARK: - Published playback state
    //
    // `TrackPlayerSheet` used to keep its own `@State isPlaying`, flipped
    // only by its own button tap. Spotify's own end-of-section timer above
    // stops playback on the device without the view ever learning -- the
    // button kept reading "Stopp" forever after the music had actually
    // ended. `playbackUpdates()` is the provider saying, on its own, what is
    // really happening; the tests below read directly from that stream
    // rather than guessing at timing.

    /// The stream is consumed directly here (not polled) so this reads the
    /// exact sequence of published states with no timing guesses at all.
    /// `.timeLimit` matters as much as the assertions: a regression that
    /// makes the provider stop publishing turns `updates.next()` into an
    /// unbounded wait, which without this would hang the suite instead of
    /// failing it.
    @Test(.timeLimit(.minutes(1)))
    func playReportsTheTrackAsPlayingAndStopReportsNothingPlaying() async throws {
        let provider = try await signedIn()
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        let initial = try #require(await updates.next())
        #expect(initial == nil)

        try await provider.play(source, from: TrackSection(start: 0, end: 30))
        let afterPlay = try #require(await updates.next())
        #expect(afterPlay == source)

        await provider.stop()
        let afterStop = try #require(await updates.next())
        #expect(afterStop == nil)
    }

    /// The one test that proves the defect was real: nobody calls `stop()`
    /// here. Only Spotify's own end-of-section timer does, and the provider
    /// still has to say so. The section is a few tens of milliseconds long,
    /// not a real song length -- `updates.next()` simply waits for exactly as
    /// long as the timer actually takes, so this needs no sleep of its own.
    /// `.timeLimit` guards the same regression as above: without the fix,
    /// `stop()` never re-publishes and this hangs instead of failing.
    @Test(.timeLimit(.minutes(1)))
    func theEndOfSectionTimerReportsNothingPlayingWithoutAnyoneCallingStop() async throws {
        let provider = try await signedIn()
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        _ = try #require(await updates.next()) // initial: nothing playing

        try await provider.play(source, from: TrackSection(start: 0, end: 0.03))
        let afterPlay = try #require(await updates.next())
        #expect(afterPlay == source)

        // Nothing here calls stop() -- only the timer scheduled by play() does.
        let afterTimer = try #require(await updates.next())
        #expect(afterTimer == nil)
    }

    /// Starting a second track while one is already playing must replace it
    /// as the published state, not sit behind it or blip through `nil` first.
    @Test(.timeLimit(.minutes(1)))
    func startingASecondTrackReplacesTheFirstAsThePlaying() async throws {
        let provider = try await signedIn()
        let secondSource = TrackSource(
            service: .spotify,
            serviceTrackID: "otherTrackID",
            pageURL: URL(string: "https://open.spotify.com/track/otherTrackID")!,
            artworkURL: nil
        )
        var updates = await provider.playbackUpdates().makeAsyncIterator()
        _ = try #require(await updates.next()) // initial: nothing playing

        try await provider.play(source, from: nil)
        let afterFirst = try #require(await updates.next())
        #expect(afterFirst == source)

        try await provider.play(secondSource, from: nil)
        let afterSecond = try #require(await updates.next())
        #expect(afterSecond == secondSource)
    }

    /// Defect 5: a second `playbackUpdates()` call replacing the stored
    /// continuation must not silently orphan whoever was reading the first
    /// stream -- its `for await` has to end, not hang forever. `.timeLimit`
    /// is the actual assertion here: without the fix the loop below never
    /// sees a finish and this test times out instead of failing fast.
    @Test(.timeLimit(.minutes(1)))
    func aSecondPlaybackUpdatesCallEndsTheFirstStream() async throws {
        let provider = try await signedIn()
        let firstStream = await provider.playbackUpdates()

        _ = await provider.playbackUpdates() // replaces the continuation above

        // Consumes the whole stream: with the fix this returns once the
        // first (and only) value -- the initial `nil` -- has been read and
        // the stream then finishes. Without the fix nothing ever finishes it.
        for await _ in firstStream {}
    }
}

/// The body of the last play request, read back as JSON.
private final class BodyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var body: Data?

    func record(_ data: Data?) {
        lock.lock(); defer { lock.unlock() }
        body = data
    }

    var json: [String: Any]? {
        lock.lock(); defer { lock.unlock() }
        return body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
