# AI 任务规划 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 接入 OpenAI GPT-4o mini，用户描述任务后 AI 流式生成子步骤，预览确认后写入 TodoItem + SubTask。

**Architecture:** 新增 `KeychainService`（API Key 存取）和 `OpenAIService`（SSE 流式客户端）作为独立 Service 层；`AIPlannerSheet` 持有流式状态，通过 `TodoStore.addItemWithSubTasks` 原子写入；入口在 `TaskInputView` 的 ✨ 按钮触发 `.sheet`。

**Tech Stack:** Swift 6.0、SwiftUI、SwiftData、Security.framework（Keychain）、URLSession async bytes（SSE）、macOS 14+、XCTest

## Global Constraints

- macOS 14.0+，Swift 6.0，`SWIFT_STRICT_CONCURRENCY: complete`
- 零第三方依赖：只用 Apple SDK（Security、URLSession、Foundation、SwiftUI）
- OpenAI model: `gpt-4o-mini`，endpoint: `https://api.openai.com/v1/chat/completions`
- Keychain service name: `"DesktopTodo.OpenAI"`，account: `"openai-api-key"`
- `KeychainService` 和 `OpenAIService` 标记 `@unchecked Sendable`（两者均无可变状态）
- 新增 Swift 文件后必须运行 `xcodegen generate` 更新 xcodeproj
- 构建命令：`xcodebuild build -project DesktopTodo.xcodeproj -scheme DesktopTodo -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5`
- 测试命令：`xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10`

---

## File Map

| 文件 | 变更 | 职责 |
|------|------|------|
| `DesktopTodo/Services/KeychainService.swift` | **新增** | Keychain 存取 API Key |
| `DesktopTodo/Services/OpenAIService.swift` | **新增** | SSE 流式 OpenAI 客户端，可测试静态解析方法 |
| `DesktopTodo/Views/SettingsView.swift` | **新增** | API Key 设置页 |
| `DesktopTodo/Views/AIPlannerSheet.swift` | **新增** | AI 规划 Sheet UI，流式状态机 |
| `DesktopTodo/ViewModels/TodoStore.swift` | 修改 | 新增 `addItemWithSubTasks(title:subtaskTitles:)` |
| `DesktopTodo/App/DesktopTodoApp.swift` | 修改 | 添加 `Settings` scene |
| `DesktopTodo/Views/TaskInputView.swift` | 修改 | 添加 ✨ 按钮 + `.sheet(isPresented:)` |
| `DesktopTodoTests/KeychainServiceTests.swift` | **新增** | Keychain 集成测试 |
| `DesktopTodoTests/OpenAIServiceTests.swift` | **新增** | SSE 解析单元测试 |

---

## Task 1: KeychainService

**Files:**
- Create: `DesktopTodo/Services/KeychainService.swift`
- Create: `DesktopTodoTests/KeychainServiceTests.swift`

**Interfaces:**
- Produces:
  - `KeychainService.shared` — singleton
  - `func save(apiKey: String) throws`
  - `func loadAPIKey() -> String?` — nil = 未设置
  - `func deleteAPIKey() throws` — idempotent，不存在不报错
  - `enum KeychainError: LocalizedError`

---

- [ ] **Step 1: 写失败测试**

  创建 `DesktopTodoTests/KeychainServiceTests.swift`：

  ```swift
  import XCTest
  @testable import DesktopTodo

  final class KeychainServiceTests: XCTestCase {
      override func tearDown() async throws {
          try? KeychainService.shared.deleteAPIKey()
      }

      func testSaveAndLoadAPIKey() throws {
          try KeychainService.shared.save(apiKey: "sk-test-key-123")
          XCTAssertEqual(KeychainService.shared.loadAPIKey(), "sk-test-key-123")
      }

      func testOverwriteExistingKey() throws {
          try KeychainService.shared.save(apiKey: "sk-first")
          try KeychainService.shared.save(apiKey: "sk-second")
          XCTAssertEqual(KeychainService.shared.loadAPIKey(), "sk-second")
      }

      func testLoadMissingKeyReturnsNil() throws {
          try KeychainService.shared.deleteAPIKey()
          XCTAssertNil(KeychainService.shared.loadAPIKey())
      }

      func testDeleteNonExistentKeyDoesNotThrow() {
          XCTAssertNoThrow(try KeychainService.shared.deleteAPIKey())
      }
  }
  ```

- [ ] **Step 2: 运行测试，确认编译失败**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: 编译错误 — `cannot find type 'KeychainService' in scope`

- [ ] **Step 3: 实现 KeychainService**

  创建 `DesktopTodo/Services/KeychainService.swift`：

  ```swift
  import Foundation
  import Security

  enum KeychainError: LocalizedError {
      case encodingFailed
      case saveFailed(OSStatus)
      case deleteFailed(OSStatus)

      var errorDescription: String? {
          switch self {
          case .encodingFailed:       return "无法编码 API Key"
          case .saveFailed(let s):    return "保存失败（错误码 \(s)）"
          case .deleteFailed(let s):  return "删除失败（错误码 \(s)）"
          }
      }
  }

  final class KeychainService: @unchecked Sendable {
      static let shared = KeychainService()
      private init() {}

      private let service = "DesktopTodo.OpenAI"
      private let account = "openai-api-key"

      func save(apiKey: String) throws {
          guard let data = apiKey.data(using: .utf8) else {
              throw KeychainError.encodingFailed
          }
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account
          ]
          let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
          if updateStatus == errSecItemNotFound {
              var addQuery = query
              addQuery[kSecValueData] = data
              let status = SecItemAdd(addQuery as CFDictionary, nil)
              guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
          } else if updateStatus != errSecSuccess {
              throw KeychainError.saveFailed(updateStatus)
          }
      }

      func loadAPIKey() -> String? {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account,
              kSecReturnData: true,
              kSecMatchLimit: kSecMatchLimitOne
          ]
          var result: AnyObject?
          let status = SecItemCopyMatching(query as CFDictionary, &result)
          guard status == errSecSuccess,
                let data = result as? Data,
                let key = String(data: data, encoding: .utf8) else { return nil }
          return key
      }

      func deleteAPIKey() throws {
          let query: [CFString: Any] = [
              kSecClass: kSecClassGenericPassword,
              kSecAttrService: service,
              kSecAttrAccount: account
          ]
          let status = SecItemDelete(query as CFDictionary)
          guard status == errSecSuccess || status == errSecItemNotFound else {
              throw KeychainError.deleteFailed(status)
          }
      }
  }
  ```

- [ ] **Step 4: 运行 xcodegen + 测试**

  ```bash
  cd /Users/zhuyecun/Documents/code/toDoList
  xcodegen generate
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`，所有测试（含原有 23 个）通过

- [ ] **Step 5: 提交**

  ```bash
  git add DesktopTodo/Services/KeychainService.swift \
          DesktopTodoTests/KeychainServiceTests.swift \
          DesktopTodo.xcodeproj
  git commit -m "feat: KeychainService — save/load/delete API key in macOS Keychain"
  ```

---

## Task 2: OpenAIService

**Files:**
- Create: `DesktopTodo/Services/OpenAIService.swift`
- Create: `DesktopTodoTests/OpenAIServiceTests.swift`

**Interfaces:**
- Consumes: `KeychainService.shared.loadAPIKey()` from Task 1
- Produces:
  - `OpenAIService.shared` — singleton
  - `func streamPlan(description: String) -> AsyncThrowingStream<String, Error>` — 每 yield 一个 String = 完整一行（第一行为任务标题，后续为步骤）
  - `static func parseSSELine(_ line: String) -> String?` — 可测试
  - `static func extractLines(buffer: String, appending: String) -> (lines: [String], remaining: String)` — 可测试
  - `enum OpenAIError: Error`

---

- [ ] **Step 1: 写失败测试**

  创建 `DesktopTodoTests/OpenAIServiceTests.swift`：

  ```swift
  import XCTest
  @testable import DesktopTodo

  final class OpenAIServiceTests: XCTestCase {

      // MARK: - parseSSELine

      func testParseSSELine_validDelta() {
          let line = #"data: {"id":"c1","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}"#
          XCTAssertEqual(OpenAIService.parseSSELine(line), "Hello")
      }

      func testParseSSELine_done() {
          XCTAssertNil(OpenAIService.parseSSELine("data: [DONE]"))
      }

      func testParseSSELine_emptyDelta() {
          let line = #"data: {"id":"c1","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}"#
          XCTAssertNil(OpenAIService.parseSSELine(line))
      }

      func testParseSSELine_emptyLine() {
          XCTAssertNil(OpenAIService.parseSSELine(""))
      }

      func testParseSSELine_commentLine() {
          XCTAssertNil(OpenAIService.parseSSELine(": ping"))
      }

      // MARK: - extractLines

      func testExtractLines_singleComplete() {
          let (lines, remaining) = OpenAIService.extractLines(buffer: "", appending: "准备汇报\n")
          XCTAssertEqual(lines, ["准备汇报"])
          XCTAssertEqual(remaining, "")
      }

      func testExtractLines_multipleLines() {
          let (lines, remaining) = OpenAIService.extractLines(
              buffer: "准备汇报\n收集数",
              appending: "据\n制作PPT"
          )
          XCTAssertEqual(lines, ["准备汇报", "收集数据"])
          XCTAssertEqual(remaining, "制作PPT")
      }

      func testExtractLines_noNewline() {
          let (lines, remaining) = OpenAIService.extractLines(buffer: "准备", appending: "汇报")
          XCTAssertEqual(lines, [])
          XCTAssertEqual(remaining, "准备汇报")
      }

      func testExtractLines_emptyLinesSkipped() {
          let (lines, _) = OpenAIService.extractLines(buffer: "", appending: "\n第一步\n\n第二步\n")
          XCTAssertEqual(lines, ["第一步", "第二步"])
      }

      func testExtractLines_trailingBufferPreserved() {
          let (lines, remaining) = OpenAIService.extractLines(buffer: "", appending: "第一步\n第二步")
          XCTAssertEqual(lines, ["第一步"])
          XCTAssertEqual(remaining, "第二步")
      }
  }
  ```

- [ ] **Step 2: 运行测试，确认编译失败**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: 编译错误 — `cannot find type 'OpenAIService' in scope`

- [ ] **Step 3: 实现 OpenAIService**

  创建 `DesktopTodo/Services/OpenAIService.swift`：

  ```swift
  import Foundation

  // MARK: - Errors

  enum OpenAIError: Error {
      case noAPIKey
      case invalidResponse
      case httpError(Int)
  }

  // MARK: - Codable types

  private struct OpenAIRequest: Encodable {
      struct Message: Encodable {
          let role: String
          let content: String
      }
      let model: String
      let messages: [Message]
      let stream: Bool
      let maxTokens: Int
      enum CodingKeys: String, CodingKey {
          case model, messages, stream
          case maxTokens = "max_tokens"
      }
  }

  struct OpenAIChunk: Decodable {
      struct Choice: Decodable {
          struct Delta: Decodable { let content: String? }
          let delta: Delta
      }
      let choices: [Choice]
  }

  // MARK: - Service

  final class OpenAIService: @unchecked Sendable {
      static let shared = OpenAIService()
      private init() {}

      private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

      private static let systemPrompt = """
          你是一个任务规划助手。将用户描述的任务拆解为 3-7 个具体可执行的步骤。
          输出格式（严格遵守）：
          - 第一行：任务标题（不超过 20 字，不含序号）
          - 后续每行：一个步骤（不含序号、符号、标点前缀）
          不要有任何前言、解释或额外说明，直接输出内容。
          """

      // MARK: - Testable static helpers

      static func parseSSELine(_ line: String) -> String? {
          guard line.hasPrefix("data: ") else { return nil }
          let jsonStr = String(line.dropFirst(6))
          guard jsonStr != "[DONE]",
                let data = jsonStr.data(using: .utf8),
                let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data),
                let content = chunk.choices.first?.delta.content else { return nil }
          return content
      }

      static func extractLines(buffer: String, appending content: String) -> (lines: [String], remaining: String) {
          var buf = buffer + content
          var lines: [String] = []
          while let newlineIndex = buf.firstIndex(of: "\n") {
              let line = String(buf[buf.startIndex..<newlineIndex])
              if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                  lines.append(line)
              }
              buf = String(buf[buf.index(after: newlineIndex)...])
          }
          return (lines, buf)
      }

      // MARK: - Stream

      func streamPlan(description: String) -> AsyncThrowingStream<String, Error> {
          AsyncThrowingStream { continuation in
              let task = Task {
                  do {
                      guard let apiKey = KeychainService.shared.loadAPIKey(), !apiKey.isEmpty else {
                          continuation.finish(throwing: OpenAIError.noAPIKey)
                          return
                      }

                      var request = URLRequest(url: OpenAIService.endpoint)
                      request.httpMethod = "POST"
                      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                      request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                      let body = OpenAIRequest(
                          model: "gpt-4o-mini",
                          messages: [
                              .init(role: "system", content: OpenAIService.systemPrompt),
                              .init(role: "user", content: description)
                          ],
                          stream: true,
                          maxTokens: 512
                      )
                      request.httpBody = try JSONEncoder().encode(body)

                      let (bytes, response) = try await URLSession.shared.bytes(for: request)
                      guard let http = response as? HTTPURLResponse else {
                          continuation.finish(throwing: OpenAIError.invalidResponse)
                          return
                      }
                      guard http.statusCode == 200 else {
                          continuation.finish(throwing: OpenAIError.httpError(http.statusCode))
                          return
                      }

                      var buffer = ""
                      for try await line in bytes.lines {
                          guard !Task.isCancelled else { break }
                          guard let content = OpenAIService.parseSSELine(line) else { continue }
                          let (newLines, newBuf) = OpenAIService.extractLines(buffer: buffer, appending: content)
                          buffer = newBuf
                          for extracted in newLines { continuation.yield(extracted) }
                      }
                      // Flush remaining buffer
                      let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                      if !trimmed.isEmpty { continuation.yield(trimmed) }
                      continuation.finish()
                  } catch {
                      continuation.finish(throwing: error)
                  }
              }
              continuation.onTermination = { _ in task.cancel() }
          }
      }
  }
  ```

- [ ] **Step 4: 运行 xcodegen + 测试**

  ```bash
  cd /Users/zhuyecun/Documents/code/toDoList
  xcodegen generate
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`，所有 OpenAIService 测试通过

- [ ] **Step 5: 提交**

  ```bash
  git add DesktopTodo/Services/OpenAIService.swift \
          DesktopTodoTests/OpenAIServiceTests.swift \
          DesktopTodo.xcodeproj
  git commit -m "feat: OpenAIService — SSE streaming client with testable parseSSELine/extractLines"
  ```

---

## Task 3: TodoStore.addItemWithSubTasks

**Files:**
- Modify: `DesktopTodo/ViewModels/TodoStore.swift`
- Modify: `DesktopTodoTests/TodoStoreTests.swift`

**Interfaces:**
- Consumes: existing `TodoStore` state, `SubTask.init(title:order:)` from v1.2
- Produces: `func addItemWithSubTasks(title: String, subtaskTitles: [String])`

---

- [ ] **Step 1: 写失败测试**

  在 `DesktopTodoTests/TodoStoreTests.swift` 末尾追加（在类的最后一个 `}`前）：

  ```swift
  // MARK: - addItemWithSubTasks

  func testAddItemWithSubTasks_createsParentAndChildren() {
      store.addItemWithSubTasks(title: "汇报", subtaskTitles: ["收集数据", "制作PPT"])
      XCTAssertEqual(store.items.count, 1)
      XCTAssertEqual(store.items[0].title, "汇报")
      XCTAssertEqual(store.items[0].subtasks?.count, 2)
  }

  func testAddItemWithSubTasks_subtaskTitlesInOrder() {
      store.addItemWithSubTasks(title: "任务", subtaskTitles: ["步骤1", "步骤2", "步骤3"])
      let subs = (store.items[0].subtasks ?? []).sorted { $0.order < $1.order }
      XCTAssertEqual(subs.map(\.title), ["步骤1", "步骤2", "步骤3"])
      XCTAssertEqual(subs.map(\.order), [0, 1, 2])
  }

  func testAddItemWithSubTasks_ignoresEmptyTitle() {
      store.addItemWithSubTasks(title: "  ", subtaskTitles: ["步骤1"])
      XCTAssertEqual(store.items.count, 0)
  }

  func testAddItemWithSubTasks_skipsBlankSubtasks() {
      store.addItemWithSubTasks(title: "任务", subtaskTitles: ["步骤1", "  ", "步骤2"])
      XCTAssertEqual(store.items[0].subtasks?.count, 2)
  }

  func testAddItemWithSubTasks_respectsSelectedList() {
      store.createList(name: "工作")
      store.selectedListID = store.lists[0].id
      store.addItemWithSubTasks(title: "任务", subtaskTitles: ["步骤1"])
      XCTAssertEqual(store.currentItems.count, 1)
      XCTAssertEqual(store.currentItems[0].list?.name, "工作")
  }
  ```

- [ ] **Step 2: 运行测试，确认失败**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: 编译错误 — `has no member 'addItemWithSubTasks'`

- [ ] **Step 3: 在 TodoStore.swift 新增方法**

  在 `// MARK: - Sub-task CRUD` 区块前，添加新的 MARK 区块和方法：

  ```swift
  // MARK: - AI task creation

  func addItemWithSubTasks(title: String, subtaskTitles: [String]) {
      let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
      guard !trimmedTitle.isEmpty else { return }

      let maxOrder = (items.map(\.order).max() ?? -1) + 1
      let item = TodoItem(title: trimmedTitle, order: maxOrder)
      if let id = selectedListID,
         let list = lists.first(where: { $0.id == id }) {
          item.list = list
      }
      context.insert(item)

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

- [ ] **Step 4: 运行测试，确认通过**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`，全部测试通过

- [ ] **Step 5: 提交**

  ```bash
  git add DesktopTodo/ViewModels/TodoStore.swift \
          DesktopTodoTests/TodoStoreTests.swift
  git commit -m "feat: TodoStore.addItemWithSubTasks — atomic create parent + children"
  ```

---

## Task 4: SettingsView + Settings scene

**Files:**
- Create: `DesktopTodo/Views/SettingsView.swift`
- Modify: `DesktopTodo/App/DesktopTodoApp.swift`

**Interfaces:**
- Consumes: `KeychainService.shared` from Task 1
- Produces: `SettingsView` — 可在 `Settings` scene 和 `SettingsLink` 中使用

---

- [ ] **Step 1: 创建 SettingsView.swift**

  创建 `DesktopTodo/Views/SettingsView.swift`：

  ```swift
  import SwiftUI

  struct SettingsView: View {
      @State private var apiKey = ""
      @State private var isRevealed = false
      @State private var saveStatus: SaveStatus = .idle

      enum SaveStatus: Equatable { case idle, saved, failed }

      var body: some View {
          Form {
              Section("OpenAI API 配置") {
                  HStack {
                      Group {
                          if isRevealed {
                              TextField("sk-...", text: $apiKey)
                          } else {
                              SecureField("sk-...", text: $apiKey)
                          }
                      }
                      .textFieldStyle(.roundedBorder)

                      Button {
                          isRevealed.toggle()
                      } label: {
                          Image(systemName: isRevealed ? "eye.slash" : "eye")
                      }
                      .buttonStyle(.borderless)

                      Button("保存") { saveKey() }
                          .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                  }

                  if saveStatus == .saved {
                      Label("已保存", systemImage: "checkmark.circle.fill")
                          .foregroundStyle(.green)
                          .font(.caption)
                  } else if saveStatus == .failed {
                      Label("保存失败，请重试", systemImage: "xmark.circle.fill")
                          .foregroundStyle(.red)
                          .font(.caption)
                  }

                  Text("API Key 将安全存储在系统 Keychain 中")
                      .font(.caption)
                      .foregroundStyle(.secondary)

                  Link("获取 OpenAI API Key →",
                       destination: URL(string: "https://platform.openai.com/api-keys")!)
                      .font(.caption)
              }
          }
          .formStyle(.grouped)
          .frame(width: 440, height: 200)
          .onAppear {
              if let existing = KeychainService.shared.loadAPIKey() {
                  apiKey = existing
              }
          }
      }

      private func saveKey() {
          do {
              try KeychainService.shared.save(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
              saveStatus = .saved
              Task {
                  try? await Task.sleep(for: .seconds(2))
                  saveStatus = .idle
              }
          } catch {
              saveStatus = .failed
          }
      }
  }
  ```

- [ ] **Step 2: 修改 DesktopTodoApp.swift — 添加 Settings scene**

  完整替换 `DesktopTodo/App/DesktopTodoApp.swift`：

  ```swift
  import SwiftUI
  import SwiftData

  @main
  struct DesktopTodoApp: App {
      private let container: ModelContainer = {
          let schema = Schema([TodoItem.self, TodoList.self, SubTask.self])
          let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
          do {
              return try ModelContainer(for: schema, configurations: [config])
          } catch {
              assertionFailure("ModelContainer failed: \(error)")
              let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
              return try! ModelContainer(for: schema, configurations: [fallback])
          }
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

          Settings {
              SettingsView()
          }
      }
  }

  extension Notification.Name {
      static let focusTaskInput = Notification.Name("focusTaskInput")
  }
  ```

- [ ] **Step 3: 运行 xcodegen + 构建**

  ```bash
  cd /Users/zhuyecun/Documents/code/toDoList
  xcodegen generate
  xcodebuild build -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: 运行全部测试**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

  ```bash
  git add DesktopTodo/Views/SettingsView.swift \
          DesktopTodo/App/DesktopTodoApp.swift \
          DesktopTodo.xcodeproj
  git commit -m "feat: SettingsView with Keychain API Key, Settings scene (Cmd+,)"
  ```

---

## Task 5: AIPlannerSheet

**Files:**
- Create: `DesktopTodo/Views/AIPlannerSheet.swift`

**Interfaces:**
- Consumes:
  - `OpenAIService.shared.streamPlan(description:) -> AsyncThrowingStream<String, Error>` from Task 2
  - `TodoStore.addItemWithSubTasks(title:subtaskTitles:)` from Task 3
  - `KeychainService.shared.loadAPIKey() -> String?` from Task 1
  - `SettingsView` from Task 4 (for `SettingsLink`)
- Produces: `AIPlannerSheet` — View, requires `@Environment(TodoStore.self)`

---

- [ ] **Step 1: 创建 AIPlannerSheet.swift**

  创建 `DesktopTodo/Views/AIPlannerSheet.swift`：

  ```swift
  import SwiftUI

  @MainActor
  struct AIPlannerSheet: View {
      @Environment(TodoStore.self) private var store
      @Environment(\.dismiss) private var dismiss

      @State private var description = ""
      @State private var planTitle = ""
      @State private var steps: [String] = []
      @State private var isStreaming = false
      @State private var errorMessage: String?
      @State private var hasGenerated = false
      @State private var streamTask: Task<Void, Never>?

      var body: some View {
          VStack(spacing: 0) {
              // ── Header ────────────────────────────────────────────────────
              HStack {
                  Label("AI 任务规划", systemImage: "wand.and.stars")
                      .font(.headline)
                  Spacer()
                  Button {
                      cancelStream()
                      dismiss()
                  } label: {
                      Image(systemName: "xmark.circle.fill")
                          .foregroundStyle(.secondary)
                          .font(.title3)
                  }
                  .buttonStyle(.plain)
              }
              .padding()

              Divider()

              // ── Scrollable body ───────────────────────────────────────────
              ScrollView {
                  VStack(alignment: .leading, spacing: 16) {

                      // Description input row
                      VStack(alignment: .leading, spacing: 6) {
                          Text("描述你想完成的事：")
                              .font(.subheadline)
                              .foregroundStyle(.secondary)
                          HStack(alignment: .top) {
                              TextField("例如：准备下周的项目汇报", text: $description, axis: .vertical)
                                  .textFieldStyle(.plain)
                                  .lineLimit(1...3)
                                  .disabled(isStreaming)
                              Button(hasGenerated ? "重新规划" : "开始规划") {
                                  startPlanning()
                              }
                              .buttonStyle(.borderedProminent)
                              .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isStreaming)
                          }
                          .padding(10)
                          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                      }

                      // No API key warning
                      if KeychainService.shared.loadAPIKey() == nil {
                          HStack(spacing: 8) {
                              Image(systemName: "key.fill").foregroundStyle(.orange)
                              Text("请先在设置中填写 OpenAI API Key")
                                  .font(.callout)
                              Spacer()
                              SettingsLink { Text("打开设置").font(.callout) }
                          }
                          .padding(10)
                          .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                      }

                      // Error banner
                      if let msg = errorMessage {
                          HStack(spacing: 8) {
                              Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                              Text(msg).font(.callout).foregroundStyle(.red)
                              Spacer()
                              Button("重试") { startPlanning() }.font(.callout)
                          }
                          .padding(10)
                          .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                      }

                      // Preview card
                      if !planTitle.isEmpty || !steps.isEmpty || isStreaming {
                          VStack(alignment: .leading, spacing: 8) {
                              if !planTitle.isEmpty {
                                  Label(planTitle, systemImage: "doc.text")
                                      .font(.headline)
                              }

                              ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                                  HStack {
                                      Text("·").foregroundStyle(.tertiary)
                                      Text(step)
                                      Spacer()
                                      // Allow delete for all steps except the last one still streaming
                                      if !isStreaming || index < steps.count - 1 {
                                          Button {
                                              steps.remove(at: index)
                                          } label: {
                                              Image(systemName: "xmark")
                                                  .font(.caption)
                                                  .foregroundStyle(.secondary)
                                          }
                                          .buttonStyle(.plain)
                                      }
                                  }
                              }

                              if isStreaming {
                                  HStack(spacing: 6) {
                                      ProgressView().scaleEffect(0.6)
                                      Text("生成中…")
                                          .font(.caption)
                                          .foregroundStyle(.secondary)
                                  }
                              }
                          }
                          .padding(12)
                          .frame(maxWidth: .infinity, alignment: .leading)
                          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                      }
                  }
                  .padding()
              }

              Divider()

              // ── Footer ────────────────────────────────────────────────────
              HStack {
                  Button("取消") {
                      cancelStream()
                      dismiss()
                  }
                  .keyboardShortcut(.escape)

                  Spacer()

                  Button("添加到列表") {
                      addToList()
                      dismiss()
                  }
                  .buttonStyle(.borderedProminent)
                  .disabled(steps.isEmpty)
              }
              .padding()
          }
          .frame(width: 440, height: 500)
          .onDisappear { cancelStream() }
      }

      // MARK: - Actions

      private func startPlanning() {
          cancelStream()
          planTitle = ""
          steps = []
          errorMessage = nil
          isStreaming = true
          hasGenerated = true

          streamTask = Task {
              do {
                  var lineCount = 0
                  for try await line in OpenAIService.shared.streamPlan(description: description) {
                      guard !Task.isCancelled else { break }
                      if lineCount == 0 {
                          planTitle = line
                      } else {
                          steps.append(line)
                      }
                      lineCount += 1
                  }
                  isStreaming = false
              } catch is CancellationError {
                  isStreaming = false
              } catch {
                  isStreaming = false
                  errorMessage = friendlyError(error)
              }
          }
      }

      private func cancelStream() {
          streamTask?.cancel()
          streamTask = nil
          isStreaming = false
      }

      private func addToList() {
          guard !steps.isEmpty else { return }
          let title = planTitle.isEmpty ? description : planTitle
          store.addItemWithSubTasks(
              title: title.trimmingCharacters(in: .whitespaces),
              subtaskTitles: steps
          )
      }

      private func friendlyError(_ error: Error) -> String {
          if let e = error as? OpenAIError {
              switch e {
              case .noAPIKey:          return "请先在设置中填写 OpenAI API Key"
              case .httpError(401):    return "API Key 无效，请检查设置"
              case .httpError(429):    return "请求过于频繁，请稍后重试"
              case .httpError(let c):  return "API 请求失败（错误码 \(c)）"
              case .invalidResponse:   return "服务器返回异常响应"
              }
          }
          if (error as NSError).domain == NSURLErrorDomain {
              return "网络连接失败，请检查网络"
          }
          return "生成失败：\(error.localizedDescription)"
      }
  }
  ```

- [ ] **Step 2: 运行 xcodegen + 构建**

  ```bash
  cd /Users/zhuyecun/Documents/code/toDoList
  xcodegen generate
  xcodebuild build -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 运行全部测试**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: 提交**

  ```bash
  git add DesktopTodo/Views/AIPlannerSheet.swift \
          DesktopTodo.xcodeproj
  git commit -m "feat: AIPlannerSheet — streaming preview, delete steps, confirm to add"
  ```

---

## Task 6: TaskInputView wiring

**Files:**
- Modify: `DesktopTodo/Views/TaskInputView.swift`

**Interfaces:**
- Consumes: `AIPlannerSheet` from Task 5
- Produces: 完整的 AI 规划入口体验

---

- [ ] **Step 1: 修改 TaskInputView.swift**

  完整替换 `DesktopTodo/Views/TaskInputView.swift`：

  ```swift
  import SwiftUI

  struct TaskInputView: View {
      @Environment(TodoStore.self) private var store
      @State private var text = ""
      @FocusState private var isFocused: Bool
      @State private var showAIPlanner = false

      var body: some View {
          HStack(spacing: 8) {
              // AI planner button
              Button {
                  showAIPlanner = true
              } label: {
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

              // Standard add button
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

- [ ] **Step 2: 构建确认**

  ```bash
  xcodebuild build -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
  ```

  Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 运行全部测试**

  ```bash
  xcodebuild test -project DesktopTodo.xcodeproj -scheme DesktopTodo \
    -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
  ```

  Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: 手动验收检查**

  启动 app，依次验证：

  - [ ] `⌘,` 打开设置 → 可输入 API Key → 点「保存」→ 显示「已保存」
  - [ ] 关闭设置再打开 → Key 仍已填入（从 Keychain 加载）
  - [ ] 未填 API Key 时，点 ✨ → Sheet 显示「请先在设置中填写 API Key」+ 「打开设置」按钮
  - [ ] 填入有效 Key → 点 ✨ → 输入任务描述 → 点「开始规划」→ 任务标题和步骤逐行流式出现
  - [ ] 生成中可点 `[×]` 删除某步骤
  - [ ] 生成完成后点「添加到列表」→ Sheet 关闭，列表出现新任务（含子任务展开可见）
  - [ ] 点「重新规划」→ 清空并重新生成
  - [ ] 网络关闭时点「开始规划」→ 显示「网络连接失败」错误

- [ ] **Step 5: 提交**

  ```bash
  git add DesktopTodo/Views/TaskInputView.swift
  git commit -m "feat: TaskInputView — add ✨ AI planner button wired to AIPlannerSheet"
  ```

---

## Done

6 个任务完整交付：

| 组件 | 状态 |
|------|------|
| `KeychainService` — Keychain 存取 API Key | ✅ |
| `OpenAIService` — SSE 流式客户端 + 单元测试 | ✅ |
| `TodoStore.addItemWithSubTasks` — 原子创建父+子 | ✅ |
| `SettingsView + Settings scene` — ⌘, 打开设置 | ✅ |
| `AIPlannerSheet` — 流式预览 + 编辑 + 确认 | ✅ |
| `TaskInputView` — ✨ 按钮接入 | ✅ |

**v1.3 候选扩展**（不在本计划内）：多轮对话、历史记录、Anthropic/Ollama 模型切换。
