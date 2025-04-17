//
//  TodoListItemView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/17/25.
//

import SwiftUI

struct TodoListItemView: View {
    @Bindable var item: TodoItem
    
    var body: some View {
        HStack {
            Button {
                item.isDone.toggle()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isDone ? .green : .gray)
            }
            VStack(alignment: .leading) {
                Text(item.title)
                    .bold()
            }
        }
    }
}

#Preview {
    TodoListItemView(item: TodoItem(
        title: "Sample Task",
        detail: "Sample Detail",
        dueDate: Date(),
        isDone: false
    ))
}

