import SwiftUI

struct TaskInputView: View {
    @Environment(TodoStore.self) private var store
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @State private var showAIPlanner = false

    var body: some View {
        HStack(spacing: 8) {
            // AI planner button
            Button {
                showAIPlanner = true
            } label: {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.purple)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("AI 任务规划")
            .sheet(isPresented: $showAIPlanner) {
                AIPlannerSheet()
                    .environment(store)
            }

            // Standard add button
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)

            TextField("添加任务...", text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .onSubmit {
                    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    store.addItem(title: text)
                    text = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .onReceive(NotificationCenter.default.publisher(for: .focusTaskInput)) { _ in
            isFocused = true
        }
    }
}
