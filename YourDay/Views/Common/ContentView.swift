import SwiftUI
import SwiftData
import GoogleSignIn
import FirebaseFirestore


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
    @StateObject private var locationManager = LocationManager()

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

    private enum Tab: String, CaseIterable {
        case tasks, garden, dashboard, scheduling, settings
    }
    @State private var selectedTab: Tab = .dashboard
    @State private var incomingChatListener: ListenerRegistration?

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated || loginViewModel.isGuest {
                authenticatedView
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
            } else {
                if !loginViewModel.isGuest {
                    clearAllLocalUserDataOnLogout()
                }
                incomingChatListener?.remove()
                incomingChatListener = nil
            }
        }
        .onChange(of: loginViewModel.isGuest) { _, isGuestNow in
            if isGuestNow {
                incomingChatListener?.remove()
                incomingChatListener = nil
            }
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

    private var authenticatedView: some View {
        mainTabView
            .tint(dynamicSecondaryColor)
            .task {
                await processNewDayLogicIfNeeded()
            }
            .sheet(isPresented: $showLastDayView, onDismiss: {
                if newDayEvaluationTriggeredLastDayView {
                    newDayEvaluationTriggeredLastDayView = false
                    isInDailyFlow = true
                    self.showMigrateTasksView = true
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
                if isInDailyFlow {
                    schedulingDate = Calendar.current.startOfDay(for: Date())
                    schedulingAutoStart = true
                    showSchedulingView = true
                }
            }) {
                DailyPlanningNoteView(isPresented: $showDailyPlanningNote) { }
                    .environment(\.modelContext, modelContext)
            }
            .sheet(isPresented: $showSchedulingView, onDismiss: {
                isInDailyFlow = false
                schedulingAutoStart = false
            }) {
                SmartSchedulingView(
                    initialDate: schedulingDate,
                    autoStart: schedulingAutoStart,
                    onSkip: { showSchedulingView = false }
                )
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
                }
            }
            .sheet(isPresented: $journalViewModel.showingTaskProofCapture, onDismiss: {
                journalViewModel.completeScheduledProofCaptureFlow()
            }) {
                if let captureContext = journalViewModel.pendingTaskProofCapture {
                    TaskProofCaptureView(
                        context: captureContext,
                        onSkip: {
                            journalViewModel.completeScheduledProofCaptureFlow()
                        },
                        onPosted: { _ in
                            journalViewModel.completeScheduledProofCaptureFlow()
                        }
                    )
                    .environmentObject(firebaseManager)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowJournalPrompt"))) { notification in
                if let eventId = notification.userInfo?["eventId"] as? String {
                    journalViewModel.showPromptForEvent(eventId: eventId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task {
                    await processNewDayLogicIfNeeded()
                }
                TaskEndMonitor.shared.forceCheck()
            }
            .onAppear {
                NotificationManager.shared.setJournalViewModel(journalViewModel)
                startIncomingChatListenerIfNeeded()
                updateLocationManagerTaskSummary()
            }
            .onChange(of: allTodoItems.map { "\($0.title)-\($0.isDone)" }.sorted().joined(separator: "|")) { _, _ in
                updateLocationManagerTaskSummary()
            }
    }

    private func updateLocationManagerTaskSummary() {
        let summary = allTodoItems.filter { !$0.isDone }.map(\.title).joined(separator: ", ")
        locationManager.updateTaskSummary(summary.isEmpty ? "No tasks" : summary)
    }

    private func startIncomingChatListenerIfNeeded() {
        guard loginViewModel.isAuthenticated, !loginViewModel.isGuest, incomingChatListener == nil else { return }
        // Remote push (FCM Cloud Function) now handles chat notifications when the app is
        // backgrounded or terminated. The Firestore listener is kept so the app can update
        // unread state while foregrounded, but we no longer fire a local notification here
        // to avoid duplicates with the remote push.
        incomingChatListener = firebaseManager.listenToIncomingChatMessages { _, _ in }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            tasksTab
                .tag(Tab.tasks)
            gardenTab
                .tag(Tab.garden)
            dashboardTab
                .tag(Tab.dashboard)
            schedulingTab
                .tag(Tab.scheduling)
            moreTab
                .tag(Tab.settings)
        }
    }

    @ViewBuilder
    private var tasksTab: some View {
        Todoview()
            .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
            .environmentObject(loginViewModel)
            .environmentObject(firebaseManager)
    }

    @ViewBuilder
    private var gardenTab: some View {
        GardenView()
            .tabItem { Label("Garden", systemImage: "leaf.fill") }
            .environmentObject(loginViewModel)
            .environmentObject(firebaseManager)
    }

    @ViewBuilder
    private var dashboardTab: some View {
        DashboardView(onSwitchToTasks: {
            selectedTab = .tasks
        })
            .tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            .environmentObject(loginViewModel)
            .environmentObject(firebaseManager)
    }

    @ViewBuilder
    private var schedulingTab: some View {
        SmartSchedulingView()
            .tabItem { Label("Scheduling", systemImage: "calendar.badge.clock") }
            .environmentObject(firebaseManager)
    }

    @ViewBuilder
    private var moreTab: some View {
        NotificationSettingsView(
            todoViewModel: todoViewModel,
            loginViewModel: loginViewModel,
            onSignOutRequested: { requestSignOut() }
        )
        .tabItem { Label("Settings", systemImage: "ellipsis.circle") }
        .environmentObject(locationManager)
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
        print("🕒 [DEBUG] processNewDayLogicIfNeeded called")
        guard let stats = currentPlayerStats else {
            print("🕒 [DEBUG] currentPlayerStats is nil, skipping new day logic")
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)
        var shouldSyncStats = false
        
        print("🕒 [DEBUG] todayString: \(todayString), lastSummaryDateString: \(lastSummaryDateString)")

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
            shouldSyncStats = true
        }
        
        stats.lastLoginDate = Date()
        print("🕒 [DEBUG] Saving lastLoginDate: \(String(describing: stats.lastLoginDate))")
        shouldSyncStats = true

        var proofTallyForCleanup: YesterdayTaskProofTallyResult?
        if todayString != lastSummaryDateString {
            print("[DailyEval] new calendar day — running daily point evaluation (today=\(todayString))")
            let tally = await withCheckedContinuation { (continuation: CheckedContinuation<YesterdayTaskProofTallyResult, Never>) in
                firebaseManager.fetchYesterdayTaskProofTallyForPoints(evaluationDate: Date()) { result in
                    continuation.resume(returning: result)
                }
            }
            proofTallyForCleanup = tally
            print("[DailyEval] proof tally complete — qualifyingPosts=\(tally.qualifyingPostIds.count) eligibleLocalTasks=\(tally.eligibleLocalTaskIds.count) eligibleSharedTasks=\(tally.eligibleSharedTaskIds.count) → calling evaluateDailyPoints")
            _ = PointManager.evaluateDailyPoints(
                context: modelContext,
                tasks: allTodoItems,
                proofBonusEligibleLocalTaskIds: tally.eligibleLocalTaskIds,
                proofBonusEligibleSharedTaskIds: tally.eligibleSharedTaskIds,
                proofVoteRollupsByLocalTaskId: tally.proofVoteRollupsByLocalTaskId,
                proofVoteRollupsBySharedTaskId: tally.proofVoteRollupsBySharedTaskId
            )
            await deleteOldDoneTasks()

            // Always trigger the flow when a new day is detected
            newDayEvaluationTriggeredLastDayView = true
            showLastDayView = true
            
            lastSummaryDateString = todayString
            shouldSyncStats = true
        } else {
            newDayEvaluationTriggeredLastDayView = false
        }
        
        do {
            try modelContext.save()
            if shouldSyncStats {
                loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: stats)
            }
            if let tally = proofTallyForCleanup, !tally.qualifyingPostIds.isEmpty {
                print("[DailyEval] deleting \(tally.qualifyingPostIds.count) qualifying proof post(s) from Firestore/Storage")
                for postId in tally.qualifyingPostIds {
                    print("[DailyEval] deleting proof post id=\(postId) …")
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        firebaseManager.deleteTaskProofPost(postId: postId) { error in
                            if let error {
                                print("[DailyEval] deleteTaskProofPost failed for \(postId): \(error.localizedDescription)")
                            } else {
                                print("[DailyEval] deleteTaskProofPost finished for \(postId)")
                            }
                            continuation.resume()
                        }
                    }
                }
                var clearedProofIds = 0
                for item in allTodoItems {
                    if let pid = item.proofPostId, tally.qualifyingPostIds.contains(pid) {
                        item.proofPostId = nil
                        clearedProofIds += 1
                    }
                }
                print("[DailyEval] cleared proofPostId on \(clearedProofIds) local TodoItem(s)")
                try modelContext.save()
            } else if proofTallyForCleanup != nil {
                print("[DailyEval] no qualifying proof posts to delete (per-post vote gate not met or no posts)")
            }
        } catch {
            // Error saving PlayerStats
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
