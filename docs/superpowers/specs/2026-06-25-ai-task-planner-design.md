# DesktopTodo AI 任务规划设计文档

**日期**: 2026-06-25  
**范围**: v1.3 — AI 任务规划（接入 OpenAI GPT-4o mini，流式生成子步骤）  
**基于**: v1.2（子任务功能）  
**最低系统**: macOS 14+

---

## 1. 功能范围

| 功能 | 说明 |
|------|------|
| AI 规划入口 | TaskInputView 旁的 ✨ 按钮，点击弹出 Sheet |
| 任务描述输入 | 用户用自然语言描述任务 |
| 流式生成预览 | GPT-4o mini 实时流式返回任务标题 + 子步骤，逐行展示 |
| 预览编辑 | 生成期间和生成后均可删除单条步骤 |
| 确认写入 | 用户点「添加到列表」后创建 TodoItem + SubTask |
| API Key 管理 | ⌘, 打开 Preferences，SecureField 输入，存入 macOS Keychain |

**不在 v1.3 范围内**：多轮对话、历史记录、自定义 Prompt、非 OpenAI 模型

---

## 2. 架构

### 2.1 数据流

```
TaskInputView
  └─ [✨ 按钮] ──→ AIPlannerSheet (.sheet)
                        │
              用户输入任务描述
                        │
              [开始规划] 按钮触发
                        │
              OpenAIService.streamPlan(description:)
                AsyncThrowingStream<String, Error>
                        │
              逐行 yield → AIPlannerSheet.steps[]
                        │
              用户确认 [添加到列表]
                        │
              TodoStore.addItemWithSubTasks(title:subtaskTitles:)
                        │
              SwiftData 写入（TodoItem + [SubTask]）
```

### 2.2 新增文件

| 文件 | 职责 |
|------|------|
| `Services/OpenAIService.swift` | OpenAI HTTP 客户端，SSE 流式解析，yield 完整行 |
| `Services/KeychainService.swift` | Keychain 存取 API Key 封装（Security.framework）|
| `Views/AIPlannerSheet.swift` | AI 规划 Sheet UI（输入 + 流式预览 + 确认）|
| `Views/SettingsView.swift` | API Key 设置页（SecureField + 保存到 Keychain）|

### 2.3 修改文件

| 文件 | 变更 |
|------|------|
| `App/DesktopTodoApp.swift` | 添加 `Settings` scene，注册 SettingsView |
| `Views/TaskInputView.swift` | `+` 图标旁添加 ✨ 按钮，`.sheet(isPresented:)` |
| `ViewModels/TodoStore.swift` | 新增 `addItemWithSubTasks(title:subtaskTitles:)` |

---

## 3. Services

### 3.1 OpenAIService

```swift
final class OpenAIService {
    static let shared = OpenAIService()
    private init() {}

    /// 流式规划。每 yield 一个 String = AI 生成了完整的一行文字。
    /// 第一行为任务标题，后续每行为一个步骤。
    func streamPlan(description: String) -> AsyncThrowingStream<String, Error>
}
```

**API 调用参数**：
- Endpoint: `POST https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o-mini`
- `stream: true`
- `max_tokens: 512`
- API Key 从 `KeychainService.shared.loadAPIKey()` 读取，注入 `Authorization: Bearer` Header

**SSE 解析**：
- 按行读取响应字节流
- 跳过空行和 `data: [DONE]`
- 解码 `data: {...}` 中的 `choices[0].delta.content`
- 拼接 delta 到缓冲区，遇到换行符 `\n` 时 yield 当前行并清空缓冲区
- 流结束时若缓冲区非空，yield 最后一行

**System Prompt（固定，不可配置）**：

```
你是一个任务规划助手。将用户描述的任务拆解为 3-7 个具体可执行的步骤。
输出格式（严格遵守）：
- 第一行：任务标题（不超过 20 字，不含序号）
- 后续每行：一个步骤（不含序号、符号、标点前缀）
不要有任何前言、解释或额外说明，直接输出内容。
```

### 3.2 KeychainService

```swift
final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let service = "DesktopTodo.OpenAI"
    private let account = "openai-api-key"

    func save(apiKey: String) throws    // SecItemAdd / SecItemUpdate
    func loadAPIKey() -> String?        // SecItemCopyMatching；nil = 未设置
    func deleteAPIKey() throws          // SecItemDelete
}
```

---

## 4. TodoStore 新增方法

```swift
func addItemWithSubTasks(title: String, subtaskTitles: [String]) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
    guard !trimmedTitle.isEmpty else { return }

    // 复用现有 addItem 逻辑创建父任务
    let maxOrder = (items.map(\.order).max() ?? -1) + 1
    let item = TodoItem(title: trimmedTitle, order: maxOrder)
    if let id = selectedListID,
       let list = lists.first(where: { $0.id == id }) {
        item.list = list
    }
    context.insert(item)

    // 批量创建子任务
    for (index, subTitle) in subtaskTitles.enumerated() {
        let trimmed = subTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let sub = SubTask(title: trimmed, order: index)
        sub.item = item
        context.insert(sub)
    }

    fetch()
}
```

---

## 5. 界面设计

### 5.1 TaskInputView 修改

在 `+` 图标**左侧**添加 ✨ 按钮（使用 `wand.and.stars` SF Symbol）：

```swift
// 新增 @State
@State private var showAIPlanner = false

// 在 HStack 最左侧添加（现有 + 图标之前）
Button { showAIPlanner = true } label: {
    Image(systemName: "wand.and.stars")
        .foregroundStyle(.purple)
        .font(.title3)
}
.buttonStyle(.plain)
.help("AI 任务规划")
.sheet(isPresented: $showAIPlanner) {
    AIPlannerSheet()
        .environment(store)
}
```

未设置 API Key 时点击，Sheet 内部处理提示（不在 TaskInputView 层判断）。

### 5.2 AIPlannerSheet

#### 状态机

```
初始态（输入）
    │ [开始规划] 点击
    ▼
生成中（流式）─── 网络/API 错误 ───→ 错误态
    │ 流结束
    ▼
预览态（可编辑）
    │ [添加到列表]
    ▼
关闭（写入完成）
```

#### 界面布局

**阶段一：输入**
```
✨ AI 任务规划                           [×]
────────────────────────────────────────
描述你想完成的事：
┌──────────────────────────────────────┐
│ 准备下周的项目汇报                     │
└──────────────────────────────────────┘
                               [开始规划 →]
```

**阶段二：流式生成中 / 预览**
```
✨ AI 任务规划                           [×]
────────────────────────────────────────
描述你想完成的事：
[准备下周的项目汇报]          [重新规划 ↺]

📋 准备下周的项目汇报
  · 收集过去季度数据和指标              [×]
  · 确定汇报核心结论                    [×]
  · 制作 PPT 框架                      [×]
  · 撰写各页说明文字…（生成中）
────────────────────────────────────────
[取消]                         [添加到列表]
```

**交互细节**：
- `planTitle`（第一行）展示为 `📋 标题`，不可在预览中编辑（可重新规划）
- 每条步骤右侧 `[×]` 可删除（流式期间也生效）
- `[添加到列表]` 在 `steps.count >= 1` 时可点击（流式生成中也可提前确认）
- 点击 `[重新规划]` 取消当前流、清空 steps、重新发起请求
- 点击 Sheet `[×]` 或取消按钮：取消正在进行的 `Task`

#### 关键 State

```swift
struct AIPlannerSheet: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var description = ""      // 用户输入
    @State private var planTitle = ""        // AI 第一行（任务标题）
    @State private var steps: [String] = []  // AI 后续行（步骤）
    @State private var isStreaming = false   // 是否正在流式生成
    @State private var errorMessage: String? // 错误提示
    @State private var streamTask: Task<Void, Never>? // 用于取消
}
```

### 5.3 SettingsView

```
API 配置
────────────────────────────────────────
OpenAI API Key
[sk-...                      ][👁] [保存]
Key 将安全存储在系统 Keychain 中

获取 API Key → api.openai.com  （可点击链接）
```

- 字段：`SecureField`，旁边 👁 按钮切换显示/隐藏（`@State private var isRevealed`）
- 「保存」调用 `KeychainService.shared.save(apiKey:)`，成功显示「✓ 已保存」短暂提示
- 启动时读取现有 Key 填入字段（`*` 掩码显示）

---

## 6. 错误处理

| 情况 | 处理 |
|------|------|
| 未设置 API Key | Sheet 显示「请先在设置中填写 OpenAI API Key」+ 「打开设置」按钮（`SettingsLink()`）|
| 网络不可用 | 显示「网络连接失败，请检查网络」+ 「重试」|
| API Key 无效（401）| 显示「API Key 无效，请检查设置」|
| 超额/限流（429）| 显示「请求过于频繁，请稍后重试」|
| 空响应 / 无有效步骤 | 显示「未能生成步骤，请重新描述或换个角度」|
| 生成中断（网络断开）| 保留已生成步骤，显示「生成中断，可使用已有步骤」|
| 用户关闭 Sheet | 调用 `streamTask?.cancel()`，丢弃内容 |

---

## 7. 文件变更清单

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `Services/OpenAIService.swift` | **新增** | SSE 流式客户端 |
| `Services/KeychainService.swift` | **新增** | Keychain 封装 |
| `Views/AIPlannerSheet.swift` | **新增** | AI 规划 Sheet |
| `Views/SettingsView.swift` | **新增** | API Key 设置页 |
| `App/DesktopTodoApp.swift` | 修改 | 添加 Settings scene |
| `Views/TaskInputView.swift` | 修改 | 添加 ✨ 按钮 + sheet |
| `ViewModels/TodoStore.swift` | 修改 | 新增 `addItemWithSubTasks` |

---

## 8. 不在 v1.3 范围内

- 多轮对话（根据用户反馈改写步骤）
- 任务描述历史记录
- 自定义 System Prompt
- 非 OpenAI 模型支持（Anthropic、Ollama 等）
- 步骤的拖拽排序（预览时）
- 步骤内容的行内编辑（删除后可重新规划）
