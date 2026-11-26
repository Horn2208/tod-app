import Foundation

/// Comments, the group chat, and following a group live.
extension AppStore {
    /// The group a submission belongs to. Not `currentGroup`: a song is reached
    /// from the story row too, which spans every group, so "the one selected"
    /// is not a safe answer to "which group is this song in" -- and the comment
    /// would land in the wrong one, or nowhere.
    func group(containing submissionID: Int) -> Group? {
        groups.first { $0.submissions.contains { $0.id == submissionID } }
    }

    /// Says something under a song, as the current user. The repository assigns
    /// the comment's id, where the existing ones are -- the same division of
    /// labour as posting a submission.
    /// False when the comment did not go up (`lastError` says why), so the
    /// field can have the words back.
    @discardableResult
    func addComment(_ text: String, to submissionID: Int) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let groupID = group(containing: submissionID)?.id else { return false }
        var sent = false
        await run {
            try await self.submissionRepo.addComment(
                trimmed,
                authorID: self.profile.id,
                authorName: self.profile.name,
                submissionID: submissionID,
                groupID: groupID
            )
            // A comment lives inside the group's submission, so that group is
            // read back -- that one, not every group with its history.
            sent = true
            self.replace(try await self.groupRepo.fetchGroup(id: groupID))
        }
        return sent
    }

    /// While the app is open on a group: each time something new lands in it
    /// -- a message, a post, a comment -- read the groups again, so it appears
    /// without pulling the list down. Ends when the caller's task does.
    func followGroup() async {
        guard let groupID = currentGroup?.id else { return }
        for await event in chatRepo.groupActivity(groupID: groupID) {
            pendingActivity.append(event)
            guard pendingRead == nil else { continue }
            pendingRead = Task { [weak self] in
                try? await Task.sleep(for: GroupReload.gathering)
                await self?.readPendingActivity(groupID: groupID)
            }
        }
        pendingRead?.cancel()
        pendingRead = nil
        pendingActivity = []
    }

    /// Reads back only what the gathered announcements touched: the chat of
    /// this group, or this one group -- never every group with its history.
    /// Quietly: a read that fails here is no reason to put an error over the
    /// chat -- the next message or a pull tries again.
    private func readPendingActivity(groupID: String) async {
        let events = pendingActivity
        pendingActivity = []
        pendingRead = nil
        switch GroupReload.needed(for: events, me: currentUserID) {
        case .nothing:
            break
        case .messages:
            if let messages = try? await chatRepo.fetchMessages(groupID: groupID) {
                replaceMessages(of: groupID, with: messages)
            }
        case .group:
            if let group = try? await groupRepo.fetchGroup(id: groupID) {
                replace(group)
            }
        }
    }

    private func replaceMessages(of groupID: String, with messages: [ChatMessage]) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[index].chatMessages = messages
    }

    func replace(_ group: Group) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
    }

    func sendMessage(_ text: String, mentionedSubmissionID: Int? = nil) async {
        guard let groupID = currentGroup?.id else { return }
        let message = ChatMessage(
            id: UUID(), authorTag: "DU", authorName: "Du", text: text, isFromCurrentUser: true,
            mentionedSubmissionID: mentionedSubmissionID, authorID: currentUserID, sentAt: now())
        await run {
            try await self.chatRepo.sendMessage(message, groupID: groupID)
            // Only this group's chat, not every group with its history.
            self.replaceMessages(of: groupID, with: try await self.chatRepo.fetchMessages(groupID: groupID))
        }
    }
}
