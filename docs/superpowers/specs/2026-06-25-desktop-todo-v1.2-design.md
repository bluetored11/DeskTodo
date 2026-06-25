# DesktopTodo v1.2 设计文档

**日期**: 2026-06-25  
**范围**: v1.2 — 子任务（单层）  
**基于**: v1.1（多清单管理、任务优先级 UI、截止日期 + 提醒）  
**最低系统**: macOS 14+

---

## 1. 功能范围

| 功能 | 说明 |
|------|------|
| 子任务（单层） | 为父任务添加子任务，支持增删改查、内联展开/折叠 |
| 自动完成父任务 | 所有子任务完成时，父任务自动标记为已完成 |
| 联动勾选子任务 | 手动勾选父任务时，所有子任务一并勾选为已完成 |

**不在 v1.2 范围**：子任务拖拽排序、子任务截止日期/优先级、状态栏模式、智能列表、搜索、标签

---

## 2. 数据模型

### 2.1 新增 `SubTask` 模型

```swift
@Model
class SubTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var order: Int          // 按创建顺序排列（v1.2 不暴露拖拽排序，字段保留供将来使用）
    var createdAt: Date

    @Relationship(inverse: \TodoItem.subtasks)
    var item: TodoItem?     // 反向关联父任务
}
```

### 2.2 `TodoItem` 新增字段

```swift
// 追加到现有 TodoItem：
@Relationship(deleteRule: .cascade)
var subtasks: [SubTask]?   // nil 等价于空数组，删除父任务时 cascade 自动删除子任务
```

### 2.3 迁移策略

- 新增可选字段 + 新增模型 → SwiftData **轻量级自动迁移**，无需 `MigrationPlan`
- `DesktopTodoApp.swift` 的 `schema` 中加入 `SubTask.self`
- 现有数据不受影响，`subtasks` 默认为 `nil`

---

## 3. 架构变更

### 3.1 TodoStore 扩展

在现有 `TodoStore` 基础上追加子任务 CRUD，不新建 store。

#### 子任务 CRUD

```swift
// 添加子任务
func addSubTask(to item: TodoItem, title: String) {
    let sub = SubTask(
        id: UUID(),
        title: title,
        isCompleted: false,
        order: (item.subtasks?.count ?? 0),
        createdAt: Date()
    )
    sub.item = item
    context.insert(sub)
}

// 更新子任务完成状态（含自动完成父任务逻辑）
func toggleSubTask(_ sub: SubTask) {
    sub.isCompleted.toggle()
    autoCompleteParentIfNeeded(sub.item)
}

// 删除子任务
func deleteSubTask(_ sub: SubTask) {
    context.delete(sub)
}
```

#### 完成状态同步

```swift
// 子任务全完成 → 自动完成父任务
private func autoCompleteParentIfNeeded(_ item: TodoItem?) {
    guard let item, !(item.subtasks?.isEmpty ?? true) else { return }
    let allDone = item.subtasks?.allSatisfy(\.isCompleted) ?? false
    if allDone && !item.isCompleted {
        item.isCompleted = true
        cancelNotificationIfNeeded(for: item)   // 复用 v1.1 的通知取消逻辑
    }
}

// 勾选父任务 → 子任务一并勾选（修改现有 toggleItem）
func toggleItem(_ item: TodoItem) {
    item.isCompleted.toggle()
    if item.isCompleted {
        item.subtasks?.forEach { $0.isCompleted = true }
        cancelNotificationIfNeeded(for: item)
    }
}
```

> **注意**：取消父任务完成（再次 toggle 为 false）时，子任务状态不回退，保持各自现有状态。

#### deleteItem 防御性处理

```swift
func deleteItem(_ item: TodoItem) {
    // SwiftData cascade 会自动删子任务，但显式先删更安全
    item.subtasks?.forEach { context.delete($0) }
    context.delete(item)
}
```

### 3.2 新增文件

```
DesktopTodo/
├── Models/
│   └── SubTask.swift          # 新增
├── Views/
│   └── SubTaskRowView.swift   # 新增
```

---

## 4. 界面设计

### 4.1 父任务行（TaskRowView 改动）

父任务有子任务时，标题后追加进度标签 + 展开/折叠按钮：

```
hover 状态（有子任务）：
●  ○  完成设计稿  ·  2/4  ⌄   [📅6月30日]  [🗑]
                  ↑  ↑   ↑
              分隔  进  展开/折叠按钮
                度  文字  (chevron.down / chevron.right)
```

- **进度格式**：`{完成数}/{总数}`（如 `2/4`），仅在 `subtasks.count > 0` 时显示
- **展开状态**：存于 `TaskRowView` 的 `@State var isExpanded: Bool`，默认 `false`，不持久化
- **展开按钮**：`chevron.down`（展开中）/ `chevron.right`（已折叠），点击切换

展开后，父任务行下方内嵌子任务列表（左缩进 20pt）：

```
[ ] 完成设计稿  ·  2/4  ⌄   [📅6月30日]  [🗑]
         [ ] 整理素材                      [🗑]
         [✓] 初稿排版（文字灰色）           [🗑]
         [ ] 审阅修改                      [🗑]
        [+ 添加子任务]
```

### 4.2 子任务行（SubTaskRowView）

| 元素 | 说明 |
|------|------|
| 复选框 | 勾选调用 `store.toggleSubTask(_:)` |
| 标题 | 未完成：正常文字；已完成：灰色 + 删除线 |
| 内联编辑 | 双击标题进入编辑态，回车/失焦保存，Esc 取消 |
| 删除按钮 | Hover 时出现在最右侧，调用 `store.deleteSubTask(_:)` |
| 缩进 | 左侧 20pt padding |
| 无优先级圆点 | 无 📅 日历按钮 |

### 4.3 「添加子任务」输入行

始终显示在子任务列表末尾（不依赖 hover），点击进入输入态：

| 操作 | 行为 |
|------|------|
| 点击「+ 添加子任务」 | 显示 `TextField`，自动获取焦点 |
| 回车（非空标题） | 调用 `store.addSubTask`，清空输入框继续输入 |
| 回车（空标题） | 关闭输入框 |
| Esc | 取消，关闭输入框 |

---

## 5. 边界情况

| 情况 | 处理 |
|------|------|
| 删除父任务（含子任务） | `deleteItem` 先显式删子任务，再删父任务；通知一并取消 |
| 父任务已完成，再添加子任务 | 允许添加，子任务默认未完成；父任务状态不变 |
| 取消父任务完成（toggle 回 false） | 子任务状态不回退，保持各自状态 |
| 所有子任务完成后再取消其中一个 | 父任务不自动取消完成（反向不联动） |
| 拖拽排序父任务 | 子任务随父任务整体移动，子任务列表不受影响 |
| `currentItems` 过滤 | 无需改动（`SubTask` 是独立 Model，不会出现在 `items` 里） |

---

## 6. 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Models/SubTask.swift` | **新增** | SubTask SwiftData 模型 |
| `Models/TodoItem.swift` | 修改 | 新增 `subtasks: [SubTask]?` 字段 |
| `ViewModels/TodoStore.swift` | 修改 | 新增子任务 CRUD；修改 `toggleItem` / `deleteItem` |
| `Views/TaskRowView.swift` | 修改 | 追加进度标签、展开按钮、子任务展开列表 |
| `Views/SubTaskRowView.swift` | **新增** | 子任务行 View |
| `App/DesktopTodoApp.swift` | 修改 | schema 加入 `SubTask.self` |

---

## 7. 不在 v1.2 范围内

- 子任务拖拽排序（`order` 字段已保留，UI 暂不暴露）
- 子任务截止日期 / 优先级
- 状态栏模式
- 智能列表（今天 / 未来 7 天）
- 搜索
- 标签系统
