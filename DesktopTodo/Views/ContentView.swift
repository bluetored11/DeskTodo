import SwiftUI

struct ContentView: View {
    @AppStorage("isPinned") private var isPinned = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var window: NSWindow?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            TaskListView(isPinned: $isPinned)
        }
        .background(WindowAccessor { captured in
            window = captured
            // Apply persisted pin state as soon as we have a real window reference
            columnVisibility = isPinned ? .detailOnly : .automatic
            WindowManager.apply(isPinned: isPinned, window: captured)
        })
        .onChange(of: isPinned) { _, newValue in
            withAnimation {
                columnVisibility = newValue ? .detailOnly : .automatic
            }
            WindowManager.apply(isPinned: newValue, window: window)
        }
    }
}
