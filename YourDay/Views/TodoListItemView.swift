import SwiftUI
import SwiftData

struct TodoListItemView: View {
    @Bindable var item: TodoItem
    @State private var showingEditView = false
    @Environment(\.modelContext) private var _modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: {
                    withAnimation {
                        item.isDone.toggle()
                        item.completedAt = item.isDone ? Date() : nil
                    }
                    print("Main item '\(item.title)' toggled to \(item.isDone), completedAt: \(String(describing: item.completedAt))")
                }) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                        .frame(width: 24, height: 24)
                        .padding(6)
                        .background(item.isDone ? dynamicPrimaryColor.opacity(0.2) : dynamicSecondaryBackgroundColor)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(item.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor, lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(item.isDone, color: dynamicSecondaryTextColor)
                        .foregroundColor(item.isDone ? dynamicSecondaryTextColor : dynamicTextColor)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .lineLimit(2)
                            .strikethrough(item.isDone, color: dynamicSecondaryTextColor.opacity(0.7))
                            .foregroundColor(item.isDone ? dynamicSecondaryTextColor : dynamicSecondaryTextColor)
                    }
                }
                .onTapGesture {
                    showingEditView = true
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            if !$item.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($item.subtasks) { $subtask in
                        SubtaskCheckboxView(subtask: $subtask)
                            .strikethrough(subtask.isDone, color: dynamicSecondaryTextColor.opacity(0.7))
                            .foregroundColor(subtask.isDone ? dynamicSecondaryTextColor.opacity(0.7) : dynamicTextColor)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditView) {
            NewItemview(newItemPresented: $showingEditView, editingItem: item)
                .environment(\.modelContext, _modelContext)
        }
    }
}
