# DesktopTodo — Pin 窗口功能设计文档

**日期**: 2026-06-24  
**范围**: 工具栏 Pin 按钮 — 窗口悬浮最上层 + 紧凑模式  
**依赖**: DesktopTodo v1.0（NavigationSplitView 架构）

---

## 1. 功能概述

用户点击工具栏大头针图标，切换窗口「固定」状态：

- **固定（Pinned）**：窗口浮于所有其他应用窗口上方（`NSWindow.level = .floating`），同时隐藏侧边栏、缩至紧凑尺寸
- **普通（Unpinned）**：窗口回到正常层级，侧边栏恢复，最小尺寸解除限制

---

## 2. 架构

### 状态驱动

唯一状态变量：

```swift
@AppStorage("isPinned") private var isPinned: Bool = false
```

存于 `ContentView`，持久化到 `UserDefaults`，重启后自动恢复上次状态。

### 组件职责

| 组件 | 职责 |
|------|------|
| `WindowManager`（新增） | 封装 AppKit 调用：设置 `NSWindow.level`、调用 `setContentSize()` |
| `ContentView`（修改） | 持有 `isPinned`；绑定 `columnVisibility` 到 `NavigationSplitView` |
| `TaskListView`（修改） | 工具栏 Pin 按钮，触发 `isPinned` 切换并调用 `WindowManager` |

### 数据流

```
用户点击 Pin 按钮（TaskListView toolbar）
  → isPinned.toggle()
  → ContentView：columnVisibility 切换
  → WindowManager.apply(isPinned, window: NSApp.mainWindow)
      → window.level = .floating / .normal
      → window.setContentSize(320×480) / 恢复最小限制
```

---

## 3. 新增文件

### `DesktopTodo/Views/WindowManager.swift`

```swift
import AppKit

struct WindowManager {
    /// 紧凑模式尺寸
    static let compactSize = NSSize(width: 320, height: 480)
    /// 普通模式最小尺寸
    static let normalMinSize = NSSize(width: 600, height: 400)

    static func apply(isPinned: Bool) {
        guard let window = NSApp.mainWindow else { return }
        if isPinned {
            window.level = .floating
            window.setContentSize(compactSize)
            window.minSize = NSSize(width: 320, height: 300)
        } else {
            window.level = .normal
            window.minSize = normalMinSize
            window.setContentSize(normalMinSize)   // 恢复可用宽度，避免侧边栏挤压
        }
    }
}
```

---

## 4. 修改文件

### `ContentView.swift`

新增：
- `@AppStorage("isPinned") private var isPinned = false`
- `@State private var columnVisibility: NavigationSplitViewVisibility = .automatic`

`NavigationSplitView` 绑定 `columnVisibility`：
- `isPinned == true` → `.detailOnly`（隐藏侧边栏）
- `isPinned == false` → `.automatic`

启动时在 `.onAppear` 里根据持久化的 `isPinned` 恢复窗口状态：

```swift
.onAppear {
    columnVisibility = isPinned ? .detailOnly : .automatic
    WindowManager.apply(isPinned: isPinned)
}
```

`isPinned` binding 传给 `TaskListView`。

### `TaskListView.swift`

**签名变更**：新增 `@Binding var isPinned: Bool` 参数，`ContentView` 调用时传入 `$isPinned`。

工具栏新增 Pin 按钮：

```swift
ToolbarItem(placement: .automatic) {
    Button {
        isPinned.toggle()
        columnVisibility = isPinned ? .detailOnly : .automatic
        WindowManager.apply(isPinned: isPinned)
    } label: {
        Image(systemName: isPinned ? "pin.fill" : "pin")
            .foregroundStyle(isPinned ? .blue : .secondary)
    }
    .help(isPinned ? "取消固定窗口" : "固定在最上层")
}
```

`isPinned` 通过 `@Binding` 从 `ContentView` 传入。

---

## 5. UI 规格

| 属性 | 值 |
|------|---|
| Pin 图标（未固定） | `pin`，次要色 |
| Pin 图标（已固定） | `pin.fill`，蓝色 |
| Tooltip | "固定在最上层" / "取消固定窗口" |
| 紧凑模式尺寸 | 320 × 480 pt |
| 紧凑模式最小高度 | 300 pt（用户可拖动） |
| 普通模式最小尺寸 | 600 × 400 pt |
| 持久化 | `@AppStorage("isPinned")`，UserDefaults |
| 重启恢复 | `.onAppear` 里应用持久化状态 |

---

## 6. 文件清单

| 文件 | 变更 |
|------|------|
| `DesktopTodo/Views/WindowManager.swift` | 新增 |
| `DesktopTodo/Views/ContentView.swift` | 修改：`isPinned`、`columnVisibility`、`onAppear` |
| `DesktopTodo/Views/TaskListView.swift` | 修改：`@Binding isPinned`、工具栏 Pin 按钮 |

---

## 7. 裁剪（不在本次范围内）

- 紧凑模式下的专用布局（字体缩小、行高压缩）
- 键盘快捷键触发 Pin（可 v1.2 加）
- 多窗口支持
