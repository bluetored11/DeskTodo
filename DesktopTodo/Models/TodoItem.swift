import SwiftData
import Foundation

enum Priority: Int, Codable {
    case none   = 0
    case low    = 1  // 蓝色
    case medium = 2  // 黄色
    case high   = 3  // 红色

    /// Cycles to the next priority: none → low → medium → high → none
    var next: Priority {
        Priority(rawValue: (rawValue + 1) % 4) ?? .none
    }
}

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var order: Int
    var priority: Priority
    var dueDate: Date?
    var reminderOffset: ReminderOffset?
    var reminderID: String?   // UNNotificationRequest identifier (UUID string)

    var list: TodoList?

    @Relationship(deleteRule: .cascade, inverse: \SubTask.item)
    var subtasks: [SubTask]?

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
        self.order = order
        self.priority = .none
    }
}
