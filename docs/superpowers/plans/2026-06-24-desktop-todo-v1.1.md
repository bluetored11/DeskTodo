
# DesktopTodo v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add multi-list management, task priority UI, due dates, and user-notification reminders to DesktopTodo.

**Architecture:** Extend the existing single-store pattern — `TodoStore` gains list CRUD and `currentItems` filtering; a new `NotificationService` wraps `UserNotifications`; `SidebarView` is rewritten for multi-list selection; `TaskRowView` gains a priority circle and a date-picker popover.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), SwiftData (automatic lightweight migration), UserNotifications, XCTest

## Global Constraints

- macOS 14.0+ deployment target
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: complete`
- Bundle ID: `com.bluetored.DesktopTodo`
- SwiftData for all persistence — no manual save needed, no iCloud sync
- XcodeGen 2.45.4: run `xcodegen generate` after every `project.yml` change

---

## File Map

| Path | Type | Purpose |
|------|------|---------|
| `DesktopTodo/Models/TodoList.swift` | New | SwiftData model for a named todo list |
| `DesktopTodo/Models/ReminderOffset.swift` | New | Reminder-timing enum |
| `DesktopTodo/Services/NotificationService.swift` | New | `UserNotifications` wrapper |
| `DesktopTodo/Views/DueDatePopoverView.swift` | New | Date-picker + reminder-selector popover |
| `DesktopTodoTests/TodoStoreTests.swift` | New | XCTest unit tests for `TodoStore` |
| `project.yml` | Modified | Add `DesktopTodoTests` unit-test target |
| `DesktopTodo/Models/TodoItem.swift` | Modified | Add `dueDate`, `reminderOffset`, `reminderID`, `list` |
| `DesktopTodo/App/DesktopTodoApp.swift` | Modified | Add `TodoList` to schema |
| `DesktopTodo/ViewModels/TodoStore.swift` | Modified | List CRUD, `currentItems`, `setDueDate`, `clearDueDate`, notification wiring |
| `DesktopTodo/Views/SidebarView.swift` | Modified | Full rewrite for multi-list |
| `DesktopTodo/Views/TaskListView.swift` | Modified | `currentItems`, dynamic title |
| `DesktopTodo/Views/TaskRowView.swift` | Modified | Priority circle, date label/icon, popover entry |
| `DesktopTodo/Views/ContentView.swift` | Modified | Pass `selectedListID` binding to `SidebarView` |

---

### Task 1: Data foundation

**Files:**
- Create: `DesktopTodo/Models/TodoList.swift`
- Create: `DesktopTodo/Models/ReminderOffset.swift`
- Modify: `DesktopTodo/Models/TodoItem.swift`
- Modify: `DesktopTodo/App/DesktopTodoApp.swift`
- Modify: `project.yml`
- Create: `DesktopTodoTests/TodoStoreTests.swift` (placeholder)

**Interfaces:**
- Produces: `TodoList(name:order:)`, `ReminderOffset` enum with `secondsBefore` and `displayName`, `TodoItem.list`, `TodoItem.dueDate`, `TodoItem.reminderOffset`, `TodoItem.reminderID`, `Priority.next`, `Priority.color`

- [ ] **Step 1: Add test target to project.yml**

Replace the full contents of `project.yml`:

```yaml
name: DesktopTodo
options:
  bundleIdPrefix: com.bluetored
  deploymentTarget:
    macOS: "14.0"

settings:
  SWIFT_VERSION: "6.0"
  MACOSX_DEPLOYMENT_TARGET: "14.0"

targets:
  DesktopTodo:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: DesktopTodo
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.bluetored.DesktopTodo
      SWIFT_VERSION: "6.0"
      INFOPLIST_FILE: DesktopTodo/Info.plist
      PRODUCT_NAME: DesktopTodo
      ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
      ENABLE_HARDENED_RUNTIME: YES
      SWIFT_STRICT_CONCURRENCY: complete
  DesktopTodoTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: DesktopTodoTests
    dependencies:
      - target: DesktopTodo
    settings:
      SWIFT_VERSION: "6.0"
      SWIFT_STRICT_CONCURRENCY: complete
```

- [ ] **Step 2: Create test directory and placeholder**

```bash
mkdir -p DesktopTodoTests
```

Create `DesktopTodoTests/TodoStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import DesktopTodo

// Tests added in Tasks 2 and 5
```

- [ ] **Step 3: Regenerate xcodeproj**

```bash
xcodegen generate
```

Expected output: `Project written to DesktopTodo.xcodeproj`

- [ ] **Step 4: Create ReminderOffset.swift**

Create `DesktopTodo/Models/ReminderOffset.swift`:

```swift
import Foundation

enum ReminderOffset: Int, Codable {
    case atTime    = 0    // 到点提醒
    case oneHour   = 60   // 提前 1 小时（单位：分钟）
    case oneDay    = 1440 // 提前 1 天

    var displayName: String {
        switch self {
        case .atTime:  return "到点提醒"
        case .oneHour: return "提前 1 小时"
        case .oneDay:  return "提前 1 天"
        }
    }

    /// 提前于截止时间的秒数
    var secondsBefore: TimeInterval {
        TimeInterval(rawValue) * 60
    }
}
```

- [ ] **Step 5: Create TodoList.swift**

Create `DesktopTodo/Models/TodoList.swift`:

```swift
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
```

- [ ] **Step 6: Update TodoItem.swift**

Replace `DesktopTodo/Models/TodoItem.swift` with:

```swift
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

    init(title: String, order: Int = 0) {
        self.id = UUID()
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
        self.order = order
        self.priority = .none
    }
}
```

- [ ] **Step 7: Update DesktopTodoApp.swift schema**

In `DesktopTodo/App/DesktopTodoApp.swift`, change:

```swift
let schema = Schema([TodoItem.self])
```

to:

```swift
let schema = Schema([TodoItem.self, TodoList.self])
```

- [ ] **Step 8: Build and verify no crash**

Build in Xcode (⌘B). Launch the app — existing inbox tasks must appear unchanged. SwiftData auto-migrates the new optional fields (all nil by default).

Expected: build succeeds, app launches without crash, existing data preserved.

- [ ] **Step 9: Commit**

```bash
git add project.yml DesktopTodo/Models/TodoList.swift DesktopTodo/Models/ReminderOffset.swift \
        DesktopTodo/Models/TodoItem.swift DesktopTodo/App/DesktopTodoApp.swift DesktopTodoTests/
git commit -m "feat: TodoList model, ReminderOffset enum, TodoItem v1.1 fields, test target"
```

---

### Task 2: TodoStore list management

**Files:**
- Modify: `DesktopTodo/ViewModels/TodoStore.swift`
- Modify: `DesktopTodoTests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: `TodoList(name:order:)`, `TodoItem.list`, `ReminderOffset`, `Priority.next`
- Produces:
  - `store.lists: [TodoList]`
  - `store.selectedListID: UUID?` (nil = inbox)
  - `store.currentItems: [TodoItem]` (filtered + sorted)
  - `store.createList(name: String)`
  - `store.renameList(_ list: TodoList, to name: String)`
  - `store.deleteList(_ list: TodoList)`
  - `store.moveLists(from: IndexSet, to: Int)`
  - `store.setPriority(_ item: TodoItem, priority: Priority)`
  - `store.setDueDate(_ item: TodoItem, date: Date, reminderOffset: ReminderOffset?)` (stub; notifications wired in Task 6)
  - `store.clearDueDate(_ item: TodoItem)`

- [ ] **Step 1: Write failing tests**

Replace `DesktopTodoTests/TodoStoreTests.swift`:

```swift
import XCTest
import SwiftData
@testable import DesktopTodo

@MainActor
final class TodoStoreTests: XCTestCase {
    var container: ModelContainer!
    var store: TodoStore!

    override func setUp() async throws {
        let schema = Schema([TodoItem.self, TodoList.self])
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
```

- [ ] **Step 2: Run tests — expect failure**

In Xcode: Product → Test (⌘U).
Expected: compilation errors — `createList`, `currentItems`, etc. don't exist yet.

- [ ] **Step 3: Implement TodoStore**

Replace `DesktopTodo/ViewModels/TodoStore.swift`:

```swift
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
    }

    func clearDueDate(_ item: TodoItem) {
        item.dueDate = nil
        item.reminderOffset = nil
        item.reminderID = nil
    }
}
```

- [ ] **Step 4: Run tests — expect all pass**

In Xcode: Product → Test (⌘U).
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add DesktopTodo/ViewModels/TodoStore.swift DesktopTodoTests/TodoStoreTests.swift
git commit -m "feat: TodoStore list management, currentItems filtering + priority sorting"
```

---

### Task 3: SidebarView multi-list

**Files:**
- Modify: `DesktopTodo/Views/SidebarView.swift`
- Modify: `DesktopTodo/Views/ContentView.swift`
- Modify: `DesktopTodo/Views/TaskListView.swift`

**Interfaces:**
- Consumes: `store.lists`, `store.selectedListID`, `store.items`, all list CRUD methods from Task 2
- Produces: updated `SidebarView(selectedListID:)` init

- [ ] **Step 1: Replace SidebarView.swift**

```swift
import SwiftUI

struct SidebarView: View {
    @Environment(TodoStore.self) private var store
    @Binding var selectedListID: UUID?

    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var renamingList: TodoList? = nil
    @State private var renameText = ""
    @State private var listToDelete: TodoList? = nil

    var body: some View {
        List(selection: $selectedListID) {
            inboxRow

            if !store.lists.isEmpty {
                Divider()
                ForEach(store.lists) { list in
                    listRow(list)
                }
                .onMove { source, destination in
                    store.moveLists(from: source, to: destination)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .navigationTitle("DesktopTodo")
        .safeAreaInset(edge: .bottom) { addListButton }
        .alert("删除清单", isPresented: .init(
            get: { listToDelete != nil },
            set: { if !$0 { listToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let list = listToDelete { store.deleteList(list) }
                listToDelete = nil
            }
            Button("取消", role: .cancel) { listToDelete = nil }
        } message: {
            Text("该清单下的所有任务将一并删除，此操作无法撤销。")
        }
    }

    // MARK: - Inbox row

    private var inboxRow: some View {
        let count = store.items.filter { $0.list == nil && !$0.isCompleted }.count
        return Label("收件箱", systemImage: "tray.fill")
            .badge(count)
            .tag(Optional<UUID>.none)
    }

    // MARK: - List row

    @ViewBuilder
    private func listRow(_ list: TodoList) -> some View {
        let count = store.items.filter { $0.list?.id == list.id && !$0.isCompleted }.count
        Group {
            if renamingList?.id == list.id {
                TextField("清单名称", text: $renameText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onKeyPress(.escape) { renamingList = nil; return .handled }
            } else {
                Label(list.name, systemImage: "list.bullet")
                    .badge(count)
                    .onTapGesture(count: 2) { startRename(list) }
            }
        }
        .tag(Optional(list.id))
        .contextMenu {
            Button("重命名") { startRename(list) }
            Divider()
            Button("删除清单", role: .destructive) { listToDelete = list }
        }
    }

    // MARK: - Add list button

    private var addListButton: some View {
        VStack(spacing: 0) {
            Divider()
            if isAddingList {
                TextField("新清单名称", text: $newListName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onSubmit { commitNewList() }
                    .onKeyPress(.escape) {
                        isAddingList = false
                        newListName = ""
                        return .handled
                    }
            } else {
                Button {
                    isAddingList = true
                } label: {
                    Label("新建清单", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func startRename(_ list: TodoList) {
        renameText = list.name
        renamingList = list
    }

    private func commitRename() {
        if let list = renamingList { store.renameList(list, to: renameText) }
        renamingList = nil
    }

    private func commitNewList() {
        store.createList(name: newListName)
        newListName = ""
        isAddingList = false
        selectedListID = store.lists.last?.id
    }
}
```

- [ ] **Step 2: Update ContentView.swift**

`SidebarView` now requires `@Binding var selectedListID: UUID?`. Use `@Bindable` to project the binding from `store`:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(TodoStore.self) private var store
    @AppStorage("isPinned") private var isPinned = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var window: NSWindow?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedListID: $store.selectedListID)
        } detail: {
            TaskListView(isPinned: $isPinned)
        }
        .toolbar(removing: .sidebarToggle)
        .background(WindowAccessor { captured in
            window = captured
            columnVisibility = isPinned ? .detailOnly : .automatic
            WindowManager.apply(isPinned: isPinned, window: captured)
        })
        .onChange(of: isPinned) { _, newValue in
            withAnimation { columnVisibility = newValue ? .detailOnly : .automatic }
            DispatchQueue.main.async {
                WindowManager.apply(isPinned: newValue, window: window)
            }
        }
    }
}
```

- [ ] **Step 3: Update TaskListView.swift**

Replace `DesktopTodo/Views/TaskListView.swift`:

```swift
import SwiftUI

struct TaskListView: View {
    @Environment(TodoStore.self) private var store
    @Binding var isPinned: Bool
    @State private var selectedItem: TodoItem?

    private var navigationTitle: String {
        if let id = store.selectedListID,
           let list = store.lists.first(where: { $0.id == id }) {
            return list.name
        }
        return "收件箱"
    }

    var body: some View {
        VStack(spacing: 0) {
            TaskInputView()

            List(selection: $selectedItem) {
                ForEach(store.currentItems) { item in
                    TaskRowView(item: item)
                        .tag(item)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        store.move(from: source, to: destination)
                    }
                }
            }
            .listStyle(.inset)
            .animation(.spring(response: 0.35, dampingFraction: 0.8),
                       value: store.currentItems.map(\.id))
            .animation(.spring(response: 0.35, dampingFraction: 0.8),
                       value: store.currentItems.map(\.isCompleted))
        }
        .navigationTitle(isPinned ? "" : navigationTitle)
        .toolbar {
            if !isPinned {
                ToolbarItem(placement: .automatic) {
                    let pending = store.currentItems.filter { !$0.isCompleted }.count
                    let allDone = pending == 0 && !store.currentItems.isEmpty
                    Text(allDone ? "全部完成 🎉" : "\(pending) 项待完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isPinned.toggle() } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(isPinned ? .blue : .secondary)
                }
                .help(isPinned ? "取消固定窗口" : "固定在最上层")
            }
        }
        .onKeyPress(.space) {
            guard let item = selectedItem else { return .ignored }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                store.toggleComplete(item)
            }
            return .handled
        }
        .onDeleteCommand {
            guard let item = selectedItem else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                store.deleteItem(item)
                selectedItem = nil
            }
        }
    }
}
```

- [ ] **Step 4: Build and manually verify**

Build (⌘B) and run. Check:
- [ ] Sidebar shows "收件箱" with pending-task badge
- [ ] Clicking "新建清单" opens inline text field; Return creates the list and selects it
- [ ] Tasks added in a list are isolated from inbox
- [ ] Double-clicking a list name enters rename mode; Return commits, Esc cancels
- [ ] Right-click → "删除清单" shows Alert with cascade warning; confirmed delete removes list + tasks
- [ ] Lists can be drag-reordered in sidebar
- [ ] Title in the main panel updates to reflect the selected list / "收件箱"

- [ ] **Step 5: Commit**

```bash
git add DesktopTodo/Views/SidebarView.swift DesktopTodo/Views/ContentView.swift \
        DesktopTodo/Views/TaskListView.swift
git commit -m "feat: SidebarView multi-list with create/rename/delete/reorder"
```

---

### Task 4: Priority circle button

**Files:**
- Modify: `DesktopTodo/Views/TaskRowView.swift`
- Create: `DesktopTodo/Views/DueDatePopoverView.swift` (stub)

**Interfaces:**
- Consumes: `item.priority`, `item.priority.next`, `store.setPriority(_:priority:)` from Task 2
- Produces: `DueDatePopoverView(item:)` stub (replaced in Task 5); `Priority.color` extension

- [ ] **Step 1: Replace TaskRowView.swift**

```swift
import SwiftUI

struct TaskRowView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showDueDatePopover = false

    var body: some View {
        HStack(spacing: 10) {
            // Priority circle (left of checkbox)
            Button {
                store.setPriority(item, priority: item.priority.next)
            } label: {
                Circle()
                    .fill(item.priority.color)
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help("点击切换优先级")
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Checkbox
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    store.toggleComplete(item)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.title3)
                    .scaleEffect(item.isCompleted ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isCompleted)
            }
            .buttonStyle(.plain)

            // Title / inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitEdit() }
                    .onKeyPress(.escape) { isEditing = false; return .handled }
            } else {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Hover-reveal: date button + delete
            if isHovered && !isEditing {
                // Date entry point
                Button {
                    showDueDatePopover = true
                } label: {
                    Group {
                        if let due = item.dueDate {
                            Text(due.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(due < Date() ? .red : .secondary)
                        } else {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDueDatePopover, arrowEdge: .bottom) {
                    DueDatePopoverView(item: item)
                        .environment(store)
                        .padding()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))

                // Delete
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.deleteItem(item) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovered }
        }
    }

    private func startEditing() { editText = item.title; isEditing = true }
    private func commitEdit() { store.updateTitle(item, title: editText); isEditing = false }
}

// MARK: - Priority color

extension Priority {
    var color: Color {
        switch self {
        case .none:   return .gray.opacity(0.35)
        case .low:    return .blue
        case .medium: return .yellow
        case .high:   return .red
        }
    }
}
```

- [ ] **Step 2: Create DueDatePopoverView stub**

Create `DesktopTodo/Views/DueDatePopoverView.swift` (placeholder so the project builds):

```swift
import SwiftUI

struct DueDatePopoverView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    var body: some View {
        // Implemented in Task 5
        Text("截止日期")
            .padding()
    }
}
```

- [ ] **Step 3: Build and manually verify**

Build (⌘B) and run. Check:
- [ ] Each task row has a small circle to the left of the checkbox
- [ ] Circle is gray (none), blue (low), yellow (medium), red (high)
- [ ] Hovering the circle changes cursor to pointer hand
- [ ] Clicking cycles: none → low → medium → high → none
- [ ] High-priority tasks automatically float above lower-priority ones

- [ ] **Step 4: Commit**

```bash
git add DesktopTodo/Views/TaskRowView.swift DesktopTodo/Views/DueDatePopoverView.swift
git commit -m "feat: priority circle button with color cycling and pointer cursor"
```

---

### Task 5: DueDatePopoverView

**Files:**
- Modify: `DesktopTodo/Views/DueDatePopoverView.swift` (replace stub)

**Interfaces:**
- Consumes: `store.setDueDate(_:date:reminderOffset:)`, `store.clearDueDate(_:)`, `ReminderOffset.displayName` (all from Tasks 1–2)

- [ ] **Step 1: Replace DueDatePopoverView.swift**

```swift
import SwiftUI

struct DueDatePopoverView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: TodoItem

    @State private var selectedDate: Date
    @State private var selectedOffset: ReminderOffset?

    init(item: TodoItem) {
        self.item = item
        _selectedDate = State(initialValue: item.dueDate ?? Calendar.current.startOfDay(for: Date()))
        _selectedOffset = State(initialValue: item.reminderOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("截止日期", systemImage: "calendar")
                .font(.headline)

            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: 300)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("提醒", systemImage: "bell")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("提醒时机", selection: $selectedOffset) {
                    Text("不提醒").tag(Optional<ReminderOffset>.none)
                    Text(ReminderOffset.atTime.displayName).tag(Optional(.atTime))
                    Text(ReminderOffset.oneHour.displayName).tag(Optional(.oneHour))
                    Text(ReminderOffset.oneDay.displayName).tag(Optional(.oneDay))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            HStack {
                Button("清除日期") {
                    store.clearDueDate(item)
                    dismiss()
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                Spacer()

                Button("完成") {
                    store.setDueDate(item, date: selectedDate, reminderOffset: selectedOffset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 300)
    }
}
```

- [ ] **Step 2: Build and manually verify**

Build (⌘B) and run. Check:
- [ ] Hovering a task shows a 📅 calendar icon
- [ ] Clicking it opens popover with a graphical calendar
- [ ] Selecting a date and clicking "完成" stores the date; row shows formatted date label
- [ ] Overdue dates display in red
- [ ] "清除日期" removes date and dismisses popover
- [ ] Reminder radio buttons appear (notification scheduling comes in Task 6)

- [ ] **Step 3: Commit**

```bash
git add DesktopTodo/Views/DueDatePopoverView.swift
git commit -m "feat: DueDatePopoverView with graphical date picker and reminder selector"
```

---

### Task 6: NotificationService

**Files:**
- Create: `DesktopTodo/Services/NotificationService.swift`
- Modify: `DesktopTodo/ViewModels/TodoStore.swift` (wire notifications into `setDueDate`, `clearDueDate`, `toggleComplete`, `deleteItem`)

**Interfaces:**
- Consumes: `item.dueDate`, `item.reminderOffset`, `item.reminderID`, `item.title`, `item.list?.name`, `ReminderOffset.secondsBefore`

- [ ] **Step 1: Create Services directory and NotificationService.swift**

```bash
mkdir -p DesktopTodo/Services
```

Create `DesktopTodo/Services/NotificationService.swift`:

```swift
import UserNotifications
import Foundation

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(for item: TodoItem) {
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
```

- [ ] **Step 2: Wire NotificationService into TodoStore**

In `DesktopTodo/ViewModels/TodoStore.swift`, replace these four methods:

**toggleComplete** — cancel on complete:
```swift
func toggleComplete(_ item: TodoItem) {
    item.isCompleted.toggle()
    if item.isCompleted { NotificationService.shared.cancelAll(for: item) }
    fetch()
}
```

**deleteItem** — cancel on delete:
```swift
func deleteItem(_ item: TodoItem) {
    NotificationService.shared.cancelAll(for: item)
    context.delete(item)
    fetch()
}
```

**setDueDate** — schedule after permission grant:
```swift
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
```

**clearDueDate** — cancel on clear:
```swift
func clearDueDate(_ item: TodoItem) {
    NotificationService.shared.cancelAll(for: item)
    item.dueDate = nil
    item.reminderOffset = nil
    item.reminderID = nil
}
```

- [ ] **Step 3: Run all tests**

In Xcode: Product → Test (⌘U).
Expected: all tests pass. (NotificationService is not exercised by unit tests — it requires the system notification stack.)

- [ ] **Step 4: Build and manually verify**

Build (⌘B) and run. To verify notifications:
1. Create a task with a due date 2 minutes from now, pick "到点提醒"
2. App asks for notification permission — grant it
3. After ~2 minutes, a system banner should appear with the task title
4. Mark the task complete before the timer — confirm the pending notification is cancelled:
   ```bash
   # List pending notifications (requires macOS debug entitlement or just wait and observe)
   ```
5. Delete a task with a future reminder — no notification should fire

- [ ] **Step 5: Commit**

```bash
git add DesktopTodo/Services/NotificationService.swift DesktopTodo/ViewModels/TodoStore.swift
git commit -m "feat: NotificationService + wire UserNotifications into TodoStore"
```

---

## Done ✅

All v1.1 features implemented and verified:

| Feature | Tasks |
|---------|-------|
| 多清单管理（create/rename/delete/reorder） | 1, 2, 3 |
| 任务优先级（hover circle, color coding） | 1, 2, 4 |
| 截止日期（graphical picker, overdue red） | 1, 2, 5 |
| 提醒（preset offsets, UserNotifications） | 1, 2, 5, 6 |
