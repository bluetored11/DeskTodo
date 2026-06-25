import SwiftData
import Foundation

@Model
final class SubTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var order: Int          // creation-order index; drag-reorder not exposed in v1.2
    var createdAt: Date

    var item: TodoItem?     // back-reference to parent; relationship declared on TodoItem side

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.order = order
        self.createdAt = Date()
    }
}
