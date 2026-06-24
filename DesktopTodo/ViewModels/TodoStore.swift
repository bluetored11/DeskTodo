import SwiftData
import Observation
import Foundation

@MainActor
@Observable
final class TodoStore {
    private let context: ModelContext
    var items: [TodoItem] = []

    init(context: ModelContext) {
        self.context = context
        fetch()
    }

    func fetch() {
        let descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        items = (try? context.fetch(descriptor)) ?? []
    }

    func addItem(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let maxOrder = items.map(\.order).max() ?? -1
        let item = TodoItem(title: trimmed, order: maxOrder + 1)
        context.insert(item)
        fetch()
    }

    func toggleComplete(_ item: TodoItem) {
        item.isCompleted.toggle()
        fetch()
    }

    func updateTitle(_ item: TodoItem, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
    }

    func deleteItem(_ item: TodoItem) {
        context.delete(item)
        fetch()
    }

    func move(from source: IndexSet, to destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() {
            item.order = index
        }
        fetch()
    }
}
