# DesktopTodo v1.1 设计文档

**日期**: 2026-06-24  
**范围**: v1.1 — 多清单管理、任务优先级（UI）、截止日期 + 提醒  
**基于**: v1.0（单收件箱、增删改查、本地持久化、Pin 窗口）  
**最低系统**: macOS 14+

---

## 1. 功能范围

| 功能 | 说明 |
|------|------|
| 多清单管理 | 侧边栏支持创建/重命名/删除/拖拽排序自定义列表，只有名称，无图标/颜色 |
| 任务优先级 | 高/中/低，任务行 hover 时圆点可点击循环切换，颜色区分 |
| 截止日期 | 任务行 hover 时日历图标入口，Popover 日历选择器 |
| 提醒 | 提前选项：到点/提前1小时/提前1天，基于 UserNotifications |

**砍掉（移至 v1.2+）**: 状态栏模式

---

## 2. 数据模型变更

### 2.1 新增 `TodoList` 模型

```swift
@Model
class TodoList {
    @Attribute(.unique) var id: UUID
    var name: String
    var order: Int
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var items: [TodoItem]?
}
```

- `deleteRule: .cascade`：删除列表时关联任务一并删除
- 只有名称，无图标/颜色

### 2.2 `TodoItem` 新增字段

```swift
// 在 v1.0 已有字段基础上追加：
var dueDate: Date?
var reminderOffset: ReminderOffset?   // nil = 不提醒
var reminderID: String?               // UNNotificationRequest identifier（UUID().uuidString），用于取消/更新通知

@Relationship(inverse: \TodoList.items)
var list: TodoList?                   // nil = 属于「收件箱」（未分配列表）
```

`priority: Priority` 字段 v1.0 已存在于模型，v1.1 只新增 UI，无需改 model。

### 2.3 `ReminderOffset` 枚举

```swift
enum ReminderOffset: Int, Codable {
    case atTime    = 0    // 到点提醒
    case oneHour   = 60   // 提前 1 小时（单位：分钟）
    case oneDay    = 1440 // 提前 1 天
}
```

### 2.4 迁移策略

SwiftData 对「新增可选字段」和「新增模型」支持**轻量级自动迁移**，无需手写 `MigrationPlan`。在 App 入口 `ModelContainer` 的 `schema` 中加入 `TodoList` 即可，现有数据不受影响。

---

## 3. 架构变更

### 3.1 TodoStore 扩展

在现有 `TodoStore` 基础上追加 list 管理能力，不新建 store。

```swift
@Observable
class TodoStore {
    // ── v1.0 已有 ──
    private var context: ModelContext
    var items: [TodoItem] = []

    // ── v1.1 新增 ──
    var lists: [TodoList] = []
    var selectedListID: UUID? = nil   // nil = 收件箱
}
```

**List CRUD**：

```swift
func createList(name: String)
func renameList(_ list: TodoList, to name: String)
func deleteList(_ list: TodoList)        // cascade 删除由 SwiftData 处理
func moveLists(from: IndexSet, to: Int)  // 拖拽排序
```

**当前任务过滤**（`items` 改为计算属性）：

```swift
var currentItems: [TodoItem] {
    let filtered = items.filter { item in
        selectedListID == nil
            ? item.list == nil
            : item.list?.id == selectedListID
    }
    // 未完成：高→中→低→无；已完成沉底
    return filtered.sorted { a, b in
        if a.isCompleted != b.isCompleted { return !a.isCompleted }
        return a.priority.rawValue > b.priority.rawValue
    }
}
```

`TaskListView` 将 `store.items` 替换为 `store.currentItems`，其余逻辑不变。

**任务创建时关联列表**：

```swift
func addItem(title: String) {
    let item = TodoItem(title: title, ...)
    if let id = selectedListID,
       let list = lists.first(where: { $0.id == id }) {
        item.list = list
    }
    context.insert(item)
}
```

### 3.2 新增文件

```
DesktopTodo/
├── Models/
│   └── TodoList.swift          # 新增
├── Services/
│   └── NotificationService.swift  # 新增
```

---

## 4. 界面设计

### 4.1 侧边栏（SidebarView）

```
SidebarView
├── 「收件箱」固定项（selectedListID = nil，显示未完成任务数 badge）
├── ── 分隔线 ──
├── List（用户自建清单，可拖拽排序）
│     └── 每行：列表名 + 未完成任务数 badge（数为 0 时隐藏）
│           双击：行内重命名输入框
│           右键：上下文菜单「重命名 / 删除」
└── 底部「+ 新建清单」按钮
```

**交互细节**：

| 操作 | 实现 |
|------|------|
| 新建清单 | 点击「+ 新建清单」→ 行内输入框，回车确认，Esc 取消 |
| 重命名 | 双击列表名 → 行内输入框，与新建复用同一组件 |
| 删除列表 | 右键菜单「删除清单」→ Alert 二次确认（说明「该列表下所有任务将一并删除」） |
| 拖拽排序 | `List` 的 `.onMove` 回调，调用 `store.moveLists` |
| 选中高亮 | `NavigationSplitView` 原生 selection 绑定 `store.selectedListID` |

### 4.2 任务行优先级（TaskRowView）

优先级圆点位于复选框**左侧**：

```
●  ○  完成设计稿     [📅] [🗑]
↑
彩色圆点，hover 时可点击
```

| 状态 | 圆点颜色 |
|------|---------|
| none | 灰色（低调） |
| low  | 蓝色 |
| medium | 黄色 |
| high | 红色 |

- Hover 时显示 tooltip「点击切换优先级」，cursor 为手型
- 单击依次循环：`none → low → medium → high → none`

### 4.3 截止日期（TaskRowView + Popover）

- Hover 时删除按钮左边出现 📅 图标按钮
- 已设日期时图标替换为日期标签（如 `6月30日`），逾期变红
- 点击弹出 Popover：

```
┌─────────────────────────┐
│  📅  截止日期            │
│  [DatePicker .graphical] │
│                         │
│  🔔  提醒               │
│  ◉ 不提醒               │
│  ○ 到点提醒              │
│  ○ 提前 1 小时           │
│  ○ 提前 1 天             │
│                         │
│  [清除日期]    [完成]    │
└─────────────────────────┘
```

- 「清除日期」同时清除提醒
- 「完成」保存并调度通知

---

## 5. 通知服务

### 5.1 NotificationService

```swift
final class NotificationService {
    static let shared = NotificationService()

    func requestPermission() async -> Bool
    func schedule(for item: TodoItem)   // 取消旧请求 + 调度新请求
    func cancel(id: String)
    func cancelAll(for item: TodoItem)
}
```

`TodoStore` 调用通知服务，Views 不直接接触 `UserNotifications`。

### 5.2 权限请求时机

**首次设置截止日期时**请求权限，而非冷启动时。用户有上下文，接受率更高。

### 5.3 通知内容

```
标题：⏰ 任务提醒
正文：「完成设计稿」截止时间到了
副标题：（有所属列表时）列表名称
```

点击通知 → `NSApp.activate(ignoringOtherApps: true)` 唤起主窗口。

### 5.4 调度规则

| 事件 | 动作 |
|------|------|
| 设置/更新日期或提醒偏移 | 取消旧通知 → 调度新通知 |
| 清除日期 | 取消通知，清空 `reminderID` |
| 完成任务 | 取消通知 |
| 删除任务 | 取消通知 |

### 5.5 边界情况

| 情况 | 处理 |
|------|------|
| 用户拒绝通知权限 | 静默保存日期，不调度，不报错 |
| 提醒时间已过 | 不调度，忽略 |
| App 未运行时到点 | 系统自动触发（UserNotifications 标准行为） |
| 修改提醒偏移 | 先 cancel 旧请求，再重新 schedule |

---

## 6. 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Models/TodoList.swift` | 新增 | TodoList SwiftData 模型 |
| `Models/TodoItem.swift` | 修改 | 新增 `dueDate`、`reminderOffset`、`reminderID`、`list` 字段 |
| `ViewModels/TodoStore.swift` | 修改 | 新增 list CRUD、`selectedListID`、`currentItems` 计算属性 |
| `Views/SidebarView.swift` | 修改 | 支持多清单、新建/重命名/删除/拖拽 |
| `Views/TaskRowView.swift` | 修改 | 新增优先级圆点、日历图标、日期 Popover |
| `Views/TaskListView.swift` | 修改 | `items` → `currentItems` |
| `App/DesktopTodoApp.swift` | 修改 | ModelContainer schema 加入 TodoList |
| `Services/NotificationService.swift` | 新增 | UserNotifications 封装 |

---

## 7. 不在 v1.1 范围内

- 状态栏模式（移至 v1.2+）
- 标签系统
- 子任务
- 搜索
- 智能列表（今天/最近7天）
