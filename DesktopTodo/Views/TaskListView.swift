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
        // Pin 模式下隐藏标题，释放工具栏空间给 Pin 按钮
        .navigationTitle(isPinned ? "" : "收件箱")
        .toolbar {
            // 待完成计数（仅普通模式显示，Pin 模式空间不足）
            if !isPinned {
                ToolbarItem(placement: .automatic) {
                    let pending = store.items.filter { !$0.isCompleted }.count
                    Text(pending == 0 && !store.items.isEmpty ? "全部完成 🎉" : "\(pending) 项待完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Pin 按钮：始终在工具栏
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPinned.toggle()
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
