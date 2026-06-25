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
    @ObservationIgnored private var schedulingTasks: [UUID: Task<Void, Never>] = [:]

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
        (list.items ?? []).forEach { NotificationService.shared.cancelAll(for: $0) }
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
        if item.isCompleted {
            item.subtasks?.forEach { $0.isCompleted = true }   // cascade to all sub-tasks
            NotificationService.shared.cancelAll(for: item)
        } else if item.dueDate != nil && item.reminderOffset != nil {
            NotificationService.shared.schedule(for: item)
        }
        fetch()
    }

    func updateTitle(_ item: TodoItem, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        item.title = trimmed
        if item.dueDate != nil && item.reminderOffset != nil {
            NotificationService.shared.schedule(for: item)
        }
    }

    func setPriority(_ item: TodoItem, priority: Priority) {
        item.priority = priority
    }

    func deleteItem(_ item: TodoItem) {
        schedulingTasks[item.id]?.cancel()
        schedulingTasks[item.id] = nil
        NotificationService.shared.cancelAll(for: item)
        item.subtasks?.forEach { context.delete($0) }   // explicit pre-delete (SwiftData cascade backup)
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
            schedulingTasks[item.id]?.cancel()
            let itemID = item.id
            schedulingTasks[item.id] = Task { [weak self] in
                guard let self else { return }
                let granted = await NotificationService.shared.requestPermission()
                guard !Task.isCancelled && granted else {
                    if !granted { item.reminderOffset = nil }
                    return
                }
                NotificationService.shared.schedule(for: item)
                schedulingTasks[itemID] = nil
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

    // MARK: - Sub-task CRUD

    func addSubTask(to item: TodoItem, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let order = item.subtasks?.count ?? 0
        let sub = SubTask(title: trimmed, order: order)
        sub.item = item
        context.insert(sub)
    }

    func toggleSubTask(_ sub: SubTask) {
        sub.isCompleted.toggle()
        autoCompleteParentIfNeeded(sub.item)
    }

    func updateSubTaskTitle(_ sub: SubTask, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        sub.title = trimmed
    }

    func deleteSubTask(_ sub: SubTask) {
        if let item = sub.item,
           let index = item.subtasks?.firstIndex(of: sub) {
            item.subtasks?.remove(at: index)
        }
        context.delete(sub)
    }

    private func autoCompleteParentIfNeeded(_ item: TodoItem?) {
        guard let item,
              let subs = item.subtasks, !subs.isEmpty else { return }
        let allDone = subs.allSatisfy(\.isCompleted)
        if allDone && !item.isCompleted {
            item.isCompleted = true
            NotificationService.shared.cancelAll(for: item)
        }
    }
}
