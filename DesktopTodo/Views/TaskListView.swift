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
                    store.move(from: source, to: destination)
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
