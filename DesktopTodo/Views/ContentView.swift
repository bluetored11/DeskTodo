import SwiftUI

struct ContentView: View {
    @Environment(TodoStore.self) private var store
    @AppStorage("isPinned") private var isPinned = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var window: NSWindow?

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedListID: $store.selectedListID)
        } detail: {
            TaskListView(isPinned: $isPinned)
        }
        .toolbar(removing: .sidebarToggle)
        .background(WindowAccessor { captured in
            window = captured
            columnVisibility = isPinned ? .detailOnly : .automatic
            WindowManager.apply(isPinned: isPinned, window: captured)
        })
        .onChange(of: isPinned) { _, newValue in
            withAnimation { columnVisibility = newValue ? .detailOnly : .automatic }
            DispatchQueue.main.async {
                WindowManager.apply(isPinned: newValue, window: window)
            }
        }
    }
}
