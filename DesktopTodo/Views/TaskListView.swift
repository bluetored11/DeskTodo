import SwiftUI

struct TaskListView: View {
    @Environment(TodoStore.self) private var store
    @Binding var isPinned: Bool
    @State private var selectedItem: TodoItem?

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            // Pin 状态下：工具栏空间不足，改为内容区悬浮按钮，保证永远可见
            if isPinned {
                Button {
                    isPinned.toggle()
                } label: {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.blue)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("取消固定窗口")
                .padding(.top, 8)
                .padding(.trailing, 8)
            }
        }
        .navigationTitle("收件箱")
        .toolbar {
            // 待完成计数（仅普通模式显示）
            ToolbarItem(placement: .automatic) {
                let pending = store.items.filter { !$0.isCompleted }.count
                Text(pending == 0 && !store.items.isEmpty ? "全部完成 🎉" : "\(pending) 项待完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Pin 按钮（仅普通模式，紧凑模式用悬浮按钮代替）
            if !isPinned {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPinned.toggle()
                    } label: {
                        Image(systemName: "pin")
                            .foregroundStyle(.secondary)
                    }
                    .help("固定在最上层")
                }
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
