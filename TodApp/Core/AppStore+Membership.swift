import Foundation

/// Leaving, removing and deleting; reporting and blocking.
extension AppStore {
    // MARK: - Leaving, removing, deleting

    func mayDelete(_ group: Group) -> Bool {
        GroupPermissions.mayDelete(group, asking: currentUserID)
    }

    func mayRemove(_ member: Member, from group: Group) -> Bool {
        GroupPermissions.mayRemove(member.id, from: group, asking: currentUserID)
    }

    /// Whether leaving `group` takes the group with it -- the confirmation
    /// says so before it happens.
    func leaving(_ group: Group) -> GroupPermissions.Leaving {
        GroupPermissions.leaving(group, asking: currentUserID)
    }

    func mayDelete(_ submission: Submission) -> Bool {
        OwnContent.mayDelete(submission, asking: currentUserID, now: now())
    }

    func mayDelete(_ comment: Comment) -> Bool {
        OwnContent.mayDelete(comment, asking: currentUserID)
    }

    func mayDelete(_ message: ChatMessage) -> Bool {
        OwnContent.mayDelete(message, asking: currentUserID)
    }

    /// Out of the group -- and, as its last member and creator, the group
    /// with it. False when the server said no (`lastError` says why).
    @discardableResult
    func leaveGroup(_ groupID: String) async -> Bool {
        guard let group = groups.first(where: { $0.id == groupID }) else { return false }
        let outcome = self.leaving(group)
        var left = false
        await run {
            switch outcome {
            case .leave: try await self.groupRepo.leaveGroup(id: groupID, asking: self.currentUserID)
            case .deleteGroup: try await self.groupRepo.deleteGroup(id: groupID, asking: self.currentUserID)
            }
            left = true
        }
        if left { await drop(groupID) }
        return left
    }

    @discardableResult
    func deleteGroup(_ groupID: String) async -> Bool {
        var deleted = false
        await run {
            try await self.groupRepo.deleteGroup(id: groupID, asking: self.currentUserID)
            deleted = true
        }
        if deleted { await drop(groupID) }
        return deleted
    }

    /// A group this user is no longer in leaves the list at once, without a
    /// round trip; the next group in the list becomes the chosen one.
    private func drop(_ groupID: String) async {
        groups.removeAll { $0.id == groupID }
        if selectedGroupID == groupID { selectedGroupID = nil }
        seasonTotals = []
        myVotes = MyVotes()
        roundScores = []
        revealedVotes = []
        await loadMyVotes()
        await syncReminders()
    }

    @discardableResult
    func removeMember(_ memberID: String, from groupID: String) async -> Bool {
        var removed = false
        await run {
            try await self.groupRepo.removeMember(memberID, from: groupID, asking: self.currentUserID)
            removed = true
            self.replace(try await self.groupRepo.fetchGroup(id: groupID))
        }
        return removed
    }

    /// Takes back this user's song of today, with the ratings it got. A
    /// reminder to post may be due again afterwards.
    @discardableResult
    func deleteSubmission(_ submissionID: Int) async -> Bool {
        guard let groupID = group(containing: submissionID)?.id else { return false }
        var deleted = false
        await run {
            try await self.submissionRepo.deleteSubmission(
                id: submissionID, groupID: groupID, asking: self.currentUserID)
            deleted = true
            self.replace(try await self.groupRepo.fetchGroup(id: groupID))
        }
        if deleted { await syncReminders() }
        return deleted
    }

    @discardableResult
    func deleteComment(_ commentID: Int, on submissionID: Int) async -> Bool {
        guard let groupID = group(containing: submissionID)?.id else { return false }
        var deleted = false
        await run {
            try await self.submissionRepo.deleteComment(
                id: commentID, submissionID: submissionID, groupID: groupID, asking: self.currentUserID)
            deleted = true
            self.replace(try await self.groupRepo.fetchGroup(id: groupID))
        }
        return deleted
    }

    /// Gone from the chat at once; back in its place if the server says no.
    @discardableResult
    func deleteMessage(_ messageID: UUID) async -> Bool {
        guard let groupID = currentGroup?.id,
              let index = groups.firstIndex(where: { $0.id == groupID }),
              let position = groups[index].chatMessages.firstIndex(where: { $0.id == messageID })
        else { return false }
        let message = groups[index].chatMessages.remove(at: position)
        var deleted = false
        await run {
            try await self.chatRepo.deleteMessage(id: messageID, groupID: groupID, asking: self.currentUserID)
            deleted = true
        }
        if !deleted, let index = groups.firstIndex(where: { $0.id == groupID }),
           !groups[index].chatMessages.contains(where: { $0.id == messageID }) {
            let at = min(position, groups[index].chatMessages.count)
            groups[index].chatMessages.insert(message, at: at)
        }
        return deleted
    }

    // MARK: - Reporting and blocking

    func isBlocked(_ userID: String) -> Bool {
        blockedIDs.contains(userID)
    }

    /// Someone else, never oneself.
    func mayReport(_ userID: String) -> Bool {
        userID != currentUserID
    }

    /// False when it did not go up (`lastError` says why).
    @discardableResult
    func report(_ report: Report) async -> Bool {
        var sent = false
        await run {
            try await self.moderationRepo.report(report)
            sent = true
        }
        return sent
    }

    /// Hides the person's songs, comments and messages at once and for good,
    /// in every group; the groups are read back without them.
    @discardableResult
    func block(_ userID: String) async -> Bool {
        guard userID != currentUserID else { return false }
        var blocked = false
        await run {
            try await self.moderationRepo.block(userID)
            blocked = true
            self.blockedIDs.insert(userID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
        return blocked
    }

    @discardableResult
    func unblock(_ userID: String) async -> Bool {
        var unblocked = false
        await run {
            try await self.moderationRepo.unblock(userID)
            unblocked = true
            self.blockedIDs.remove(userID)
            self.groups = try await self.groupRepo.fetchGroups()
        }
        return unblocked
    }
}
