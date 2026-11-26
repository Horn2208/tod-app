import Foundation

/// The daily reminders.
extension AppStore {
    // MARK: - Reminders

    func refreshReminderAuthorization() async {
        reminderAuthorization = await reminders.authorization()
    }

    /// Every start of the app (`RootTabView`): the system's prompt while it
    /// has not been answered -- and then the plan at once -- and otherwise
    /// what the screen should do about it (`ReminderAsk`).
    func askForRemindersAtStart() async -> ReminderAsk {
        await refreshReminderAuthorization()
        let ask = ReminderAsk.atStart(reminderAuthorization)
        if ask == .askSystem { await enableReminders() }
        return ask
    }

    /// Asks the system -- the prompt only ever appears the first time -- and
    /// plans straight away, so the first reminder does not wait for the next
    /// load.
    func enableReminders() async {
        reminderAuthorization = await reminders.requestAuthorization()
        await syncReminders()
    }

    /// Plans the reminders again from the groups as they are now. Called
    /// wherever the answer can change: groups loaded, a song posted, the app
    /// back in front on what may be a new day.
    func syncReminders() async {
        let today = now()
        let statuses = groups.compactMap { group -> DailyReminders.GroupStatus? in
            guard let me = group.members.first(where: { $0.id == currentUserID }) else { return nil }
            return DailyReminders.GroupStatus(
                name: group.name,
                hasPostedToday: Member.hasPosted(on: today, in: me.postedDates))
        }
        let plan = DailyReminders.plan(for: statuses, now: today)
        let previous = reminderSync
        let reminders = reminders
        let sync = Task {
            await previous?.value
            await reminders.replaceAll(with: plan)
        }
        reminderSync = sync
        await sync.value
    }
}
