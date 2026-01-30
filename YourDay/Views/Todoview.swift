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
    @State private var highlightFilterButton = false
    @State private var previousInProgressCount = 0

    @Query(sort: [SortDescriptor(\TodoItem.position)]) private var items: [TodoItem]
    
    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? {
        playerStatsList.first
    }

    @State private var showSignOutAlertInTodoView = false
    @State private var signOutAlertMessageInTodoView = ""
    @State private var navigateToCalendar = false

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
                filterPickerView
                taskListView
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                toolbarContent
            }
            .overlay(tutorialOverlay)
            .sheet(isPresented: $viewModel.showingDailySummary) {
                LastDayView(isModal: true)
            }
            .sheet(isPresented: $viewModel.showingNewItemView) {
                NewItemview(newItemPresented: $viewModel.showingNewItemView, selectedOrigin: selectedFilter == .today ? .today : .master)
            }
            .background(
                NavigationLink(
                    destination: GoogleCalendarView(embedded: true)
                        .environment(\.modelContext, context),
                    isActive: $navigateToCalendar
                ) {
                    EmptyView()
                }
                .hidden()
            )
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
        .onChange(of: currentTodoTutorialStep) { _, newStep in
            // Reset all highlights
            highlightAddButton = false
            highlightSummaryButton = false
            highlightFilterButton = false
            
            // Set appropriate highlight based on current step
            switch newStep {
            case .explainFilter:
                highlightFilterButton = true
            case .explainAdd:
                highlightAddButton = true
            case .explainSummary:
                highlightSummaryButton = true
            default:
                break
            }
        }
    }
    
    private var filterPickerView: some View {
        ZStack(alignment: .center) {
            if highlightFilterButton {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.yellow.opacity(0.4))
                    .frame(height: 40)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightFilterButton)
            }
            
            Picker("Filter", selection: $selectedFilter) {
                Text("Today").tag(TaskListFilter.today)
                Text("Master List").tag(TaskListFilter.master)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            .tint(dynamicPrimaryColor)
        }
    }
    
    private var taskListView: some View {
        List {
            inProgressSection
            completedSection
        }
        .listStyle(PlainListStyle())
        .background(dynamicBackgroundColor)
    }
    
    private var inProgressSection: some View {
        Section(header: sectionHeader(title: "In Progress")) {
            ForEach(filteredItems.filter { !$0.isDone }) { item in
                TodoListItemView(item: item, todoViewModel: viewModel)
                    .listRowBackground(dynamicSecondaryBackgroundColor)
            }
            .onMove(perform: moveItem)
            .onDelete { indexSet in
                handleInProgressDelete(indexSet: indexSet)
            }
        }
    }
    
    private var completedSection: some View {
        Section(header: sectionHeader(title: "Completed")) {
            ForEach(filteredItems.filter { $0.isDone }) { item in
                TodoListItemView(item: item, todoViewModel: viewModel)
                    .listRowBackground(dynamicSecondaryBackgroundColor)
            }
            .onDelete { indexSet in
                handleCompletedDelete(indexSet: indexSet)
            }
        }
    }
    
    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
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
    }
    
    private var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItem(placement: .principal) {
                Text("Your To-Do List")
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarButtons
            }
        }
    }
    
    private var toolbarButtons: some View {
        HStack(spacing: -5) {
            addButton
            summaryButton
            calendarButton
        }
    }
    
    private var addButton: some View {
        ZStack(alignment: .center) {
            if highlightAddButton {
                Circle()
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .offset(x: 4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightAddButton)
            }
            
            Button(action: {
                // If we're in tutorial and user interacts with add button, progress to next step
                if showTodoTutorial && currentTodoTutorialStep == .explainAdd {
                    let nextRawValue = currentTodoTutorialStep.rawValue + 1
                    if let nextStep = TodoTutorialStep(rawValue: nextRawValue) {
                        currentTodoTutorialStep = nextStep
                    }
                }
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
    }
    
    private var summaryButton: some View {
        ZStack(alignment: .center) {
            if highlightSummaryButton {
                Circle()
                    .fill(Color.yellow.opacity(0.4))
                    .frame(width: 44, height: 44)
                    .offset(x: 4)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightSummaryButton)
            }
            
            Button(action: {
                // If we're in tutorial and user interacts with star button, progress to next step
                if showTodoTutorial && currentTodoTutorialStep == .explainSummary {
                    let nextRawValue = currentTodoTutorialStep.rawValue + 1
                    if let nextStep = TodoTutorialStep(rawValue: nextRawValue) {
                        currentTodoTutorialStep = nextStep
                    }
                }
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
    
    private var calendarButton: some View {
        Button(action: {
            navigateToCalendar = true
        }) {
            Image(systemName: "calendar")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundColor(dynamicPrimaryColor)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
    }
    
    private var tutorialOverlay: some View {
        Group {
            if showTodoTutorial {
                TodoTutorialOverlay(
                    currentStep: $currentTodoTutorialStep,
                    isActive: $showTodoTutorial,
                    hasCompletedTutorialPreviously: $hasCompletedTodoTutorial,
                    highlightAdd: $highlightAddButton,
                    highlightStar: $highlightSummaryButton,
                    highlightFilter: $highlightFilterButton,
                    onDismiss: {
                        highlightAddButton = false
                        highlightSummaryButton = false
                        highlightFilterButton = false
                    }
                )
            }
        }
    }
    
    private func handleInProgressDelete(indexSet: IndexSet) {
        for index in indexSet {
            let activeItems = filteredItems.filter { !$0.isDone }
            if index < activeItems.count {
                let item = activeItems[index]
                if let sharedId = item.sharedTaskId {
                    // Mark as discarded instead of deleting, so other person sees it was cancelled
                    FirebaseManager.shared.markSharedTaskDiscarded(sharedTaskId: sharedId) { error in
                        if let error = error {
                            print("Failed to mark shared task as discarded: \(error)")
                        }
                    }
                }
                context.delete(item)
            }
        }
    }
    
    private func handleCompletedDelete(indexSet: IndexSet) {
        for index in indexSet {
            let doneItems = filteredItems.filter { $0.isDone }
            if index < doneItems.count {
                let item = doneItems[index]
                if let sharedId = item.sharedTaskId {
                    // Keep completed status synced before deletion
                    FirebaseManager.shared.deleteSharedTask(sharedTaskId: sharedId) { error in
                        if let error = error {
                            print("Failed to delete shared task: \(error)")
                        }
                    }
                }
                context.delete(item)
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
