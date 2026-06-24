import SwiftUI

struct SidebarView: View {
    var body: some View {
        List {
            Label("收件箱", systemImage: "tray.fill")
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        .navigationTitle("DesktopTodo")
    }
}
