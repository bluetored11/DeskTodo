import SwiftData
import Observation
import Foundation

@MainActor
@Observable
final class TodoStore {
    private let context: ModelContext
    var items: [TodoItem] = []
    var lists: [TodoList] = []
    var selectedListID: UUID? = nil

    init(context: ModelContext) {
        self.context = context
        fetch()
        fetchLists()
    }

    // MARK: - Fetch

    func fetch() {
        let descriptor = FetchDescriptor<TodoItem>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        items = (try? context.fetch(descriptor)) ?? []
    }

    func fetchLists() {
        let descriptor = FetchDescriptor<TodoList>(
            sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)]
        )
        lists = (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Current items (filtered + sorted by priority, completed last)

    var currentItems: [TodoItem] {
        let filtered = items.filter { item in
            selectedListID == nil
                ? item.list == nil
                : item.list?.id == selectedListID
        }
        return filtered.sorted { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            if a.priority.rawValue != b.priority.rawValue {
                return a.priority.rawValue > b.priority.rawValue
            }
            return a.order < b.order
        }
    }

    // MARK: - List CRUD

    func createList(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let maxOrder = lists.map(\.order).max() ?? -1
        let list = TodoList(name: trimmed, order: maxOrder + 1)
        context.insert(list)
        fetchLists()
    }

    func renameList(_ list: TodoList, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        list.name = trimmed
    }

    func deleteList(_ list: TodoList) {
        if selectedListID == list.id { selectedListID = nil }
        context.delete(list)
        fetchLists()
        fetch()
    }

    func moveLists(from source: IndexSet, to destination: Int) {
        var reordered = lists
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, list) in reordered.enumerated() { list.order = index }
        fetchLists()
    }

    // MARK: - Item CRUD

    func addItem(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let maxOrder = (items.map(\.order).max() ?? -1) + 1
        let item = TodoItem(title: trimmed, order: maxOrder)
        if let id = selectedListID,
           let list = lists.first(where: { $0.id == id }) {
            item.list = list
        }
        context.insert(item)
        fetch()
    }

    func toggleComplete(_ item: TodoItem) {
        item.isCompleted.toggle()
        if item.isCompleted { NotificationService.shared.cancelAll(for: item) }
        fetch()
    }

    func updateTitle(_ item: TodoItem, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
    }

    func setPriority(_ item: TodoItem, priority: Priority) {
        item.priority = priority
    }

    func deleteItem(_ item: TodoItem) {
        NotificationService.shared.cancelAll(for: item)
        context.delete(item)
        fetch()
    }

    func move(from source: IndexSet, to destination: Int) {
        var reordered = currentItems
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in reordered.enumerated() { item.order = index }
        fetch()
    }

    // MARK: - Due date (notification wiring added in Task 6)

    func setDueDate(_ item: TodoItem, date: Date, reminderOffset: ReminderOffset?) {
        item.dueDate = date
        item.reminderOffset = reminderOffset
        if reminderOffset != nil {
            Task {
                let granted = await NotificationService.shared.requestPermission()
                if granted { NotificationService.shared.schedule(for: item) }
            }
        } else {
            NotificationService.shared.cancelAll(for: item)
        }
    }

    func clearDueDate(_ item: TodoItem) {
        NotificationService.shared.cancelAll(for: item)
        item.dueDate = nil
        item.reminderOffset = nil
        item.reminderID = nil
    }
}
