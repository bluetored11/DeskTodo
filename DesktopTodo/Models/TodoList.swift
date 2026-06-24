import SwiftData
import Foundation

@Model
final class TodoList {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.list)
    var items: [TodoItem]?

    init(name: String, order: Int = 0) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.createdAt = Date()
    }
}
