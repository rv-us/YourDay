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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                List {
                    Section(header: Text("In Progress")) {
                        ForEach(items.filter { !$0.isDone }) { item in
                            TodoListItemView(item: item)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let activeItems = items.filter { !$0.isDone }
                                context.delete(activeItems[index])
                            }
                        }
                    }

                    Section(header: Text("Completed")) {
                        ForEach(items.filter { $0.isDone }) { item in
                            TodoListItemView(item: item)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let doneItems = items.filter { $0.isDone }
                                context.delete(doneItems[index])
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())

            }
            .navigationTitle("To Do List")
//            .toolbar {
//                Button {
//                    viewModel.showingNewItemView = true
//                } label: {
//                    Image(systemName: "plus")
//                }
//            }
            .toolbar {
                HStack {
                    Button {
                        viewModel.showingNewItemView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSettings) {
                NotificationSettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showingNewItemView) {
                NewItemview(newItemPresented: $viewModel.showingNewItemView)
            }
        }
        
    }
}
