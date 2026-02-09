import SwiftUI
import SwiftData
import GoogleSignIn


struct ContentView: View {
    @Environment(\.modelContext) private var modelContext


    @Query(sort: \PlayerStats.playerLevel) private var localPlayerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? {
        if localPlayerStatsList.isEmpty {
            return nil
        }
        return localPlayerStatsList.first
    }

    @StateObject private var loginViewModel = LoginViewModel()
    @StateObject private var firebaseManager = FirebaseManager.shared


    @State private var showSignOutErrorAlert = false
    @State private var signOutErrorMessage = ""
    @State private var showLastDayView = false
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""
    @AppStorage("lastAppOpenDateForWitheringCheck") private var lastAppOpenDateForWitheringCheckString: String = ""

    @State private var showMigrateTasksView = false
    @State private var newDayEvaluationTriggeredLastDayView = false
    
    @State private var showWitheringAlert = false
    @State private var witheringAlertMessage = ""
    
    // Daily flow state
    @State private var showDailyPlanningNote = false
    @State private var showSchedulingView = false
    @State private var schedulingAutoStart = false
    @State private var schedulingDate = Date()
    @State private var isInDailyFlow = false

    @Query private var allTodoItems: [TodoItem]
    @StateObject private var todoViewModel = TodoViewModel()
    @ObservedObject private var journalViewModel = JournalViewModel.shared

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated || loginViewModel.isGuest {
                TabView {
                                        Todoview()
                        .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                        .environmentObject(loginViewModel)
                        .environmentObject(firebaseManager)
                        
                    GardenView()
                        .tabItem { Label("Garden", systemImage: "leaf.fill") }
                        .environmentObject(loginViewModel)
                        .environmentObject(firebaseManager)

                    AddNotesView()
                        .tabItem { Label("Notes", systemImage: "square.and.pencil") }
                        .environmentObject(loginViewModel)

                    SocialView()
                        .tabItem { Label("Social", systemImage: "person.2.fill") }
                        .environmentObject(loginViewModel)
                        .environmentObject(firebaseManager)

                    SmartSchedulingView()
                        .tabItem { Label("Scheduling", systemImage: "calendar.badge.clock") }
                        .environmentObject(firebaseManager)

                    MoreView(
                        todoViewModel: todoViewModel,
                        loginViewModel: loginViewModel,
                        onSignOutRequested: {
                            requestSignOut()
                        }
                    )
                    .tabItem { Label("More", systemImage: "ellipsis.circle") }
                    .environmentObject(firebaseManager)
                }
                .tint(.black)
                .task {
                    await processNewDayLogicIfNeeded()
                }
                .sheet(isPresented: $showLastDayView, onDismiss: {
                    if newDayEvaluationTriggeredLastDayView {
                        newDayEvaluationTriggeredLastDayView = false
                        let tasksThatNeedReview = allTodoItems.filter { todoItem in
                             !todoItem.isDone || todoItem.subtasks.contains(where: { !$0.isDone })
                         }
                        if !tasksThatNeedReview.isEmpty {
                            isInDailyFlow = true
                            self.showMigrateTasksView = true
                        }
                    }
                }) {
                    NavigationView {
                        LastDayView(isModal: true)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { showLastDayView = false }
                                }
                            }
                    }
                    .environment(\.modelContext, modelContext)
                }
                .sheet(isPresented: $showMigrateTasksView, onDismiss: {
                    // After migration, show daily planning note if we're in the daily flow
                    if isInDailyFlow {
                        showDailyPlanningNote = true
                    }
                }) {
                    NavigationView {
                        MigrateTasksView()
                            .environment(\.modelContext, modelContext)
                            .environmentObject(firebaseManager)
                    }
                }
                .sheet(isPresented: $showDailyPlanningNote, onDismiss: {
                    // After planning note, show scheduling view
                    if isInDailyFlow {
                        schedulingDate = Calendar.current.startOfDay(for: Date())
                        schedulingAutoStart = true
                        showSchedulingView = true
                    }
                }) {
                    DailyPlanningNoteView(isPresented: $showDailyPlanningNote) {
                        // Completion handler - just dismiss, onDismiss will handle the next step
                        // The view will set isPresented = false itself
                    }
                    .environment(\.modelContext, modelContext)
                }
                .sheet(isPresented: $showSchedulingView, onDismiss: {
                    // Reset daily flow flags when scheduling view dismisses
                    isInDailyFlow = false
                    schedulingAutoStart = false
                }) {
                    SmartSchedulingView(initialDate: schedulingDate, autoStart: schedulingAutoStart)
                        .environmentObject(firebaseManager)
                }
                .alert("Plant Care Notice", isPresented: $showWitheringAlert) {
                    Button("OK") {}
                } message: {
                    Text(witheringAlertMessage)
                }
                .sheet(isPresented: $journalViewModel.showingJournalPrompt) {
                    if let pendingEvent = journalViewModel.pendingJournalPrompt {
                        JournalCompletionFlowView(journalViewModel: journalViewModel, pendingEvent: pendingEvent)
                            .onDisappear {
                                // Trigger AI analysis when journal entry is saved
                                // Note: This requires SchedulingAssistantViewModel, which is only available in SmartSchedulingView
                                // For now, we'll trigger it from there if needed
                            }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowJournalPrompt"))) { notification in
                    // Handle notification tap to show journal prompt
                    if let eventId = notification.userInfo?["eventId"] as? String {
                        journalViewModel.showPromptForEvent(eventId: eventId)
                    }
                }
                .onAppear {
                    // Set journal view model in notification delegate
                    JournalNotificationDelegate.shared.setJournalViewModel(journalViewModel)
                }

            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            if loginViewModel.isAuthenticated && localPlayerStatsList.isEmpty {
                let newStats = PlayerStats()
                modelContext.insert(newStats)
                do {
                    try modelContext.save()
                    loginViewModel.handleUserSession(localPlayerStats: newStats, modelContext: modelContext)
                } catch {
                    print("ContentView: Failed to save initial PlayerStats: \(error.localizedDescription)")
                    // Continue with the session even if save fails
                    loginViewModel.handleUserSession(localPlayerStats: newStats, modelContext: modelContext)
                }
            } else if loginViewModel.isAuthenticated, let stats = currentPlayerStats {
                loginViewModel.handleUserSession(localPlayerStats: stats, modelContext: modelContext)
            }
        }
        .onChange(of: loginViewModel.isAuthenticated) { _, userIsAuthenticated in
            if userIsAuthenticated {
                loginViewModel.handleUserSession(localPlayerStats: localPlayerStatsList.first, modelContext: modelContext)
            } else if !loginViewModel.isGuest { // Only clear data on explicit sign-out, not when entering guest mode
                clearAllLocalUserDataOnLogout()
            }
        }
        .onChange(of: loginViewModel.isGuest) { _, isGuestNow in
            if isGuestNow && localPlayerStatsList.isEmpty {
                // If entering guest mode and no local data exists, create it.
                loginViewModel.handleUserSession(localPlayerStats: nil, modelContext: modelContext)
            } else if !isGuestNow && !loginViewModel.isAuthenticated {
                // If exiting guest mode (and not to an authenticated state), clear local data.
                clearAllLocalUserDataOnLogout()
            }
        }
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
        .alert("Sign Out Issue", isPresented: $showSignOutErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(signOutErrorMessage)
        }
    }

    private func requestSignOut() {
        loginViewModel.requestSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessageText in
             if !didSignOut, let message = errorMessageText {
                self.signOutErrorMessage = message
                self.showSignOutErrorAlert = true
            }
        }
    }

    private func clearAllLocalUserDataOnLogout() {
        deleteSwiftData(modelType: PlayerStats.self)
        deleteSwiftData(modelType: TodoItem.self)
        deleteSwiftData(modelType: NoteItem.self)
        deleteSwiftData(modelType: DailySummaryTask.self)
        do {
            try modelContext.save()
        } catch {
            print("ContentView: Failed to save context after clearing data: \(error.localizedDescription)")
            // Continue even if save fails - the app should still function
        }
    }

    private func deleteSwiftData<T: PersistentModel>(modelType: T.Type) {
        let descriptor = FetchDescriptor<T>()
        do {
            let fetchedItems = try modelContext.fetch(descriptor)
            if fetchedItems.isEmpty { return }
            for item in fetchedItems { modelContext.delete(item) }
        } catch {
            // Error fetching for deletion
        }
    }

    private func processNewDayLogicIfNeeded() async {
        guard let stats = currentPlayerStats else {
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        if todayString != lastAppOpenDateForWitheringCheckString {
            if let lastLoginActual = stats.lastLoginDate {
                let daysSinceLastLogin = calendar.dateComponents([.day], from: lastLoginActual, to: today).day ?? 0
                
                if daysSinceLastLogin > 5 {
                    var witheredCount = 0
                    let fullyGrownPlantIndices = stats.placedPlants.indices.filter { index in
                        let plant = stats.placedPlants[index]
                        return plant.isFullyGrown && plant.name != PlantLibrary.blueprint(withId: "withered_1")?.name
                    }
                    
                    if !fullyGrownPlantIndices.isEmpty {
                        let numberToWither = Int(ceil(Double(fullyGrownPlantIndices.count) / 3.0))
                        let indicesToWither = fullyGrownPlantIndices.shuffled().prefix(numberToWither)
                        
                        if let witheredBlueprint = PlantLibrary.blueprint(withId: "withered_1") {
                            for index in indicesToWither {
                                if index < stats.placedPlants.count {
                                    stats.placedPlants[index].name = witheredBlueprint.name
                                    stats.placedPlants[index].assetName = witheredBlueprint.assetName
                                    stats.placedPlants[index].iconName = witheredBlueprint.iconName
                                    stats.placedPlants[index].rarity = witheredBlueprint.rarity
                                    stats.placedPlants[index].theme = witheredBlueprint.theme
                                    stats.placedPlants[index].baseValue = witheredBlueprint.baseValue
                                    stats.placedPlants[index].daysLeftTillFullyGrown = witheredBlueprint.initialDaysToGrow
                                    stats.placedPlants[index].initialDaysToGrow = witheredBlueprint.initialDaysToGrow
                                    witheredCount += 1
                                }
                            }
                        }
                        if witheredCount > 0 {
                            self.witheringAlertMessage = "Welcome back! It's been \(daysSinceLastLogin) days. Unfortunately, \(witheredCount) of your plants withered."
                            self.showWitheringAlert = true
                            stats.updateGardenValue()
                        }
                    }
                }
            }
            lastAppOpenDateForWitheringCheckString = todayString
            
            do {
                try modelContext.save()
                loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: stats)
            } catch {
                // Error saving PlayerStats
            }
        }
        stats.lastLoginDate = Date()
        print("🕒 [DEBUG] Saving lastLoginDate: \(String(describing: stats.lastLoginDate))")

        if todayString != lastSummaryDateString {
            let (points, _) = PointManager.evaluateDailyPoints(context: modelContext, tasks: allTodoItems)
            await deleteOldDoneTasks()

            let tasksThatNeedReview = allTodoItems.filter { todoItem in
                !todoItem.isDone || todoItem.subtasks.contains(where: { !$0.isDone })
            }

            if points > 0 {
                newDayEvaluationTriggeredLastDayView = true
                showLastDayView = true
            } else {
                newDayEvaluationTriggeredLastDayView = false
                if !tasksThatNeedReview.isEmpty {
                    isInDailyFlow = true
                    showMigrateTasksView = true
                }
            }
            lastSummaryDateString = todayString
        } else {
            newDayEvaluationTriggeredLastDayView = false
        }
    }

    private func deleteOldDoneTasks() async {
        let oldDoneTasksPredicate = #Predicate<TodoItem> {
            $0.isDone == true
        }
        let descriptor = FetchDescriptor<TodoItem>(predicate: oldDoneTasksPredicate)
        do {
            let tasksToDelete = try modelContext.fetch(descriptor)
            if tasksToDelete.isEmpty { return }
            for task in tasksToDelete { modelContext.delete(task) }
            try modelContext.save()
        } catch {
            // Error deleting old done tasks
        }
    }
}
