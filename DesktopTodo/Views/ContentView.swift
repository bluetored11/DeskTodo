import SwiftUI

struct ContentView: View {
    @AppStorage("isPinned") private var isPinned = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            TaskListView(isPinned: $isPinned)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            // 重启后恢复持久化的 Pin 状态
            columnVisibility = isPinned ? .detailOnly : .automatic
            WindowManager.apply(isPinned: isPinned)
        }
        .onChange(of: isPinned) { _, newValue in
            // Pin 按钮切换时同步侧边栏可见性
            withAnimation {
                columnVisibility = newValue ? .detailOnly : .automatic
            }
        }
    }
}
