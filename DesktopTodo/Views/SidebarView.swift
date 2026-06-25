import SwiftUI

struct SidebarView: View {
    @Environment(TodoStore.self) private var store
    @Binding var selectedListID: UUID?

    @State private var isAddingList = false
    @State private var newListName = ""
    @State private var renamingList: TodoList? = nil
    @State private var renameText = ""
    @State private var listToDelete: TodoList? = nil

    var body: some View {
        List(selection: $selectedListID) {
            inboxRow

            if !store.lists.isEmpty {
                Divider()
                ForEach(store.lists) { list in
                    listRow(list)
                }
                .onMove { source, destination in
                    store.moveLists(from: source, to: destination)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .navigationTitle("DesktopTodo")
        .safeAreaInset(edge: .bottom) { addListButton }
        .alert("删除清单", isPresented: .init(
            get: { listToDelete != nil },
            set: { if !$0 { listToDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let list = listToDelete { store.deleteList(list) }
                listToDelete = nil
            }
            Button("取消", role: .cancel) { listToDelete = nil }
        } message: {
            Text("该清单下的所有任务将一并删除，此操作无法撤销。")
        }
    }

    // MARK: - Inbox row

    private var inboxRow: some View {
        let count = store.items.filter { $0.list == nil && !$0.isCompleted }.count
        // List(selection:) treats nil as "no selection", so a nil-tagged row never
        // receives the click event. Use .onTapGesture to handle it explicitly.
        return Label("收件箱", systemImage: "tray.fill")
            .badge(count)
            .tag(Optional<UUID>.none)
            .contentShape(Rectangle())
            .onTapGesture { selectedListID = nil }
            .listRowBackground(
                selectedListID == nil
                    ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15))
                    : nil
            )
    }

    // MARK: - List row

    @ViewBuilder
    private func listRow(_ list: TodoList) -> some View {
        let count = store.items.filter { $0.list?.id == list.id && !$0.isCompleted }.count
        Group {
            if renamingList?.id == list.id {
                TextField("清单名称", text: $renameText)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onKeyPress(.escape) { renamingList = nil; return .handled }
            } else {
                Label(list.name, systemImage: "list.bullet")
                    .badge(count)
                    .onTapGesture(count: 2) { startRename(list) }
            }
        }
        .tag(Optional(list.id))
        .contextMenu {
            Button("重命名") { startRename(list) }
            Divider()
            Button("删除清单", role: .destructive) { listToDelete = list }
        }
    }

    // MARK: - Add list button

    private var addListButton: some View {
        VStack(spacing: 0) {
            Divider()
            if isAddingList {
                TextField("新清单名称", text: $newListName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onSubmit { commitNewList() }
                    .onKeyPress(.escape) {
                        isAddingList = false
                        newListName = ""
                        return .handled
                    }
            } else {
                Button {
                    isAddingList = true
                } label: {
                    Label("新建清单", systemImage: "plus")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Helpers

    private func startRename(_ list: TodoList) {
        renameText = list.name
        renamingList = list
    }

    private func commitRename() {
        if let list = renamingList { store.renameList(list, to: renameText) }
        renamingList = nil
    }

    private func commitNewList() {
        store.createList(name: newListName)
        newListName = ""
        isAddingList = false
        selectedListID = store.lists.last?.id
    }
}
