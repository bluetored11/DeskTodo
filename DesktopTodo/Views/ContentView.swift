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
        .toolbar(removing: .sidebarToggle)
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
            // Defer AppKit resize to the next run-loop cycle so it doesn't
            // conflict with SwiftUI's in-progress layout pass, which causes
            // an infinite constraint-update loop and freezes the UI.
            DispatchQueue.main.async {
                WindowManager.apply(isPinned: newValue, window: window)
            }
        }
    }
}
