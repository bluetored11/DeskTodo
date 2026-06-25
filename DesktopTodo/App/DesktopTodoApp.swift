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
    }
}

extension Notification.Name {
    static let focusTaskInput = Notification.Name("focusTaskInput")
}
