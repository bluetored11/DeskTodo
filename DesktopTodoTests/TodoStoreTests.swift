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
}
