# Pin 窗口功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 工具栏大头针按钮，点击后窗口悬浮所有应用上方并切换至紧凑模式（隐藏侧边栏，320×480pt），再次点击恢复正常。

**Architecture:** `WindowManager`（新文件）封装所有 `NSWindow` AppKit 调用；`ContentView` 持有 `@AppStorage("isPinned")` 作为唯一状态变量，绑定 `NavigationSplitView` 的 `columnVisibility`；`TaskListView` 通过 `@Binding` 接收状态，工具栏 Pin 按钮触发切换。

**Tech Stack:** Swift 6, SwiftUI (macOS 14+), AppKit (`NSWindow`), `@AppStorage` (UserDefaults), XcodeGen 2.45.4

## Global Constraints

- Swift 版本：6.0，严格并发（`SWIFT_STRICT_CONCURRENCY: complete`）
- macOS 部署目标：14.0
- 不引入任何第三方 Swift 包
- `project.yml` 是 Xcode 项目唯一来源，每次新增文件后必须重跑 `xcodegen generate`
- 工作目录：`/Users/zhuyecun/Documents/code/toDoList`

---

### Task 1: WindowManager

**Files:**
- Create: `DesktopTodo/Views/WindowManager.swift`

**Interfaces:**
- Consumes: `AppKit.NSWindow`（通过 `NSApp.mainWindow`）
- Produces:
  - `struct WindowManager` — 无实例，纯静态方法
  - `WindowManager.apply(isPinned: Bool)` — 根据状态设置 `window.level`、`window.minSize`、`window.setContentSize()`
  - `WindowManager.compactSize: NSSize` = `NSSize(width: 320, height: 480)`
  - `WindowManager.normalMinSize: NSSize` = `NSSize(width: 600, height: 400)`

- [ ] **Step 1: 创建 WindowManager.swift**

创建 `DesktopTodo/Views/WindowManager.swift`：

```swift
import AppKit

struct WindowManager {
    /// 紧凑模式（Pin）窗口尺寸
    static let compactSize = NSSize(width: 320, height: 480)
    /// 普通模式最小尺寸
    static let normalMinSize = NSSize(width: 600, height: 400)

    /// 根据 isPinned 状态调整窗口层级与尺寸
    static func apply(isPinned: Bool) {
        guard let window = NSApp.mainWindow else { return }
        if isPinned {
            window.level = .floating
            window.minSize = NSSize(width: 320, height: 300)
            window.setContentSize(compactSize)
        } else {
            window.level = .normal
            window.minSize = normalMinSize
            window.setContentSize(normalMinSize)  // 避免取消固定后侧边栏挤压
        }
    }
}
```

- [ ] **Step 2: 重跑 xcodegen，将新文件加入项目**

```bash
xcodegen generate
```

预期输出包含：`Created project at DesktopTodo.xcodeproj`

- [ ] **Step 3: Xcode 编译验证**

在 Xcode 按 `⌘B`。预期：**Build Succeeded**，无错误。

- [ ] **Step 4: Commit**

```bash
git add DesktopTodo/Views/WindowManager.swift DesktopTodo.xcodeproj
git commit -m "feat: add WindowManager for NSWindow level and size control"
```

---

### Task 2: ContentView + TaskListView — Pin 状态接线与按钮

**Files:**
- Modify: `DesktopTodo/Views/ContentView.swift`
- Modify: `DesktopTodo/Views/TaskListView.swift`

**Interfaces:**
- Consumes: `WindowManager.apply(isPinned:)` from Task 1
- Produces:
  - `ContentView` — 新增 `@AppStorage("isPinned") private var isPinned: Bool`；`@State private var columnVisibility: NavigationSplitViewVisibility`；`.onAppear` 恢复持久化状态；`TaskListView` 调用改为 `TaskListView(isPinned: $isPinned)`
  - `TaskListView` — 新增 `@Binding var isPinned: Bool`；工具栏新增 Pin `ToolbarItem`，点击切换状态并调用 `WindowManager.apply`

- [ ] **Step 1: 替换 ContentView.swift**

用以下内容完整替换 `DesktopTodo/Views/ContentView.swift`：

```swift
import SwiftUI

struct ContentView: View {
    @AppStorage("isPinned") private var isPinned = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            TaskListView(isPinned: $isPinned)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            // 重启后恢复持久化的 Pin 状态
            columnVisibility = isPinned ? .detailOnly : .automatic
            WindowManager.apply(isPinned: isPinned)
        }
        .onChange(of: isPinned) { _, newValue in
            // Pin 按钮切换时同步侧边栏可见性
            withAnimation {
                columnVisibility = newValue ? .detailOnly : .automatic
            }
        }
    }
}
```

- [ ] **Step 2: 替换 TaskListView.swift**

用以下内容完整替换 `DesktopTodo/Views/TaskListView.swift`：

```swift
import SwiftUI

struct TaskListView: View {
    @Environment(TodoStore.self) private var store
    @Binding var isPinned: Bool
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
            // 待完成计数
            ToolbarItem(placement: .automatic) {
                let pending = store.items.filter { !$0.isCompleted }.count
                Text(pending == 0 && !store.items.isEmpty ? "全部完成 🎉" : "\(pending) 项待完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Pin 按钮
            ToolbarItem(placement: .automatic) {
                Button {
                    isPinned.toggle()
                    WindowManager.apply(isPinned: isPinned)
                } label: {
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

- [ ] **Step 3: Xcode 编译验证**

在 Xcode 按 `⌘B`。预期：**Build Succeeded**，无错误。

- [ ] **Step 4: Commit**

```bash
git add DesktopTodo/Views/ContentView.swift DesktopTodo/Views/TaskListView.swift
git commit -m "feat: add Pin toggle button with compact mode and floating window"
```

---

### Task 3: 冒烟测试 + 收尾

**Files:** 无（仅验证）

- [ ] **Step 1: 运行 App**

Xcode 按 `⌘R` 启动 App。

- [ ] **Step 2: 冒烟测试**

| 操作 | 预期结果 |
|------|---------|
| 观察工具栏右侧 | 出现灰色 `pin`（大头针）图标 |
| 点击 Pin 按钮 | 图标变为蓝色 `pin.fill`；侧边栏消失；窗口缩至 ~320×480 |
| 切换到其他 App（如 Finder） | DesktopTodo 窗口仍悬浮在最上层，不被遮挡 |
| 再次点击 Pin 按钮 | 图标恢复灰色 `pin`；侧边栏重新出现；窗口扩回 600×400 |
| `⌘Q` 退出，重新 `⌘R` 启动 | 若上次退出时是 Pin 状态，重启后窗口立即悬浮并呈紧凑布局 |
| 悬浮于 Tooltip | 未固定时显示「固定在最上层」；已固定时显示「取消固定窗口」 |

- [ ] **Step 3: 最终 Commit**

```bash
git add -A
git commit -m "feat: pin window feature complete"
```
