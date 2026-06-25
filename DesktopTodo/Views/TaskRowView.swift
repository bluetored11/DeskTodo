import SwiftUI

struct TaskRowView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showDueDatePopover = false

    var body: some View {
        HStack(spacing: 10) {
            // Priority circle (left of checkbox)
            Button {
                store.setPriority(item, priority: item.priority.next)
            } label: {
                Circle()
                    .fill(item.priority.color)
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .help("点击切换优先级")
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }

            // Checkbox
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

            // Title / inline editor
            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .onSubmit { commitEdit() }
                    .onKeyPress(.escape) { isEditing = false; return .handled }
            } else {
                Text(item.title)
                    .font(.body)
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Hover-reveal: date button + delete
            if isHovered && !isEditing {
                // Date entry point — only triggers the popover;
                // the popover itself is anchored to the outer HStack (below)
                // so it survives the hover-exit that fires on click.
                Button {
                    showDueDatePopover = true
                } label: {
                    Group {
                        if let due = item.dueDate {
                            Text(due.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(due < Date() ? .red : .secondary)
                        } else {
                            Image(systemName: "calendar")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))

                // Delete
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { store.deleteItem(item) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // Popover anchored to the row HStack so it persists even when
        // isHovered flips to false after the user clicks the date button.
        .popover(isPresented: $showDueDatePopover, arrowEdge: .bottom) {
            DueDatePopoverView(item: item)
                .environment(store)
                .padding()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovered in
            // Keep the row "hovered" while the popover is open so the date
            // button stays visible while the user interacts with the popover.
            guard !showDueDatePopover else { return }
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovered }
        }
        .onChange(of: showDueDatePopover) { _, showing in
            // When the popover closes, clear hover so hover-reveal buttons hide.
            if !showing { isHovered = false }
        }
    }

    private func startEditing() { editText = item.title; isEditing = true }
    private func commitEdit() { store.updateTitle(item, title: editText); isEditing = false }
}

// MARK: - Priority color

extension Priority {
    var color: Color {
        switch self {
        case .none:   return .gray.opacity(0.35)
        case .low:    return .blue
        case .medium: return .yellow
        case .high:   return .red
        }
    }
}
