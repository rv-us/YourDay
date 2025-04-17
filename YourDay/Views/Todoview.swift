//
//  ContentView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData

struct Todoview: View {
    @Environment(\.modelContext) private var context
    @StateObject var viewModel = TodoViewModel()
    @Query(sort: [SortDescriptor(\TodoItem.dueDate, order: .reverse)]) private var items: [TodoItem]
    
    init() {
        
    }
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(items) { item in
                        TodoListItemView(item: item)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            context.delete(items[index])
                        }
                    }
                }
            }
            .navigationTitle("To Do List")
            .toolbar {
                Button {
                    viewModel.showingNewItemView = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $viewModel.showingNewItemView){
                NewItemview(newItemPresented: $viewModel.showingNewItemView)
            }
        }
    }
}

