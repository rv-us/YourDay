//
//  TodoListItemView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//

import SwiftUI

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
                        .foregroundColor(item.isDone ? .green : .gray)
                        .frame(width: 24, height: 24)
                        .padding(6)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .lineLimit(1)
                        .strikethrough(item.isDone)
                        .foregroundColor(item.isDone ? .gray : .primary)

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundColor(item.isDone ? .gray.opacity(0.7) : .gray)
                            .strikethrough(item.isDone)
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
                        .strikethrough(subtask.isDone)
                        .foregroundColor(subtask.isDone ? .gray : .primary)
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
