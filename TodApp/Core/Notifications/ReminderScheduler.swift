import Foundation
import os
import UserNotifications

/// Whether the system lets this app remind anyone.
enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined, allowed, denied
}

/// The side-effecting half of the reminders. `DailyReminders` decides what
/// should arrive; this hands it to the system. A protocol so the store can be
/// tested with a recorder instead of the real notification centre.
protocol ReminderScheduling: Sendable {
    func authorization() async -> ReminderAuthorization
    /// Shows the system prompt the first time; after that it only reports the
    /// answer given then.
    func requestAuthorization() async -> ReminderAuthorization
    /// Replaces everything planned before with `reminders`.
    func replaceAll(with reminders: [DailyReminders.Reminder]) async
}

struct UserNotificationReminders: ReminderScheduling {
    private static let log = Logger(subsystem: "com.lennetschierhorn.TodApp", category: "reminders")

    func authorization() async -> ReminderAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .allowed
        case .notDetermined: .notDetermined
        case .denied: .denied
        @unknown default: .denied
        }
    }

    func requestAuthorization() async -> ReminderAuthorization {
        do {
            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.log.error("authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
        return await authorization()
    }

    func replaceAll(with reminders: [DailyReminders.Reminder]) async {
        let center = UNUserNotificationCenter.current()
        // Cleared first and regardless of permission: a plan made while
        // reminders were allowed must not outlive a later "no".
        let old = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(DailyReminders.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        guard await authorization() == .allowed else {
            Self.log.info("planned \(reminders.count) reminders, not allowed, none scheduled")
            return
        }
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: reminder.fireAt, repeats: false)
            do {
                try await center.add(UNNotificationRequest(
                    identifier: reminder.id, content: content, trigger: trigger))
            } catch {
                Self.log.error("could not schedule \(reminder.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.log.info("scheduled \(reminders.count) reminders, first \(reminders.first?.id ?? "none", privacy: .public)")
    }
}
