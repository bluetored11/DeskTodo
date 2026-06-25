import UserNotifications
import Foundation

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    /// Returns false when running outside a proper app bundle (e.g., unit tests),
    /// where UNUserNotificationCenter would throw NSInternalInconsistencyException.
    private var isAvailable: Bool {
        !(Bundle.main.bundleIdentifier ?? "").isEmpty
    }

    func requestPermission() async -> Bool {
        guard isAvailable else { return false }
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(for item: TodoItem) {
        guard isAvailable else { return }
        guard let dueDate = item.dueDate,
              let offset = item.reminderOffset else { return }

        cancelAll(for: item)   // remove stale request first

        let fireDate = dueDate.addingTimeInterval(-offset.secondsBefore)
        guard fireDate > Date() else { return }   // silently ignore past dates

        let content = UNMutableNotificationContent()
        content.title = "⏰ 任务提醒"
        content.body  = "「\(item.title)」截止时间到了"
        content.sound = .default
        if let listName = item.list?.name { content.subtitle = listName }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let id      = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        item.reminderID = id
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func cancel(id: String) {
        guard isAvailable else { return }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll(for item: TodoItem) {
        if let id = item.reminderID {
            cancel(id: id)
            item.reminderID = nil
        }
    }
}
