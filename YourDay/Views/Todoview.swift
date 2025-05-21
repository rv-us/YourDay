//
//  ContentView.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData
import UserNotifications

struct Todoview: View {
    @Environment(\.modelContext) private var context
    @StateObject var viewModel = TodoViewModel()
    @StateObject var loginViewModel = LoginViewModel()

    @Query(sort: [SortDescriptor(\TodoItem.dueDate, order: .reverse)]) private var items: [TodoItem]
    
    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? {
        playerStatsList.first
    }

    @State private var showSignOutAlertInTodoView = false
    @State private var signOutAlertMessageInTodoView = ""

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
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
                                if index < activeItems.count { // Ensure index is valid
                                    context.delete(activeItems[index])
                                }
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
                                 if index < doneItems.count { // Ensure index is valid
                                    context.delete(doneItems[index])
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
            .navigationTitle("To Do List")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { // Ensure buttons are on the trailing side
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
            }
            .sheet(isPresented: $viewModel.showingSettings) {
                NotificationSettingsView(
                    todoViewModel: viewModel,
                    loginViewModel: loginViewModel, // Pass Todoview's instance
                    onSignOutRequested: {
                        // This closure is called when "Sign Out" is tapped in NotificationSettingsView
                        requestSignOut()
                    }
                )
            }
            .sheet(isPresented: $viewModel.showingNewItemView) {
                NewItemview(newItemPresented: $viewModel.showingNewItemView) // Assuming NewItemview is defined
            }
            .alert("Sign Out", isPresented: $showSignOutAlertInTodoView) { // Alert for sign-out issues from this view
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutAlertMessageInTodoView)
            }
        }
    }

    private func requestSignOut() {
        print("Todoview: Sign out requested from NotificationSettingsView.")
        // Use Todoview's local loginViewModel and currentPlayerStats
        loginViewModel.attemptSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessage in
            if !didSignOut {
                self.signOutAlertMessageInTodoView = errorMessage ?? "Could not sign out. Please check your connection and try again."
                self.showSignOutAlertInTodoView = true
                print("Todoview: Sign out attempt failed or was blocked: \(self.signOutAlertMessageInTodoView)")
            } else {
                // If sign-out is successful, LoginViewModel.isAuthenticated will change.
                // If Todoview is part of ContentView, ContentView's .onChange(of: loginViewModel.isAuthenticated)
                // should handle UI changes and local data clearing.
                print("Todoview: Sign out process reported successful by its LoginViewModel.")
            }
        }
    }
}
