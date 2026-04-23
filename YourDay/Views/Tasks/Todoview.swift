import SwiftUI
import SwiftData
import FirebaseAuth

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
    @State private var showGoogleCalendarView = false
    @State private var pendingProofFromList: TaskProofCaptureContext?

    enum TaskListFilter {
        case today
        case master
    }

    @State private var selectedFilter: TaskListFilter = .today

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showGoogleCalendarView {
                    GoogleCalendarView(embedded: true)
                        .environment(\.modelContext, context)
                } else {
                    ZStack(alignment: .center) {
                        if highlightFilterButton {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(plantPeach.opacity(0.6))
                                .frame(height: 40)
                                .padding(.horizontal)
                                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightFilterButton)
                        }

                        HStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedFilter = .today
                                }
                            } label: {
                                Text("Today")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundColor(selectedFilter == .today ? .white : .black.opacity(0.65))
                                    .background(selectedFilter == .today ? dynamicPrimaryColor : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedFilter = .master
                                }
                            } label: {
                                Text("Master List")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .foregroundColor(selectedFilter == .master ? .white : .black.opacity(0.65))
                                    .background(selectedFilter == .master ? dynamicPrimaryColor : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(4)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                        .padding()
                    }

                    List {
                        Section(header:
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(plantLightMintGreen)
                                    .frame(width: 10, height: 10)
                                Text("In Progress")
                                    .fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.subheadline)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [plantLightMintGreen.opacity(0.3), dynamicSecondaryBackgroundColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(6)
                            .listRowInsets(EdgeInsets())
                        ) {
                            ForEach(filteredItems.filter { !$0.isDone }) { item in
                                TodoListItemView(item: item, todoViewModel: viewModel, onRequestProofCapture: { pendingProofFromList = $0 })
                                    .listRowBackground(dynamicSecondaryBackgroundColor)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button(selectedFilter == .today ? "Move to Master" : "Move to Today") {
                                            moveToOtherList(item)
                                        }
                                        .tint(dynamicPrimaryColor)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteTask(item)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                            .onMove(perform: moveItem)
                        }

                        Section(header:
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(plantVeryLightBlue)
                                    .frame(width: 10, height: 10)
                                Text("Completed")
                                    .fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.subheadline)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(
                                LinearGradient(
                                    colors: [plantVeryLightBlue.opacity(0.4), dynamicSecondaryBackgroundColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(6)
                            .listRowInsets(EdgeInsets())
                        ) {
                            ForEach(filteredItems.filter { $0.isDone }) { item in
                                TodoListItemView(item: item, todoViewModel: viewModel, onRequestProofCapture: { pendingProofFromList = $0 })
                                    .listRowBackground(dynamicSecondaryBackgroundColor)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button(selectedFilter == .today ? "Move to Master" : "Move to Today") {
                                            moveToOtherList(item)
                                        }
                                        .tint(dynamicPrimaryColor)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            deleteTask(item)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .background(dynamicBackgroundColor)
                }
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
                                    .fill(plantPeach.opacity(0.6))
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
                        
                        Button(action: {
                            showGoogleCalendarView.toggle()
                        }) {
                            Image(systemName: showGoogleCalendarView ? "checklist" : "calendar")
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
            .overlay(tutorialOverlay)
            .sheet(item: $pendingProofFromList, onDismiss: { pendingProofFromList = nil }) { proofContext in
                TaskProofCaptureView(
                    context: proofContext,
                    onSkip: { pendingProofFromList = nil },
                    onPosted: { postId in
                        applyProofPostId(postId, localTaskId: proofContext.localTaskId)
                        pendingProofFromList = nil
                    }
                )
                .environmentObject(FirebaseManager.shared)
            }
            .sheet(isPresented: $viewModel.showingNewItemView) {
                NewItemview(newItemPresented: $viewModel.showingNewItemView, selectedOrigin: selectedFilter == .today ? .today : .master)
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
                    .fill(plantPeach.opacity(0.6))
                    .frame(height: 40)
                    .padding(.horizontal)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: highlightFilterButton)
            }

            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = .today
                    }
                } label: {
                    Text("Today")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(selectedFilter == .today ? .white : .black.opacity(0.65))
                        .background(selectedFilter == .today ? dynamicPrimaryColor : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedFilter = .master
                    }
                } label: {
                    Text("Master List")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(selectedFilter == .master ? .white : .black.opacity(0.65))
                        .background(selectedFilter == .master ? dynamicPrimaryColor : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(4)
            .background(Capsule().fill(Color.black.opacity(0.06)))
            .padding()
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
                TodoListItemView(item: item, todoViewModel: viewModel, onRequestProofCapture: { pendingProofFromList = $0 })
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTask(item)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                        }
                    }
            }
            .onMove(perform: moveItem)
        }
    }
    
    private var completedSection: some View {
        Section(header: sectionHeader(title: "Completed")) {
            ForEach(filteredItems.filter { $0.isDone }) { item in
                TodoListItemView(item: item, todoViewModel: viewModel, onRequestProofCapture: { pendingProofFromList = $0 })
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTask(item)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                        }
                    }
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
            calendarButton
        }
    }
    
    private var addButton: some View {
        ZStack(alignment: .center) {
            if highlightAddButton {
                Circle()
                    .fill(plantPeach.opacity(0.6))
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
    
    private var calendarButton: some View {
        Button(action: {
            navigateToCalendar = true
        }) {
            Image(systemName: "calendar")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundColor(dynamicSecondaryColor)
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
    
    private func deleteTask(_ item: TodoItem) {
        let taskId = item.localTaskId

        if let sharedId = item.sharedTaskId {
            if item.isDone {
                FirebaseManager.shared.deleteSharedTask(sharedTaskId: sharedId) { error in
                    if let error = error { print("Failed to delete shared task: \(error)") }
                }
            } else {
                FirebaseManager.shared.markSharedTaskDiscarded(sharedTaskId: sharedId) { error in
                    if let error = error { print("Failed to mark shared task as discarded: \(error)") }
                }
            }
        }

        context.delete(item)

        FirebaseManager.shared.deleteTodoItem(localTaskId: taskId) { error in
            if let error = error {
                print("Todoview: Failed to delete task from Firebase: \(error.localizedDescription)")
            } else {
                print("Todoview: Successfully deleted task from Firebase")
            }
        }
    }

    private var filteredItems: [TodoItem] {
        switch selectedFilter {
        case .today:
            return items
                .filter { $0.origin == .today }
                .sorted { lhs, rhs in
                    // User-dragged tasks always rank above the auto-sorted groups.
                    if lhs.userPinned != rhs.userPinned {
                        return lhs.userPinned
                    }
                    if lhs.userPinned {
                        return lhs.position < rhs.position
                    }
                    switch (lhs.scheduledStartTime, rhs.scheduledStartTime) {
                    case let (l?, r?): return l < r
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return lhs.position < rhs.position
                    }
                }
        case .master:
            return items.filter { $0.origin == .master }
        }
    }

    func moveItem(from source: IndexSet, to destination: Int) {
        var activeItems = filteredItems.filter { !$0.isDone }
        let movedItems = source.map { activeItems[$0] }
        activeItems.move(fromOffsets: source, toOffset: destination)

        for (index, item) in activeItems.enumerated() {
            item.position = index
        }
        for item in movedItems {
            item.userPinned = true
        }

        try? context.save()
    }

    private func moveToOtherList(_ item: TodoItem) {
        item.origin = selectedFilter == .today ? .master : .today
        try? context.save()
        
        // Sync origin change to Firebase
        if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
            let codableTask = TodoItemCodable(from: item, userId: userId)
            FirebaseManager.shared.saveTodoItem(codableTask) { error in
                if let error = error {
                    print("Todoview: Failed to sync task move to Firebase: \(error.localizedDescription)")
                } else {
                    print("Todoview: Successfully synced task move to Firebase")
                }
            }
        }
    }

    private func applyProofPostId(_ postId: String, localTaskId: String?) {
        guard let localTaskId = localTaskId else { return }
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.localTaskId == localTaskId }
        )
        guard let item = try? context.fetch(descriptor).first else { return }
        item.proofPostId = postId
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
