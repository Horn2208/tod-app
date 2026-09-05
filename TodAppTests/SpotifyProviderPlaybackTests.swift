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

    private func signedIn(
        product: String = "premium",
        devices: String = #"{"devices":[{"id":"dev-1","is_active":true}]}"#,
        devicesStatus: Int = 200,
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
}
