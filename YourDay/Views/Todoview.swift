////
////  ContentView.swift
////  YourDay
////
////  Created by Rachit Verma on 4/8/25.
////
//
//import SwiftUI
//import SwiftData
//import UserNotifications
//
//struct Todoview: View {
//    @Environment(\.modelContext) private var context
//    @StateObject var viewModel = TodoViewModel()
//    @StateObject var loginViewModel = LoginViewModel()
//    
//    @AppStorage("hasCompletedTodoTutorial") private var hasCompletedTodoTutorial = false
//    @State private var showTodoTutorial = false
//    @State private var currentTodoTutorialStep: TodoTutorialStep = .welcome
//    @State private var highlightAddButton = false
//    @State private var highlightSummaryButton = false
//    @State private var previousInProgressCount = 0
//
////    @Query(sort: [SortDescriptor(\TodoItem.dueDate, order: .reverse)]) private var items: [TodoItem]
//    @Query(sort: [SortDescriptor(\TodoItem.position)]) private var items: [TodoItem]
//    
//    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
//    private var currentPlayerStats: PlayerStats? {
//        playerStatsList.first
//    }
//
//    @State private var showSignOutAlertInTodoView = false
//    @State private var signOutAlertMessageInTodoView = ""
//
//    init() {
//        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
//            if let error = error {
//                print("Notification permission error: \(error.localizedDescription)")
//            }
//        }
//    }
//
//    var body: some View {
//        NavigationView {
//            VStack {
//                List {
//                    Section(header: Text("In Progress")) {
//                        ForEach(items.filter { !$0.isDone }) { item in
//                            TodoListItemView(item: item)
//                        }
//                        .onMove(perform: moveItem)
//                        .onDelete { indexSet in
//                            for index in indexSet {
//                                let activeItems = items.filter { !$0.isDone }
//                                if index < activeItems.count { // Ensure index is valid
//                                    context.delete(activeItems[index])
//                                }
//                            }
//                        }
//                    }
//
//                    Section(header: Text("Completed")) {
//                        ForEach(items.filter { $0.isDone }) { item in
//                            TodoListItemView(item: item)
//                        }
//                        .onDelete { indexSet in
//                            for index in indexSet {
//                                let doneItems = items.filter { $0.isDone }
//                                 if index < doneItems.count { // Ensure index is valid
//                                    context.delete(doneItems[index])
//                                }
//                            }
//                        }
//                    }
//                }
//                .listStyle(InsetGroupedListStyle())
//            }
//            .navigationTitle("To Do List")
//            .onAppear {
//                if !hasCompletedTodoTutorial {
//                    showTodoTutorial = true
//                }
//                previousInProgressCount = items.filter { !$0.isDone }.count
//            }
//            .onChange(of: currentTodoTutorialStep) { newStep in
//                // Reset all highlights
//                highlightAddButton = false
//                highlightSummaryButton = false
//
//                // Set based on current step
//                switch newStep {
//                case .explainAdd:
//                    highlightAddButton = true
//                case .explainSummary:
//                    highlightSummaryButton = true
//                default:
//                    break
//                }
//            }
//            .onChange(of: viewModel.showingDailySummary) { opened in
//                if opened && currentTodoTutorialStep == .explainSummary {
//                    currentTodoTutorialStep = .finished
//                }
//            }
//            .onChange(of: items.filter { !$0.isDone }.count) { newCount in
//                if currentTodoTutorialStep == .explainAdd && newCount > previousInProgressCount {
//                    currentTodoTutorialStep = .explainSummary
//                }
//                previousInProgressCount = newCount
//            }
//            .toolbar {
//                ToolbarItem(placement: .navigationBarTrailing) {
//                    HStack {
//                        ZStack(alignment: .center) {
//                            if highlightAddButton {
//                                Circle()
//                                    .fill(Color.yellow.opacity(0.4))
//                                    .frame(width: 44, height: 44)
//                                    .offset(x: 4)
//                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightAddButton)
//                            }
//
//                            Button(action: {
//                                viewModel.showingNewItemView = true
//                            }) {
//                                Image(systemName: "plus")
//                                    .resizable()
//                                    .scaledToFit()
//                                    .frame(width: 22, height: 22)
//                                    .foregroundColor(.blue)
//                                    .frame(width: 44, height: 44) // ensures consistent touch + highlight area
//                                    .contentShape(Rectangle())   // ensures full area is tappable
//                            }
//                        }
//
//                        ZStack(alignment: .center) {
//                            if highlightSummaryButton {
//                                Circle()
//                                    .fill(Color.yellow.opacity(0.4))
//                                    .frame(width: 44, height: 44)
//                                    .offset(x: 4)
//                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightSummaryButton)
//                            }
//
//                            Button(action: {
//                                viewModel.showingDailySummary = true
//                            }) {
//                                Image(systemName: "star")
//                                    .resizable()
//                                    .scaledToFit()
//                                    .frame(width: 22, height: 22)
//                                    .foregroundColor(.blue)
//                                    .frame(width: 44, height: 44)
//                                    .contentShape(Rectangle())
//                            }
//                        }
//                    }
//                }
//            }
//            .overlay(
//                Group {
//                    if showTodoTutorial {
//                        TodoTutorialOverlay(
//                            currentStep: $currentTodoTutorialStep,
//                            isActive: $showTodoTutorial,
//                            hasCompletedTutorialPreviously: $hasCompletedTodoTutorial,
//                            highlightAdd: $highlightAddButton,
//                            highlightStar: $highlightSummaryButton,
//                            onDismiss: {
//                                highlightAddButton = false
//                                highlightSummaryButton = false
//                            }
//                        )
//                    }
//                }
//            )
//            .sheet(isPresented: $viewModel.showingDailySummary) {
//                LastDayView(isModal: true)
//            }
//            .sheet(isPresented: $viewModel.showingNewItemView) {
//                NewItemview(newItemPresented: $viewModel.showingNewItemView) // Assuming NewItemview is defined
//            }
//            .alert("Sign Out", isPresented: $showSignOutAlertInTodoView) { // Alert for sign-out issues from this view
//                Button("OK", role: .cancel) {}
//            } message: {
//                Text(signOutAlertMessageInTodoView)
//            }
//        }
//    }
//
//    func moveItem(from source: IndexSet, to destination: Int) {
//        var activeItems = items.filter { !$0.isDone }
//        activeItems.move(fromOffsets: source, toOffset: destination)
//
//        for (index, item) in activeItems.enumerated() {
//            item.position = index
//        }
//
//        try? context.save()
//    }
//    
//    private func requestSignOut() {
//        print("Todoview: Sign out requested from NotificationSettingsView.")
//        // Use Todoview's local loginViewModel and currentPlayerStats
//        loginViewModel.attemptSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessage in
//            if !didSignOut {
//                self.signOutAlertMessageInTodoView = errorMessage ?? "Could not sign out. Please check your connection and try again."
//                self.showSignOutAlertInTodoView = true
//                print("Todoview: Sign out attempt failed or was blocked: \(self.signOutAlertMessageInTodoView)")
//            } else {
//                // If sign-out is successful, LoginViewModel.isAuthenticated will change.
//                // If Todoview is part of ContentView, ContentView's .onChange(of: loginViewModel.isAuthenticated)
//                // should handle UI changes and local data clearing.
//                print("Todoview: Sign out process reported successful by its LoginViewModel.")
//            }
//        }
//    }
//}

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
    @StateObject var loginViewModel = LoginViewModel() // Should be @EnvironmentObject if passed from parent
    
    @AppStorage("hasCompletedTodoTutorial") private var hasCompletedTodoTutorial = false
    @State private var showTodoTutorial = false
    @State private var currentTodoTutorialStep: TodoTutorialStep = .welcome
    @State private var highlightAddButton = false
    @State private var highlightSummaryButton = false
    @State private var previousInProgressCount = 0

    @Query(sort: [SortDescriptor(\TodoItem.position)]) private var items: [TodoItem]
    
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
            VStack(spacing: 0) { // Added spacing: 0 for consistent look
                List {
                    Section(header:
                                HStack {
                                    Text("In Progress")
                                        .fontWeight(.semibold)
                                        .foregroundColor(plantDarkGreen)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(plantPastelGreen.opacity(0.5))
                                .cornerRadius(6)
                                .listRowInsets(EdgeInsets()) // Crucial for full-width header
                    ) {
                        ForEach(items.filter { !$0.isDone }) { item in
                            TodoListItemView(item: item) // Ensure TodoListItemView uses plant colors
                                .listRowBackground(plantBeige) // Apply background to row
                        }
                        .onMove(perform: moveItem)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let activeItems = items.filter { !$0.isDone }
                                if index < activeItems.count { // Ensure index is valid
                                    context.delete(activeItems[index])
                                }
                            }
                        }
                    }

                    Section(header:
                                HStack {
                                    Text("Completed")
                                        .fontWeight(.semibold)
                                        .foregroundColor(plantDarkGreen)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(plantPastelGreen.opacity(0.5))
                                .cornerRadius(6)
                                .listRowInsets(EdgeInsets()) // Crucial for full-width header
                    ) {
                        ForEach(items.filter { $0.isDone }) { item in
                            TodoListItemView(item: item) // Ensure TodoListItemView uses plant colors
                                .listRowBackground(plantBeige) // Apply background to row
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
                .listStyle(PlainListStyle()) // Changed to plain for consistency
                .background(plantBeige) // Applied background to the list itself
            }
            .background(plantBeige.edgesIgnoringSafeArea(.all)) // Apply background to the entire view
            .navigationTitle("") // Hide default title
            .navigationBarTitleDisplayMode(.inline) // Ensure inline display for custom title
            .toolbarBackground(plantLightMintGreen, for: .navigationBar) // Custom toolbar background
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { // Custom title placement
                    Text("Your To-Do List") // More friendly title
                        .fontWeight(.bold)
                        .foregroundColor(plantDarkGreen)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: -5) {
                        ZStack(alignment: .center) {
                            if highlightAddButton {
                                Circle()
                                    .fill(Color.yellow.opacity(0.4))
                                    .frame(width: 44, height: 44)
                                    .offset(x: 4)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightAddButton)
                            }

                            Button(action: {
                                viewModel.showingNewItemView = true
                            }) {
                                Image(systemName: "plus")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                                    .foregroundColor(plantDarkGreen) // Applied plantDarkGreen
                                    .frame(width: 44, height: 44) // ensures consistent touch + highlight area
                                    .contentShape(Rectangle())    // ensures full area is tappable
                            }
                        }

                        ZStack(alignment: .center) {
                            if highlightSummaryButton {
                                Circle()
                                    .fill(Color.yellow.opacity(0.4))
                                    .frame(width: 44, height: 44)
                                    .offset(x: 4)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightSummaryButton)
                            }

                            Button(action: {
                                viewModel.showingDailySummary = true
                            }) {
                                Image(systemName: "star")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                                    .foregroundColor(plantDarkGreen) // Applied plantDarkGreen
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            .onAppear {
                if !hasCompletedTodoTutorial {
                    showTodoTutorial = true
                }
                previousInProgressCount = items.filter { !$0.isDone }.count
            }
            .onChange(of: currentTodoTutorialStep) { newStep in
                // Reset all highlights
                highlightAddButton = false
                highlightSummaryButton = false

                // Set based on current step
                switch newStep {
                case .explainAdd:
                    highlightAddButton = true
                case .explainSummary:
                    highlightSummaryButton = true
                default:
                    break
                }
            }
            .onChange(of: viewModel.showingDailySummary) { opened in
                if opened && currentTodoTutorialStep == .explainSummary {
                    currentTodoTutorialStep = .finished
                }
            }
            .onChange(of: items.filter { !$0.isDone }.count) { newCount in
                if currentTodoTutorialStep == .explainAdd && newCount > previousInProgressCount {
                    currentTodoTutorialStep = .explainSummary
                }
                previousInProgressCount = newCount
            }
            .overlay(
                Group {
                    if showTodoTutorial {
                        TodoTutorialOverlay(
                            currentStep: $currentTodoTutorialStep,
                            isActive: $showTodoTutorial,
                            hasCompletedTutorialPreviously: $hasCompletedTodoTutorial,
                            highlightAdd: $highlightAddButton,
                            highlightStar: $highlightSummaryButton,
                            onDismiss: {
                                highlightAddButton = false
                                highlightSummaryButton = false
                            }
                        )
                    }
                }
            )
            .sheet(isPresented: $viewModel.showingDailySummary) {
                LastDayView(isModal: true)
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
        .navigationViewStyle(.stack)
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        var activeItems = items.filter { !$0.isDone }
        activeItems.move(fromOffsets: source, toOffset: destination)

        for (index, item) in activeItems.enumerated() {
            item.position = index
        }

        try? context.save()
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
