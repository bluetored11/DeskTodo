# DesktopTodo v1.0 设计文档

**日期**: 2026-06-24  
**范围**: v1.0 MVP — 单收件箱列表、增删改查、本地持久化、基础动画  
**Bundle ID**: com.bluetored.DesktopTodo  
**最低系统**: macOS 14+  
**项目生成**: XcodeGen 2.45.4

---

## 1. 架构

### 数据流

```
DesktopTodoApp
  └── ModelContainer（SwiftData，本地持久化）
        └── TodoStore（@Observable，注入 @Environment）
              └── Views（通过 @Environment(TodoStore.self) 消费）
```

- `ModelContainer` 在 App 入口创建，注入整个视图树
- `TodoStore` 持有 `ModelContext`，封装所有增删改查逻辑
- Views 只负责渲染和用户事件，不直接操作数据库
- SwiftData 自动持久化，无需手动调用 save

### 视图树

```
ContentView（NavigationSplitView）
  ├── SidebarView（左列，v1.0 固定只有「收件箱」）
  └── TaskListView（右列）
        ├── TaskInputView（顶部输入框，回车添加）
        └── List → TaskRowView × N（复选框 + 标题 + 删除）
```

---

## 2. 数据模型

```swift
@Model
class TodoItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var isCompleted: Bool
    var createdAt: Date
    var order: Int          // 拖拽排序依据
    var priority: Priority  // v1.0 存储，UI 暂不暴露
}

enum Priority: Int, Codable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
}
```

**v1.0 裁剪**：`dueDate`、`notes`、`tags`、`list` 关联关系不实现，v1.1+ 扩展。

---

## 3. 文件结构

```
DesktopTodo/
├── project.yml
└── DesktopTodo/
    ├── App/
    │   └── DesktopTodoApp.swift    # 入口，ModelContainer 配置
    ├── Models/
    │   └── TodoItem.swift          # SwiftData @Model
    ├── ViewModels/
    │   └── TodoStore.swift         # @Observable，增删改查+排序
    ├── Views/
    │   ├── ContentView.swift       # NavigationSplitView 容器
    │   ├── SidebarView.swift       # 左侧边栏（收件箱固定项）
    │   ├── TaskListView.swift      # 任务列表主区域
    │   ├── TaskRowView.swift       # 单行任务（复选框+文字+删除）
    │   └── TaskInputView.swift     # 顶部添加任务输入框
    └── Assets.xcassets
```

---

## 4. TodoStore 接口

```swift
@Observable
class TodoStore {
    // 查：按 order 排序的未完成 + 已完成任务
    var items: [TodoItem]

    // 增
    func addItem(title: String)

    // 改：切换完成状态
    func toggleComplete(_ item: TodoItem)

    // 改：更新标题（双击编辑）
    func updateTitle(_ item: TodoItem, title: String)

    // 删
    func deleteItem(_ item: TodoItem)

    // 排：拖拽后更新 order 字段
    func move(from: IndexSet, to: Int)
}
```

---

## 5. UI 与动画

- **设计语言**: macOS Sonoma，系统控件，跟随深浅色模式
- **窗口**: 标准可调整大小窗口，最小宽度 600pt
- **侧边栏**: `NavigationSplitView` 左列，固定宽度约 200pt
- **任务行**: hover 时显示删除按钮（`.onHover` 控制透明度）
- **双击编辑**: `TaskRowView` 内联 `TextField`，`isEditing` 状态切换
- **动画**:
  - 添加任务：`.transition(.asymmetric(insertion: .slide, removal: .opacity))`
  - 完成任务：复选框 `.scaleEffect` 弹簧动画 + 文字删除线渐变
  - 删除任务：`.transition(.opacity)` + `withAnimation(.spring())`

---

## 6. XcodeGen 配置要点（project.yml）

- target 类型: `application`，platform: `macOS`
- deploymentTarget: `14.0`
- Swift version: `6.0`
- 能力: `com.apple.developer.iCloud-container-identifiers`（暂不需要，不加）
- Info.plist: `NSPrincipalClass = NSApplication`

---

## 7. 键盘交互（v1.0 基础部分）

| 快捷键 | 行为 |
|--------|------|
| `Cmd + N` | 聚焦顶部输入框 |
| `Return`（输入框内） | 提交新任务 |
| `Space` | 选中任务时切换完成状态 |
| `Delete` | 选中任务时删除 |
| `Esc` | 取消内联编辑，恢复原文本 |
| `Return`（编辑模式） | 确认编辑并退出编辑状态 |

---

## 8. v1.0 范围外（明确不实现）

| 功能 | 规划版本 |
|------|---------|
| 多列表管理 | v1.1 |
| 优先级 UI | v1.1 |
| 截止日期 + 提醒 | v1.1 |
| 状态栏模式 | v1.1 |
| 全局快捷键 | v1.2 |
| 搜索 | v1.2 |
| 标签、子任务 | v1.2 |
| 数据导入导出 | v1.3 |
