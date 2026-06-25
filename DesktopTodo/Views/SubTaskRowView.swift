import SwiftUI

struct SubTaskRowView: View {
    @Environment(TodoStore.self) private var store
    let sub: SubTask

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox
            Button {
                store.toggleSubTask(sub)
            } label: {
                Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(sub.isCompleted ? .green : .secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)

            // Title / inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitEdit() }
                    .onKeyPress(.escape) { isEditing = false; return .handled }
            } else {
                Text(sub.title)
                    .font(.body)
                    .strikethrough(sub.isCompleted, color: .secondary)
                    .foregroundStyle(sub.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Hover-reveal delete button
            if isHovered && !isEditing {
                Button {
                    store.deleteSubTask(sub)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 20)      // 20pt indent under parent row
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovered }
        }
    }

    private func startEditing() { editText = sub.title; isEditing = true }
    private func commitEdit() { store.updateSubTaskTitle(sub, title: editText); isEditing = false }
}
