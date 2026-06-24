import SwiftUI

struct TaskRowView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox with spring bounce animation
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    store.toggleComplete(item)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
                    .font(.title3)
                    .scaleEffect(item.isCompleted ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: item.isCompleted)
            }
            .buttonStyle(.plain)

            // Title or inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitEdit() }
                    .onKeyPress(.escape) {
                        isEditing = false
                        return .handled
                    }
            } else {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Hover-reveal delete button
            if isHovered && !isEditing {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.deleteItem(item)
                    }
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
        .contentShape(Rectangle())
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovered
            }
        }
    }

    private func startEditing() {
        editText = item.title
        isEditing = true
    }

    private func commitEdit() {
        store.updateTitle(item, title: editText)
        isEditing = false
    }
}
