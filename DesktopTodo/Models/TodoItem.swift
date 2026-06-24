import SwiftData
import Foundation

enum Priority: Int, Codable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
}

@Model
final class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var order: Int
    var priority: Priority

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
        self.order = order
        self.priority = .none
    }
}
