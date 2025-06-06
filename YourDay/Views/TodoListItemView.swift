//
//  TodoListItemView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//

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
                        // Apply darker green for completed checkbox icon, keeping dusty blue for uncompleted
                        .foregroundColor(item.isDone ? plantDarkGreen : plantDustyBlue)
                        .frame(width: 24, height: 24)
                        .padding(6)
                        // Apply themed background for checkbox circle
                        .background(item.isDone ? plantLightMintGreen.opacity(0.6) : plantPastelGreen.opacity(0.3))
                        .clipShape(Circle())
                        .overlay( // Add a subtle border to checkbox
                            // Use darker green for completed border, dusty blue for uncompleted
                            Circle()
                                .stroke(item.isDone ? plantDarkGreen : plantDustyBlue, lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body) // Keep original font size
                        .lineLimit(1)
                        .strikethrough(item.isDone, color: plantDustyBlue) // Themed strikethrough color
                        // Apply original themed colors for main title text
                        .foregroundColor(item.isDone ? plantDustyBlue : plantDarkGreen)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption) // Keep original font size
                            .lineLimit(2)
                            .strikethrough(item.isDone, color: plantDustyBlue.opacity(0.7)) // Themed strikethrough color
                            // Apply original themed colors for detail text
                            .foregroundColor(item.isDone ? plantDustyBlue.opacity(0.7) : plantMediumGreen)
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
                        // Apply original themed strikethrough and text colors for subtasks
                            .strikethrough(subtask.isDone, color: plantDustyBlue.opacity(0.7))
                            .foregroundColor(subtask.isDone ? plantDustyBlue.opacity(0.7) : plantMediumGreen)
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
