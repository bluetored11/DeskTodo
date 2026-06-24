# DesktopTodo v1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS SwiftUI todo app (v1.0 MVP) with single inbox list, CRUD + completion toggle, local SwiftData persistence, spring animations, and basic keyboard shortcuts.

**Architecture:** MVVM — `TodoStore` (`@MainActor @Observable`) holds all state and wraps `ModelContext`; Views consume it via `@Environment(TodoStore.self)`. `ModelContainer` is created at app startup in `DesktopTodoApp`, persisting data locally to the user's Application Support directory automatically via SwiftData.

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), SwiftData, XcodeGen 2.45.4

## Global Constraints

- Swift version: 6.0, strict concurrency (`SWIFT_STRICT_CONCURRENCY: complete`)
- macOS deployment target: 14.0
- Bundle ID: `com.bluetored.DesktopTodo`
- `TodoStore` is `@MainActor` — all calls from Views are safe (SwiftUI Views run on main thread)
- No network, no iCloud, no third-party Swift packages
- `project.yml` is the source of truth for the Xcode project — never edit `.xcodeproj` manually; re-run `xcodegen generate` after any structural change
- Working directory for all commands: `/Users/zhuyecun/Documents/code/toDoList`

---

### Task 1: Project Scaffold

**Files:**
- Create: `project.yml`
- Create: `DesktopTodo/Info.plist`
- Create: `DesktopTodo/Assets.xcassets/Contents.json`
- Create: `DesktopTodo/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Generate: `DesktopTodo.xcodeproj` (via xcodegen)

**Interfaces:**
- Produces: compilable Xcode project skeleton with correct bundle ID, deployment target, and Swift 6 settings

- [ ] **Step 1: Initialize git repository**

```bash
cd /Users/zhuyecun/Documents/code/toDoList
git init
git add REQUIREMENTS.md docs/
git commit -m "chore: add requirements and design docs"
```

Expected: `[main (root-commit) xxxxxxx] chore: add requirements and design docs`

- [ ] **Step 2: Create project.yml**

Create `/Users/zhuyecun/Documents/code/toDoList/project.yml`:

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
```

- [ ] **Step 3: Create Info.plist**

Create `DesktopTodo/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>DesktopTodo</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 bluetored. All rights reserved.</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 4: Create Assets.xcassets**

Create `DesktopTodo/Assets.xcassets/Contents.json`:
```json
{
  "info": { "author": "xcode", "version": 1 }
}
```

Create `DesktopTodo/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images": [],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 5: Create source directory structure**

```bash
mkdir -p DesktopTodo/App
mkdir -p DesktopTodo/Models
mkdir -p DesktopTodo/ViewModels
mkdir -p DesktopTodo/Views
```

- [ ] **Step 6: Run XcodeGen**

```bash
xcodegen generate
```

Expected output contains: `✅  Created project at DesktopTodo.xcodeproj`

- [ ] **Step 7: Commit scaffold**

```bash
git add project.yml DesktopTodo/
git commit -m "chore: scaffold XcodeGen project structure"
```

---

### Task 2: Data Model + TodoStore

**Files:**
- Create: `DesktopTodo/Models/TodoItem.swift`
- Create: `DesktopTodo/ViewModels/TodoStore.swift`
- Create: `DesktopTodo/App/DesktopTodoApp.swift` (placeholder to enable build verification)

**Interfaces:**
- Produces:
  - `final class TodoItem` — `@Model`, fields: `id: UUID`, `title: String`, `isCompleted: Bool`, `createdAt: Date`, `order: Int`, `priority: Priority`
  - `enum Priority: Int, Codable` — `.none=0`, `.low=1`, `.medium=2`, `.high=3`
  - `final class TodoStore` — `@MainActor @Observable`, init: `init(context: ModelContext)`, properties: `items: [TodoItem]`, methods: `addItem(title:)`, `toggleComplete(_:)`, `updateTitle(_:title:)`, `deleteItem(_:)`, `move(from:to:)`, `fetch()`

- [ ] **Step 1: Create TodoItem.swift**

Create `DesktopTodo/Models/TodoItem.swift`:

```swift
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
```

- [ ] **Step 2: Create TodoStore.swift**

Create `DesktopTodo/ViewModels/TodoStore.swift`:

```swift
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
```

- [ ] **Step 3: Create placeholder App entry to enable build**

Create `DesktopTodo/App/DesktopTodoApp.swift`:

```swift
import SwiftUI
import SwiftData

@main
struct DesktopTodoApp: App {
    var body: some Scene {
        WindowGroup { Text("scaffold") }
    }
}
```

- [ ] **Step 4: Re-run XcodeGen and verify build in Xcode**

```bash
xcodegen generate
```

Open `DesktopTodo.xcodeproj` in Xcode, press `Cmd+B`.  
Expected: **Build Succeeded** — no errors.

- [ ] **Step 5: Commit**

```bash
git add DesktopTodo/Models/ DesktopTodo/ViewModels/ DesktopTodo/App/
git commit -m "feat: add TodoItem model and TodoStore"
```

---

### Task 3: App Entry + ContentView + SidebarView

**Files:**
- Modify: `DesktopTodo/App/DesktopTodoApp.swift` (replace placeholder)
- Create: `DesktopTodo/Views/ContentView.swift`
- Create: `DesktopTodo/Views/SidebarView.swift`
- Create: `DesktopTodo/Views/TaskListView.swift` (temporary placeholder)

**Interfaces:**
- Consumes: `TodoStore`, `TodoItem` from Task 2
- Produces:
  - `DesktopTodoApp` — creates `ModelContainer`, injects `TodoStore` via `@Environment`, registers `Cmd+N` menu command, posts `Notification.Name.focusTaskInput`
  - `ContentView` — `NavigationSplitView` with sidebar + detail columns, min size 600×400
  - `SidebarView` — fixed "收件箱" list entry, sidebar column width 180–200pt
  - `extension Notification.Name` — `static let focusTaskInput`

- [ ] **Step 1: Replace DesktopTodoApp.swift**

```swift
import SwiftUI
import SwiftData

@main
struct DesktopTodoApp: App {
    private let container: ModelContainer = {
        let schema = Schema([TodoItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(TodoStore(context: container.mainContext))
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") {
                    NotificationCenter.default.post(name: .focusTaskInput, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
    }
}

extension Notification.Name {
    static let focusTaskInput = Notification.Name("focusTaskInput")
}
```

- [ ] **Step 2: Create ContentView.swift**

Create `DesktopTodo/Views/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TaskListView()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
```

- [ ] **Step 3: Create SidebarView.swift**

Create `DesktopTodo/Views/SidebarView.swift`:

```swift
import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Label("收件箱", systemImage: "tray.fill")
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .navigationTitle("DesktopTodo")
    }
}
```

- [ ] **Step 4: Create temporary placeholder TaskListView.swift**

Create `DesktopTodo/Views/TaskListView.swift`:

```swift
import SwiftUI

struct TaskListView: View {
    var body: some View {
        Text("任务列表（即将实现）")
            .navigationTitle("收件箱")
    }
}
```

- [ ] **Step 5: Build and run**

In Xcode, press `Cmd+R`.  
Expected: app launches, split view appears — sidebar shows "收件箱" label, detail area shows placeholder text.

- [ ] **Step 6: Commit**

```bash
git add DesktopTodo/App/ DesktopTodo/Views/
git commit -m "feat: app entry, ContentView, SidebarView"
```

---

### Task 4: TaskInputView

**Files:**
- Create: `DesktopTodo/Views/TaskInputView.swift`

**Interfaces:**
- Consumes: `TodoStore.addItem(title:)`, `Notification.Name.focusTaskInput`
- Produces: `TaskInputView` — TextField with plus icon; Return submits non-empty title; listens for `focusTaskInput` notification to become first responder

- [ ] **Step 1: Create TaskInputView.swift**

Create `DesktopTodo/Views/TaskInputView.swift`:

```swift
import SwiftUI

struct TaskInputView: View {
    @Environment(TodoStore.self) private var store
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)
            TextField("添加任务...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.addItem(title: text)
                    text = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onReceive(NotificationCenter.default.publisher(for: .focusTaskInput)) { _ in
            isFocused = true
        }
    }
}
```

- [ ] **Step 2: Build to verify**

In Xcode, press `Cmd+B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add DesktopTodo/Views/TaskInputView.swift
git commit -m "feat: add TaskInputView with Cmd+N focus support"
```

---

### Task 5: TaskRowView

**Files:**
- Create: `DesktopTodo/Views/TaskRowView.swift`

**Interfaces:**
- Consumes: `TodoItem` (id, title, isCompleted), `TodoStore.toggleComplete(_:)`, `TodoStore.updateTitle(_:title:)`, `TodoStore.deleteItem(_:)`
- Produces: `TaskRowView(item: TodoItem)` — horizontal row containing: spring-animated checkbox button, title label (or inline TextField when editing), hover-revealed trash button

- [ ] **Step 1: Create TaskRowView.swift**

Create `DesktopTodo/Views/TaskRowView.swift`:

```swift
import SwiftUI

struct TaskRowView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox with spring bounce animation
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

            // Title or inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitEdit() }
                    .onKeyPress(.escape) {
                        isEditing = false
                        return .handled
                    }
            } else {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Hover-reveal delete button
            if isHovered && !isEditing {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.deleteItem(item)
                    }
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
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }

    private func startEditing() {
        editText = item.title
        isEditing = true
    }

    private func commitEdit() {
        store.updateTitle(item, title: editText)
        isEditing = false
    }
}
```

- [ ] **Step 2: Build to verify**

In Xcode, press `Cmd+B`. Expected: Build Succeeded.

- [ ] **Step 3: Commit**

```bash
git add DesktopTodo/Views/TaskRowView.swift
git commit -m "feat: add TaskRowView with checkbox animation, inline edit, hover delete"
```

---

### Task 6: TaskListView — Full Implementation

**Files:**
- Modify: `DesktopTodo/Views/TaskListView.swift` (replace placeholder from Task 3)

**Interfaces:**
- Consumes: `TodoStore.items`, `TodoStore.move(from:to:)`, `TodoStore.toggleComplete(_:)`, `TodoStore.deleteItem(_:)`, `TaskInputView`, `TaskRowView`
- Produces: Complete task list view — `TaskInputView` at top, `List` with `ForEach` of `TaskRowView`, drag-to-reorder via `.onMove`, insert/delete spring animations, `Space` key toggles selected item, `Delete` key removes selected item

- [ ] **Step 1: Replace TaskListView.swift**

```swift
import SwiftUI

struct TaskListView: View {
    @Environment(TodoStore.self) private var store
    @State private var selectedItem: TodoItem?

    var body: some View {
        VStack(spacing: 0) {
            TaskInputView()

            List(selection: $selectedItem) {
                ForEach(store.items) { item in
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
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.items.map(\.id))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.items.map(\.isCompleted))
        }
        .navigationTitle("收件箱")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                let pending = store.items.filter { !$0.isCompleted }.count
                Text(pending == 0 && !store.items.isEmpty ? "全部完成 🎉" : "\(pending) 项待完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

- [ ] **Step 2: Build and run**

In Xcode, press `Cmd+R`.

- [ ] **Step 3: Manual smoke test — run through every v1.0 feature**

| Action | Expected |
|--------|---------|
| Type "写需求文档" → Return | Task appears with slide-in animation; input clears |
| Type "  " → Return | Nothing added (whitespace guard) |
| Click checkbox on a task | Checkmark fills green with spring bounce; text gets strikethrough |
| Hover over a task | Trash icon fades in on right side |
| Click trash icon | Task disappears with fade animation |
| Double-click task title | Title becomes editable TextField |
| Edit text → Return | New title committed, view exits editing |
| Edit text → Esc | Original title restored, view exits editing |
| Click task to select → Space | Completion toggled |
| Click task to select → Delete | Task deleted, selection cleared |
| Drag task row to new position | Task reorders with spring animation |
| Press Cmd+N | Input field receives focus (cursor appears) |
| Quit app (Cmd+Q) → relaunch | All tasks persist with correct state |

- [ ] **Step 4: Commit**

```bash
git add DesktopTodo/Views/TaskListView.swift
git commit -m "feat: complete TaskListView with animations and keyboard shortcuts"
```

---

### Task 7: Final Build Verification

**Files:** None — verification only.

- [ ] **Step 1: Clean build**

In Xcode: `Product → Clean Build Folder` (`Cmd+Shift+K`), then `Cmd+B`.  
Expected: **Build Succeeded** — zero errors.

- [ ] **Step 2: Verify persistence across launches**

1. `Cmd+R` — launch app
2. Add tasks: "任务A", "任务B", "任务C"
3. Check "任务B" as complete
4. `Cmd+Q` — quit
5. `Cmd+R` — relaunch
6. Expected: all 3 tasks present, "任务B" shows as completed

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: DesktopTodo v1.0 MVP complete"
```

---

## File Summary

| File | Responsibility |
|------|---------------|
| `project.yml` | XcodeGen config — bundle ID, Swift 6, macOS 14 |
| `DesktopTodo/Info.plist` | macOS app metadata |
| `DesktopTodo/Assets.xcassets` | Asset catalog (empty app icon for v1.0) |
| `DesktopTodo/App/DesktopTodoApp.swift` | `@main` entry, `ModelContainer` setup, Cmd+N command, `focusTaskInput` notification |
| `DesktopTodo/Models/TodoItem.swift` | `@Model TodoItem`, `Priority` enum |
| `DesktopTodo/ViewModels/TodoStore.swift` | `@MainActor @Observable TodoStore` — all CRUD + reorder logic |
| `DesktopTodo/Views/ContentView.swift` | `NavigationSplitView` host, min frame 600×400 |
| `DesktopTodo/Views/SidebarView.swift` | Fixed "收件箱" sidebar entry |
| `DesktopTodo/Views/TaskListView.swift` | Input bar + animated list + Space/Delete keyboard handlers |
| `DesktopTodo/Views/TaskInputView.swift` | Add-task TextField, Cmd+N focus via notification |
| `DesktopTodo/Views/TaskRowView.swift` | Checkbox, inline edit, hover-reveal delete button |
