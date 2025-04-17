//
//  ContentView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData

struct Todoview: View {
    @StateObject var viewModel = TodoViewModel()
    @Query(sort: [SortDescriptor(\TodoItem.dueDate, order: .reverse)]) private var items: [TodoItem]
    
    init() {
        
    }
    var body: some View {
        NavigationView {
            VStack {
                List(items) { item in
                    TodoListItemView(item: item)
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

