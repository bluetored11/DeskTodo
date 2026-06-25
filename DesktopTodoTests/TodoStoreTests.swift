import XCTest
import SwiftData
@testable import DesktopTodo

@MainActor
final class TodoStoreTests: XCTestCase {
    var container: ModelContainer!
    var store: TodoStore!

    override func setUp() async throws {
        let schema = Schema([TodoItem.self, TodoList.self, SubTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        store = TodoStore(context: container.mainContext)
    }

    override func tearDown() async throws {
        container = nil
        store = nil
    }

    // MARK: - List CRUD

    func testCreateList() {
        store.createList(name: "工作")
        XCTAssertEqual(store.lists.count, 1)
        XCTAssertEqual(store.lists[0].name, "工作")
    }

    func testCreateListTrimsWhitespace() {
        store.createList(name: "  工作  ")
        XCTAssertEqual(store.lists[0].name, "工作")
    }

    func testCreateListIgnoresEmptyName() {
        store.createList(name: "   ")
        XCTAssertEqual(store.lists.count, 0)
    }

    func testRenameList() {
        store.createList(name: "工作")
        let list = store.lists[0]
        store.renameList(list, to: "学习")
        XCTAssertEqual(list.name, "学习")
    }

    func testDeleteList() {
        store.createList(name: "工作")
        let list = store.lists[0]
        store.deleteList(list)
        XCTAssertEqual(store.lists.count, 0)
    }

    func testDeleteListResetsSelectionToInbox() {
        store.createList(name: "工作")
        let list = store.lists[0]
        store.selectedListID = list.id
        store.deleteList(list)
        XCTAssertNil(store.selectedListID)
    }

    // MARK: - currentItems filtering

    func testCurrentItemsShowsInboxWhenNoListSelected() {
        store.addItem(title: "收件箱任务")
        store.createList(name: "工作")
        store.selectedListID = store.lists[0].id
        store.addItem(title: "工作任务")
        store.selectedListID = nil
        XCTAssertEqual(store.currentItems.count, 1)
        XCTAssertEqual(store.currentItems[0].title, "收件箱任务")
    }

    func testCurrentItemsShowsListItems() {
        store.addItem(title: "收件箱任务")
        store.createList(name: "工作")
        store.selectedListID = store.lists[0].id
        store.addItem(title: "工作任务")
        XCTAssertEqual(store.currentItems.count, 1)
        XCTAssertEqual(store.currentItems[0].title, "工作任务")
    }

    func testCurrentItemsSortsByPriorityDescThenCompleted() {
        store.addItem(title: "低优")
        store.addItem(title: "高优")
        store.addItem(title: "已完成")
        let low  = store.currentItems.first(where: { $0.title == "低优" })!
        let high = store.currentItems.first(where: { $0.title == "高优" })!
        let done = store.currentItems.first(where: { $0.title == "已完成" })!
        store.setPriority(low,  priority: .low)
        store.setPriority(high, priority: .high)
        store.toggleComplete(done)
        let sorted = store.currentItems
        XCTAssertEqual(sorted[0].title, "高优")
        XCTAssertEqual(sorted[1].title, "低优")
        XCTAssertEqual(sorted[2].title, "已完成")
    }

    // MARK: - setPriority / Priority.next

    func testPriorityNextCycles() {
        store.addItem(title: "任务")
        let item = store.currentItems[0]
        XCTAssertEqual(item.priority, .none)
        store.setPriority(item, priority: item.priority.next)
        XCTAssertEqual(item.priority, .low)
        store.setPriority(item, priority: item.priority.next)
        XCTAssertEqual(item.priority, .medium)
        store.setPriority(item, priority: item.priority.next)
        XCTAssertEqual(item.priority, .high)
        store.setPriority(item, priority: item.priority.next)
        XCTAssertEqual(item.priority, .none)
    }

    // MARK: - Due date

    func testSetDueDateStoresValues() {
        store.addItem(title: "任务")
        let item = store.currentItems[0]
        let due = Date().addingTimeInterval(3600)
        store.setDueDate(item, date: due, reminderOffset: .oneHour)
        XCTAssertEqual(item.dueDate, due)
        XCTAssertEqual(item.reminderOffset, .oneHour)
    }

    func testClearDueDateNilsAllFields() {
        store.addItem(title: "任务")
        let item = store.currentItems[0]
        item.reminderID = "test-id"
        store.setDueDate(item, date: Date().addingTimeInterval(3600), reminderOffset: .atTime)
        store.clearDueDate(item)
        XCTAssertNil(item.dueDate)
        XCTAssertNil(item.reminderOffset)
        XCTAssertNil(item.reminderID)
    }

    // MARK: - Sub-task CRUD

    func testAddSubTask() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子任务1")
        XCTAssertEqual(item.subtasks?.count, 1)
        XCTAssertEqual(item.subtasks?.first?.title, "子任务1")
        XCTAssertFalse(item.subtasks!.first!.isCompleted)
    }

    func testAddSubTaskTrimsWhitespace() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "  子任务  ")
        XCTAssertEqual(item.subtasks?.first?.title, "子任务")
    }

    func testAddSubTaskIgnoresEmptyTitle() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "   ")
        XCTAssertEqual(item.subtasks?.count ?? 0, 0)
    }

    func testUpdateSubTaskTitle() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "旧标题")
        let sub = item.subtasks!.first!
        store.updateSubTaskTitle(sub, title: "新标题")
        XCTAssertEqual(sub.title, "新标题")
    }

    func testUpdateSubTaskTitleIgnoresEmpty() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "原标题")
        let sub = item.subtasks!.first!
        store.updateSubTaskTitle(sub, title: "   ")
        XCTAssertEqual(sub.title, "原标题")
    }

    func testToggleSubTaskCompletesParentWhenAllDone() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        store.addSubTask(to: item, title: "子2")
        let subs = item.subtasks!
        XCTAssertEqual(subs.count, 2)
        // Toggle first — parent should stay incomplete
        store.toggleSubTask(subs[0])
        XCTAssertFalse(item.isCompleted)
        // Toggle second — all done, parent should auto-complete
        store.toggleSubTask(subs[1])
        XCTAssertTrue(item.isCompleted)
    }

    func testToggleSubTaskDoesNotAutoUncompleteParent() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        store.addSubTask(to: item, title: "子2")
        let subs = item.subtasks!
        // Complete all → parent auto-completes
        store.toggleSubTask(subs[0])
        store.toggleSubTask(subs[1])
        XCTAssertTrue(item.isCompleted)
        // Uncomplete one → parent stays completed (no reverse link)
        store.toggleSubTask(subs[0])
        XCTAssertTrue(item.isCompleted)
    }

    func testToggleCompleteParentCascadesToSubtasks() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        store.addSubTask(to: item, title: "子2")
        store.toggleComplete(item)
        XCTAssertTrue(item.isCompleted)
        XCTAssertTrue(item.subtasks!.allSatisfy(\.isCompleted))
    }

    func testToggleCompleteParentUncompleteDoesNotRevertSubtasks() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        store.toggleComplete(item)   // complete → sub also completed
        store.toggleComplete(item)   // uncomplete → sub stays completed
        XCTAssertFalse(item.isCompleted)
        XCTAssertTrue(item.subtasks!.first!.isCompleted)
    }

    func testDeleteSubTask() {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        let sub = item.subtasks!.first!
        store.deleteSubTask(sub)
        XCTAssertEqual(item.subtasks?.count ?? 0, 0)
    }

    func testDeleteItemAlsoDeletesSubtasks() throws {
        store.addItem(title: "父任务")
        let item = store.currentItems[0]
        store.addSubTask(to: item, title: "子1")
        store.deleteItem(item)
        // Verify sub-tasks are gone from the context
        let subDescriptor = FetchDescriptor<SubTask>()
        let remainingSubs = try container.mainContext.fetch(subDescriptor)
        XCTAssertEqual(remainingSubs.count, 0)
    }
}
