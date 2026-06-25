import SwiftUI

struct TaskRowView: View {
    @Environment(TodoStore.self) private var store
    let item: TodoItem

    @State private var isHovered = false
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showDueDatePopover = false
    @State private var isExpanded = false
    @State private var addingSubTask = false
    @State private var newSubTaskTitle = ""
    @FocusState private var subTaskInputFocused: Bool

    private var sortedSubtasks: [SubTask] {
        (item.subtasks ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Main row ──────────────────────────────────────────────────
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
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.body)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .foregroundStyle(item.isCompleted ? .secondary : .primary)

                        // Progress + expand/collapse
                        // Show chevron on hover (even with 0 sub-tasks) so the first sub-task is reachable.
                        // Show progress text only when sub-tasks actually exist.
                        if isHovered || !(item.subtasks?.isEmpty ?? true) {
                            let subs = item.subtasks ?? []
                            if !subs.isEmpty {
                                let doneCount = subs.filter(\.isCompleted).count
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                                Text("\(doneCount)/\(subs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Button {
                                isExpanded.toggle()
                            } label: {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                    .onTapGesture(count: 2) { startEditing() }
                }

                // Hover-reveal: date button + delete
                if isHovered && !isEditing {
                    Button {
                        showDueDatePopover = true
                    } label: {
                        Group {
                            if let due = item.dueDate {
                                Text(due.formatted(date: .abbreviated, time: .shortened))
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
            .popover(isPresented: $showDueDatePopover, arrowEdge: .bottom) {
                DueDatePopoverView(item: item)
                    .environment(store)
                    .padding()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onHover { hovered in
                guard !showDueDatePopover else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovered }
            }
            .onChange(of: showDueDatePopover) { _, showing in
                if !showing { isHovered = false }
            }

            // ── Expanded sub-task section ─────────────────────────────────
            if isExpanded {
                ForEach(sortedSubtasks) { sub in
                    SubTaskRowView(sub: sub)
                }

                // Add sub-task: input field OR "+" button
                if addingSubTask {
                    HStack(spacing: 8) {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                            .font(.body)
                        TextField("新子任务", text: $newSubTaskTitle)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($subTaskInputFocused)
                            .onAppear { subTaskInputFocused = true }   // grab focus as soon as input row appears
                            .onSubmit {
                                let trimmed = newSubTaskTitle.trimmingCharacters(in: .whitespaces)
                                if trimmed.isEmpty {
                                    addingSubTask = false
                                } else {
                                    store.addSubTask(to: item, title: trimmed)
                                    newSubTaskTitle = ""
                                    // Keep addingSubTask = true so user can keep adding
                                }
                            }
                            .onKeyPress(.escape) {
                                addingSubTask = false
                                newSubTaskTitle = ""
                                return .handled
                            }
                    }
                    .padding(.vertical, 2)
                    .padding(.leading, 20)
                } else {
                    Button {
                        addingSubTask = true
                    } label: {
                        Label("添加子任务", systemImage: "plus")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 20)
                    .padding(.vertical, 2)
                }
            }
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
