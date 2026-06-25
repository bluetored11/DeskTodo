import SwiftUI

struct DueDatePopoverView: View {
    @Environment(TodoStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: TodoItem

    @State private var selectedDate: Date
    @State private var selectedOffset: ReminderOffset?

    init(item: TodoItem) {
        self.item = item
        _selectedDate = State(initialValue: item.dueDate ?? Calendar.current.startOfDay(for: Date()))
        _selectedOffset = State(initialValue: item.reminderOffset)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("截止日期", systemImage: "calendar")
                .font(.headline)

            DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
                .frame(maxWidth: 300)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("提醒", systemImage: "bell")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("提醒时机", selection: $selectedOffset) {
                    Text("不提醒").tag(Optional<ReminderOffset>.none)
                    Text(ReminderOffset.atTime.displayName).tag(Optional<ReminderOffset>(.atTime))
                    Text(ReminderOffset.oneHour.displayName).tag(Optional<ReminderOffset>(.oneHour))
                    Text(ReminderOffset.oneDay.displayName).tag(Optional<ReminderOffset>(.oneDay))
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            HStack {
                Button("清除日期") {
                    store.clearDueDate(item)
                    dismiss()
                }
                .foregroundStyle(.red)
                .buttonStyle(.plain)

                Spacer()

                Button("完成") {
                    store.setDueDate(item, date: selectedDate, reminderOffset: selectedOffset)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(minWidth: 300)
    }
}
