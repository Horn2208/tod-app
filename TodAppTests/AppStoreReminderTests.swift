import Foundation
import Testing
@testable import TodApp

/// Records what the store hands over instead of scheduling anything.
actor RecordingReminders: ReminderScheduling {
    private(set) var plans: [[DailyReminders.Reminder]] = []
    private var status: ReminderAuthorization

    init(status: ReminderAuthorization = .notDetermined) { self.status = status }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> ReminderAuthorization {
        if status == .notDetermined { status = .allowed }
        return status
    }

    func replaceAll(with reminders: [DailyReminders.Reminder]) async {
        plans.append(reminders)
    }

    var lastIDs: [String] { plans.last?.map(\.id) ?? [] }
}

@MainActor
@Suite
struct AppStoreReminderTests {
    /// Nine in the morning of the real today. The seed dates its posts by the
    /// real calendar day, so the store's clock has to be on the same one.
    private let morning = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: Date())!

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: morning)!
    }

    private func makeStore(_ reminders: RecordingReminders) -> AppStore {
        let repo = InMemoryRepository()
        let morning = morning
        return AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: reminders,
            now: { morning }
        )
    }

    private func isOpen(_ group: Group) -> Bool {
        guard let me = group.members.first(where: { $0.isCurrentUser }) else { return false }
        return !Member.hasPosted(on: morning, in: me.postedDates)
    }

    @Test
    func loadingGroupsPlansTodaysPostReminderWhileAGroupIsOpen() async throws {
        let reminders = RecordingReminders()
        let store = makeStore(reminders)

        await store.loadGroups()

        try #require(store.groups.contains(where: isOpen))
        #expect(await reminders.lastIDs.contains(DailyReminders.id(.post, on: morning)))
    }

    /// The prompt's rule: once someone has posted, the 15:00 reminder for
    /// today must not arrive. Posting in every open group has to take it back.
    @Test
    func postingEverywhereTakesTodaysPostReminderBack() async throws {
        let reminders = RecordingReminders()
        let store = makeStore(reminders)
        await store.loadGroups()

        let open = store.groups.filter(isOpen).map(\.id)
        try #require(!open.isEmpty)
        for id in open {
            store.selectGroup(id)
            await store.post(candidate: TrackCandidate(
                title: "Genesis", artist: "Justice",
                source: TrackSource(
                    service: .spotify, serviceTrackID: "t\(id)",
                    pageURL: URL(string: "https://open.spotify.com/track/t\(id)")!),
                durationSeconds: nil))
        }

        let planned = await reminders.lastIDs
        #expect(!planned.contains(DailyReminders.id(.post, on: morning)))
        #expect(planned.contains(DailyReminders.id(.vote, on: morning)))
        #expect(planned.contains(DailyReminders.id(.post, on: tomorrow)))
    }

    @Test
    func switchingRemindersOnAsksAndPlansAtOnce() async {
        let reminders = RecordingReminders()
        let store = makeStore(reminders)
        await store.loadGroups()
        let plansBefore = await reminders.plans.count

        await store.enableReminders()

        #expect(store.reminderAuthorization == .allowed)
        #expect(await reminders.plans.count == plansBefore + 1)
    }
}

/// Asked at every start: the system's prompt once, then the way to the
/// settings for as long as notifications are off.
@MainActor
@Suite
struct ReminderAskAtStartTests {
    @Test
    func theRuleFollowsTheAnswer() {
        #expect(ReminderAsk.atStart(.notDetermined) == .askSystem)
        #expect(ReminderAsk.atStart(.denied) == .pointToSettings)
        #expect(ReminderAsk.atStart(.allowed) == .nothing)
    }

    private func store(_ reminders: RecordingReminders) -> AppStore {
        let repo = InMemoryRepository()
        return AppStore(
            groupRepo: repo, submissionRepo: repo, voteRepo: repo,
            chatRepo: repo, battleRepo: repo,
            provider: FakeMusicProvider(capabilities: .none),
            reminders: reminders)
    }

    /// Unanswered: the prompt, and the plan straight after a yes.
    @Test
    func unansweredItAsksTheSystemAndPlans() async {
        let reminders = RecordingReminders(status: .notDetermined)
        let store = store(reminders)

        #expect(await store.askForRemindersAtStart() == .askSystem)
        #expect(store.reminderAuthorization == .allowed)
        #expect(await reminders.plans.count == 1)
    }

    /// Switched off: no prompt iOS would not show anyway, the settings instead.
    @Test
    func switchedOffItPointsToTheSettings() async {
        let reminders = RecordingReminders(status: .denied)
        let store = store(reminders)

        #expect(await store.askForRemindersAtStart() == .pointToSettings)
        #expect(await reminders.plans.isEmpty)
    }

    @Test
    func allowedItAsksNothing() async {
        let store = store(RecordingReminders(status: .allowed))

        #expect(await store.askForRemindersAtStart() == .nothing)
    }
}
