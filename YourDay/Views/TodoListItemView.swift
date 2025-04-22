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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button(action: {
                    item.isDone.toggle()
                    print("Main item '\(item.title)' toggled to \(item.isDone)")
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

                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                    .onTapGesture {
                        showingEditView = true
                    }

                Spacer()
            }
            .padding(.horizontal, 4)

            if !$item.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($item.subtasks) { $subtask in
                        SubtaskCheckboxView(
                            title: subtask.title,
                            isDone: $subtask.isDone
                        )
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

    @Environment(\.modelContext) private var _modelContext
}

