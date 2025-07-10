import SwiftUI
import SwiftData
import UserNotifications

struct Todoview: View {
    @Environment(\.modelContext) private var context
    @StateObject var viewModel = TodoViewModel()
    @StateObject var loginViewModel = LoginViewModel()
    
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

    enum TaskListFilter {
        case today
        case master
    }

    @State private var selectedFilter: TaskListFilter = .today

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Filter", selection: $selectedFilter) {
                    Text("Today").tag(TaskListFilter.today)
                    Text("Master List").tag(TaskListFilter.master)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                List {
                    Section(header:
                        HStack {
                            Text("In Progress")
                                .fontWeight(.semibold)
                                .foregroundColor(dynamicPrimaryColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(dynamicSecondaryBackgroundColor.opacity(0.8))
                        .cornerRadius(6)
                        .listRowInsets(EdgeInsets())
                    ) {
                        ForEach(filteredItems.filter { !$0.isDone }) { item in
                            TodoListItemView(item: item)
                                .listRowBackground(dynamicSecondaryBackgroundColor)
                        }
                        .onMove(perform: moveItem)
                        .onDelete { indexSet in
                            for index in indexSet {
                                let activeItems = filteredItems.filter { !$0.isDone }
                                if index < activeItems.count {
                                    context.delete(activeItems[index])
                                }
                            }
                        }
                    }

                    Section(header:
                        HStack {
                            Text("Completed")
                                .fontWeight(.semibold)
                                .foregroundColor(dynamicPrimaryColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.subheadline)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(dynamicSecondaryBackgroundColor.opacity(0.8))
                        .cornerRadius(6)
                        .listRowInsets(EdgeInsets())
                    ) {
                        ForEach(filteredItems.filter { $0.isDone }) { item in
                            TodoListItemView(item: item)
                                .listRowBackground(dynamicSecondaryBackgroundColor)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let doneItems = filteredItems.filter { $0.isDone }
                                if index < doneItems.count {
                                    context.delete(doneItems[index])
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .background(dynamicBackgroundColor)
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Your To-Do List")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
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
                                    .foregroundColor(dynamicPrimaryColor)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
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
                                    .foregroundColor(dynamicPrimaryColor)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                        }
                    }
                }
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
                NewItemview(newItemPresented: $viewModel.showingNewItemView)
            }
            .alert("Sign Out", isPresented: $showSignOutAlertInTodoView) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutAlertMessageInTodoView)
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if !hasCompletedTodoTutorial {
                showTodoTutorial = true
            }
        }
    }

    private var filteredItems: [TodoItem] {
        switch selectedFilter {
        case .today:
            return items.filter { $0.origin == .today }
        case .master:
            return items.filter { $0.origin == .master }
        }
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        var activeItems = filteredItems.filter { !$0.isDone }
        activeItems.move(fromOffsets: source, toOffset: destination)

        for (index, item) in activeItems.enumerated() {
            item.position = index
        }

        try? context.save()
    }
    
    private func requestSignOut() {
        print("Todoview: Sign out requested from NotificationSettingsView.")
        loginViewModel.attemptSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessage in
            if !didSignOut {
                self.signOutAlertMessageInTodoView = errorMessage ?? "Could not sign out. Please check your connection and try again."
                self.showSignOutAlertInTodoView = true
                print("Todoview: Sign out attempt failed or was blocked: \(self.signOutAlertMessageInTodoView)")
            } else {
                print("Todoview: Sign out process reported successful by its LoginViewModel.")
            }
        }
    }
}
