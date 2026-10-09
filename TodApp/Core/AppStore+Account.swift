import Foundation
import os

/// Signing in and out, invite links, saved songs, and the Spotify connection.
extension AppStore {
    func restoreSession() async {
        // `defer` rather than an assignment at the end: this must flip to
        // false on every exit from this function, including one added later
        // that returns early or throws, not just the happy path visible today.
        defer { isRestoringSession = false }
        let restored = await accountService.restore()
        await provider.restore()
        await refreshSpotify()
        if let restored {
            await begin(restored)
        }
    }

    /// Everything that follows from someone being signed in: who they are,
    /// and what is theirs.
    private func begin(_ user: AccountUser) async {
        hasLeft = false
        account = user
        loadSavedSongs()
        if profile.id != user.id {
            profile = Self.placeholderProfile(for: user.id, isPremium: profile.isPremium)
        }
        await loadProfile()
        await loadGroups()
        // A link tapped before there was an account goes on from here.
        if let code = pendingInviteCode { await joinByLink(code) }
    }

    // MARK: - Invite links

    /// Takes `todapp://join/<code>`: joins at once when signed in, otherwise
    /// right after signing in. False for any other link, which is someone
    /// else's to handle.
    @discardableResult
    func openInvite(_ url: URL) -> Bool {
        guard let code = InviteCode.code(from: url) else { return false }
        if isSignedIn && !isRestoringSession {
            Task { await joinByLink(code) }
        } else {
            pendingInviteCode = code
        }
        return true
    }

    private func joinByLink(_ code: String) async {
        pendingInviteCode = nil
        if await joinGroup(code: code) { joinedByLink = currentGroup?.name }
    }

    /// Signs in with what Sign in with Apple handed over, and loads the groups
    /// straight away. Loading lives here, not in a view's `.task`: that once
    /// ran for the view's lifetime only, and a fresh sign-in reached the tab
    /// bar with nothing in it.
    func signInWithApple(idToken: String, nonce: String, name: String?) async {
        do {
            let user = try await accountService.signInWithApple(
                idToken: idToken, nonce: nonce, name: name)
            await begin(user)
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .accountSignInFailed
        }
    }

    /// Signs in with Spotify, then connects Spotify for playing. The second
    /// page runs on the Spotify session the first one made, so it asks for
    /// consent at most, never for the password again. Closing it leaves the
    /// account signed in; Spotify can be connected in the profile later.
    /// Secures an account made without sign-in: Apple becomes the way back
    /// into it. False when that did not happen (`lastError` says why).
    @discardableResult
    func linkApple(idToken: String, nonce: String) async -> Bool {
        guard account?.isAnonymous == true else { return false }
        do {
            account = try await accountService.linkApple(idToken: idToken, nonce: nonce)
            return true
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .accountSignInFailed
        }
        return false
    }

    func signInWithSpotify() async {
        do {
            let user = try await accountService.signInWithSpotify()
            await begin(user)
        } catch TodAppError.authorizationCancelled {
            // Closing Spotify's page is a decision, not an error.
            return
        } catch TodAppError.spotifyNotRegistered {
            lastError = .spotifyNotRegistered
            return
        } catch {
            lastError = .accountSignInFailed
            return
        }
        await connectSpotify()
    }

    /// "Ohne Anmeldung": an account that lives on this phone only.
    func continueWithoutAccount() async {
        do {
            let user = try await accountService.signInAnonymously()
            await begin(user)
        } catch {
            lastError = .accountSignInFailed
        }
    }

    /// Leaves the app on this phone: the account, and Spotify with it -- a
    /// phone handed on must not keep someone else's music login.
    func signOut() async {
        await accountService.signOut()
        await forgetTheAccount()
    }

    /// Deletes the account on the server; then this phone forgets it, as on
    /// signing out. False, with `lastError` saying why, when the server did
    /// not delete -- and then nothing here is thrown away.
    func deleteAccount() async -> Bool {
        var deleted = false
        await run {
            try await self.accountService.deleteAccount()
            deleted = true
        }
        guard deleted else { return false }
        // Noted songs are this account's too; they go with it.
        do {
            try savedSongStorage.delete(for: currentUserID)
        } catch {
            Self.log.error("saved songs not deleted: \(error.localizedDescription, privacy: .public)")
        }
        await forgetTheAccount()
        return true
    }

    private func forgetTheAccount() async {
        hasLeft = true
        account = nil
        groups = []
        hasLoadedGroups = false
        groupsLoadFailed = false
        selectedGroupID = nil
        profile = Self.placeholderProfile(for: LocalAccountService.user.id)
        myVotes = MyVotes()
        roundScores = []
        revealedVotes = []
        seasonTotals = []
        blockedIDs = []
        pendingInviteCode = nil
        savedSongs = []
        await disconnectSpotify()
    }

    // MARK: - Saved songs

    func isSaved(_ candidate: TrackCandidate) -> Bool {
        savedSongs.contains { $0.id == candidate.id }
    }

    /// The bookmark beside a hit: notes the song, or forgets it again.
    func toggleSaved(_ candidate: TrackCandidate) {
        if isSaved(candidate) {
            removeSaved(id: candidate.id)
        } else {
            keepSavedSongs(SavedSongs.adding(SavedSong(candidate, savedAt: now()), to: savedSongs))
        }
    }

    func removeSaved(id: String) {
        keepSavedSongs(SavedSongs.removing(id: id, from: savedSongs))
    }

    /// Shows the list at once and writes it behind. A failed write is logged,
    /// not shown: the list on screen is right for this session, and a note
    /// for later is not worth an alert.
    private func keepSavedSongs(_ songs: [SavedSong]) {
        savedSongs = songs
        do {
            try savedSongStorage.save(songs, for: currentUserID)
        } catch {
            Self.log.error("saved songs not written: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadSavedSongs() {
        do {
            savedSongs = try savedSongStorage.load(for: currentUserID)
        } catch {
            Self.log.error("saved songs not read: \(error.localizedDescription, privacy: .public)")
            savedSongs = []
        }
    }

    func connectSpotify() async {
        do {
            try await provider.authorize()
        } catch TodAppError.authorizationCancelled {
            // Declining is a decision, not something to shout about.
        } catch let error as TodAppError {
            lastError = error
        } catch {
            lastError = .network(underlying: error)
        }
        await refreshSpotify()
    }

    func disconnectSpotify() async {
        await provider.signOut()
        await refreshSpotify()
    }

    private func refreshSpotify() async {
        isSpotifyConnected = await provider.isAuthorized
        capabilities = await provider.capabilities
    }
}
