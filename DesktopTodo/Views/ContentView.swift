import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            TaskListView()
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
