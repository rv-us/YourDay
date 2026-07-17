import SwiftUI
import SwiftData
import GoogleSignIn
import FirebaseFirestore
import FirebaseAuth
import AuthenticationServices
import UIKit


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
    @State private var reauthorizationRequest: ConnectionReauthorizationRequest?
    @State private var showReauthorizationFailureAlert = false
    @State private var reauthorizationFailureMessage = ""
    @State private var showLastDayView = false
    /// Calendar day (yyyy-MM-dd) when the user dismissed LastDay; gates re-showing until the next day.
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""
    /// Calendar day when daily eval + cleanup ran; separate so LastDay can reappear until dismiss.
    @AppStorage("lastDailyEvaluationDate") private var lastDailyEvaluationDateString: String = ""
    @AppStorage("lastAppOpenDateForWitheringCheck") private var lastAppOpenDateForWitheringCheckString: String = ""

    @State private var showMigrateTasksView = false
    @State private var newDayEvaluationTriggeredLastDayView = false
    /// Re-entry guard: new-day logic is triggered from both .task and didBecomeActive,
    /// which can interleave across its awaits on a cold launch.
    @State private var isProcessingNewDayLogic = false
    
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
    @ObservedObject private var penaltyProcessor = FocusPenaltyProcessor.shared
    @ObservedObject private var screenTimeManager = ScreenTimeManager.shared
    @ObservedObject private var incomingChatBannerManager = IncomingChatBannerManager.shared
    @State private var showFocusPenaltyToast = false
    @State private var focusPenaltyToastMessage = ""

    private enum Tab: String, CaseIterable {
        case tasks, garden, dashboard, scheduling, settings
    }
    @State private var selectedTab: Tab = .dashboard
    @State private var incomingChatListener: ListenerRegistration?
    @State private var groupTaskListener: ListenerRegistration?

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated || loginViewModel.isGuest {
                authenticatedView
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            #if DEBUG
            // UI-test seam: "-UITestGardenSmoke" jumps straight to the Garden
            // tab as a local guest so the smoke test never touches auth,
            // Firebase, or display-name moderation.
            if ProcessInfo.processInfo.arguments.contains("-UITestGardenSmoke") {
                loginViewModel.userDisplayName = "UITest"
                loginViewModel.isGuest = true
                selectedTab = .garden
            }
            #endif
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
                startIncomingChatListenerIfNeeded()
                Task {
                    await TaskEndMonitor.shared.checkForEndedTasks()
                    await MainActor.run {
                        journalViewModel.reconcileJournalPromptsFromMonitor()
                    }
                }
            } else {
                if !loginViewModel.isGuest {
                    clearAllLocalUserDataOnLogout()
                }
                incomingChatListener?.remove()
                incomingChatListener = nil
                groupTaskListener?.remove()
                groupTaskListener = nil
            }
        }
        .onChange(of: loginViewModel.isGuest) { _, isGuestNow in
            if isGuestNow {
                incomingChatListener?.remove()
                incomingChatListener = nil
                groupTaskListener?.remove()
                groupTaskListener = nil
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
            if TrelloOAuthCoordinator.shared.resumeIfOpenURL(url) {
                return
            }
            if GoogleCalendarLinkedOAuthCoordinator.shared.resumeLinkedOAuthIfOpenURL(url) {
                return
            }
            GIDSignIn.sharedInstance.handle(url)
        }
        .alert("Sign Out Issue", isPresented: $showSignOutErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(signOutErrorMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionReauthorizationRequired)) { notification in
            guard let request = ConnectionReauthorizationNotifier.request(from: notification) else { return }
            reauthorizationRequest = request
        }
        .alert(
            reauthorizationTitle(for: reauthorizationRequest),
            isPresented: Binding(
                get: { reauthorizationRequest != nil },
                set: { if !$0 { reauthorizationRequest = nil } }
            ),
            presenting: reauthorizationRequest
        ) { request in
            Button(reauthorizationButtonTitle(for: request)) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    startConnectionReauthorization(for: request)
                }
            }
            Button("Not now", role: .cancel) { }
        } message: { request in
            Text(reauthorizationMessage(for: request))
        }
        .alert("Connection Issue", isPresented: $showReauthorizationFailureAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(reauthorizationFailureMessage)
        }
    }

    private var authenticatedView: some View {
        mainTabView
            .tint(dynamicSecondaryColor)
            .task {
                await processNewDayLogicIfNeeded()
                await TaskEndMonitor.shared.checkForEndedTasks()
                journalViewModel.reconcileJournalPromptsFromMonitor()
            }
            .sheet(isPresented: $showLastDayView, onDismiss: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let todayString = formatter.string(from: Calendar.current.startOfDay(for: Date()))
                lastSummaryDateString = todayString

                if newDayEvaluationTriggeredLastDayView {
                    newDayEvaluationTriggeredLastDayView = false
                    isInDailyFlow = true
                    self.showMigrateTasksView = true
                    GeofenceManager.shared.classifyAndSetupGeofences(context: modelContext)
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
                    await TrelloTaskSyncService.refreshTrelloMirroredTasks(modelContext: modelContext)
                    await TaskEndMonitor.shared.checkForEndedTasks()
                    await MainActor.run {
                        journalViewModel.reconcileJournalPromptsFromMonitor()
                    }
                }
                Task { @MainActor in
                    await FocusPenaltyProcessor.shared.drainPending(
                        context: modelContext,
                        loginViewModel: loginViewModel
                    )
                    await ScreenTimeManager.shared.writeSnapshotFromCurrentTasks(context: modelContext)
                    // Also refresh the cached Screen Time authorization state
                    // and re-apply the shield in case the user changed their
                    // Screen Time permissions in iOS Settings while we were
                    // backgrounded, or iOS returned a stale status earlier.
                    await ScreenTimeManager.shared.refreshAuthorizationAndReapplyShieldIfNeeded()
                }
            }
            .onAppear {
                NotificationManager.shared.setJournalViewModel(journalViewModel)
                startIncomingChatListenerIfNeeded()
                startGroupTaskListenerIfNeeded()
                Task { @MainActor in
                    await FocusPenaltyProcessor.shared.drainPending(
                        context: modelContext,
                        loginViewModel: loginViewModel
                    )
                    await ScreenTimeManager.shared.writeSnapshotFromCurrentTasks(context: modelContext)
                }
            }
            .onChange(of: allTodoItems.map { "\($0.title)-\($0.isDone)-\($0.manualScheduleGoogleEventId ?? "")" }.sorted().joined(separator: "|")) { _, _ in
                ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)
            }
            .onChange(of: penaltyProcessor.lastDrainResult) { _, result in
                guard let result else { return }
                let noun = result.penaltyCount == 1 ? "break" : "breaks"
                focusPenaltyToastMessage = "Lost \(result.totalDeducted) point\(result.totalDeducted == 1 ? "" : "s") for \(result.penaltyCount) focus \(noun)."
                showFocusPenaltyToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    showFocusPenaltyToast = false
                    penaltyProcessor.acknowledgeLastDrain()
                }
            }
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    if let banner = incomingChatBannerManager.activeBanner {
                        IncomingChatBannerView(banner: banner) {
                            incomingChatBannerManager.dismiss()
                            selectedTab = .dashboard
                            ChatNavigationCoordinator.shared.openChat(
                                FriendEntry(
                                    userId: banner.senderId,
                                    displayName: banner.senderName
                                )
                            )
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                    }

                    if showFocusPenaltyToast {
                        Text(focusPenaltyToastMessage)
                            .font(.callout)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(dynamicDestructiveColor.opacity(0.9))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .padding(.top, incomingChatBannerManager.activeBanner == nil ? 8 : 0)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.86), value: incomingChatBannerManager.activeBanner)
            }
    }

    private func startIncomingChatListenerIfNeeded() {
        guard loginViewModel.isAuthenticated, !loginViewModel.isGuest, incomingChatListener == nil else { return }
        incomingChatListener = firebaseManager.listenToIncomingChatMessages { message, senderName in
            Task { @MainActor in
                IncomingChatBannerManager.shared.show(message: message, senderName: senderName)
            }
        }
    }

    private func startGroupTaskListenerIfNeeded() {
        guard loginViewModel.isAuthenticated, !loginViewModel.isGuest, groupTaskListener == nil else { return }
        groupTaskListener = firebaseManager.listenToMyGroupTasks { tasks in
            materializeGroupTasks(tasks)
        }
    }

    /// Auto-adds group tasks assigned to this user into the local todo list.
    /// `materializedBy` keeps a task from coming back after the user deletes it
    /// locally or the daily cleanup removes the completed copy; the deterministic
    /// localTaskId makes the Firestore write idempotent across the user's devices.
    private func materializeGroupTasks(_ tasks: [GroupTask]) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        for task in tasks {
            guard let groupTaskId = task.id,
                  task.assigneeIds.contains(userId),
                  !task.materializedBy.contains(userId) else { continue }

            let localId = "gt_\(groupTaskId)"
            let descriptor = FetchDescriptor<TodoItem>(predicate: #Predicate { $0.localTaskId == localId })
            if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
                firebaseManager.markGroupTaskMaterialized(groupTaskId: groupTaskId)
                continue
            }

            let todo = TodoItem(
                localTaskId: localId,
                title: task.title,
                detail: task.detail,
                dueDate: task.dueDate,
                origin: .today,
                groupTaskId: groupTaskId,
                groupId: task.groupId,
                groupName: task.groupName
            )
            modelContext.insert(todo)
            do {
                try modelContext.save()
            } catch {
                print("ContentView: Failed to save materialized group task \(groupTaskId): \(error.localizedDescription)")
                continue
            }

            firebaseManager.saveTodoItem(TodoItemCodable(from: todo, userId: userId)) { error in
                if let error = error {
                    print("ContentView: Failed to sync materialized group task to Firebase: \(error.localizedDescription)")
                }
            }
            firebaseManager.markGroupTaskMaterialized(groupTaskId: groupTaskId)
        }
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
        SettingsHubView(
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

    private func reauthorizationTitle(for request: ConnectionReauthorizationRequest?) -> String {
        switch request?.service {
        case .googleCalendar:
            return "Google Calendar Needs Access"
        case .trello:
            return "Trello Needs Access"
        case .none:
            return "Connection Needs Access"
        }
    }

    private func reauthorizationButtonTitle(for request: ConnectionReauthorizationRequest) -> String {
        switch request.service {
        case .googleCalendar:
            return request.isLinkedGoogleCalendarAccount ? "Reconnect Google Account" : "Reconnect Google Calendar"
        case .trello:
            return "Reconnect Trello"
        }
    }

    private func reauthorizationMessage(for request: ConnectionReauthorizationRequest) -> String {
        switch request.service {
        case .googleCalendar:
            let accountLabel = request.displayName ?? "Google Calendar"
            if request.isLinkedGoogleCalendarAccount {
                return "\(accountLabel) stopped allowing calendar access. Reconnect it to keep showing events from that account."
            }
            return "\(accountLabel) stopped allowing calendar access. Reconnect Google Calendar so YourDay can keep reading and creating events."
        case .trello:
            return "Your Trello authorization stopped working. Reconnect Trello so YourDay can keep syncing cards and tasks."
        }
    }

    private func startConnectionReauthorization(for request: ConnectionReauthorizationRequest) {
        switch request.service {
        case .googleCalendar:
            if request.isLinkedGoogleCalendarAccount {
                reconnectLinkedGoogleCalendarAccount()
            } else {
                reconnectPrimaryGoogleCalendar()
            }
        case .trello:
            reconnectTrello()
        }
    }

    private func reconnectPrimaryGoogleCalendar() {
        GoogleCalendarManager.shared.reauthorizeCalendarWriteAccess { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    GoogleCalendarEventFetchService.syncPrimaryAccountRecordIfNeeded()
                case .failure(let error):
                    showConnectionReauthorizationFailure(error.localizedDescription)
                }
            }
        }
    }

    private func reconnectLinkedGoogleCalendarAccount() {
        guard let presenting = rootViewController() else {
            showConnectionReauthorizationFailure("Could not show Google sign-in. Try again after closing other sheets.")
            return
        }
        GoogleCalendarLinkedOAuthCoordinator.shared.signInReadOnlyLinkedAccount(presenting: presenting) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    showConnectionReauthorizationFailure(error.localizedDescription)
                }
            }
        }
    }

    private func reconnectTrello() {
        guard let anchor = presentationAnchor() else {
            showConnectionReauthorizationFailure("Could not open Trello sign-in.")
            return
        }
        TrelloOAuthCoordinator.shared.start(presentationAnchor: anchor) { result in
            Task { @MainActor in
                switch result {
                case .success(let token):
                    do {
                        try TrelloConnectionKeychain.saveUserToken(token)
                        await TrelloTaskSyncService.refreshTrelloMirroredTasks(modelContext: modelContext)
                    } catch {
                        showConnectionReauthorizationFailure(error.localizedDescription)
                    }
                case .failure(let error):
                    if let trelloError = error as? TrelloOAuthError,
                       case .userCancelled = trelloError {
                        return
                    }
                    showConnectionReauthorizationFailure(error.localizedDescription)
                }
            }
        }
    }

    private func showConnectionReauthorizationFailure(_ message: String) {
        reauthorizationFailureMessage = message
        showReauthorizationFailureAlert = true
    }

    private func rootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    private func presentationAnchor() -> ASPresentationAnchor? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
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
        guard !isProcessingNewDayLogic else {
            print("🕒 [DEBUG] new day logic already running, skipping")
            return
        }
        isProcessingNewDayLogic = true
        defer { isProcessingNewDayLogic = false }

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
        
        print("🕒 [DEBUG] todayString: \(todayString), lastSummaryDate: \(lastSummaryDateString), lastDailyEval: \(lastDailyEvaluationDateString)")

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
        if todayString != lastDailyEvaluationDateString {
            print("[DailyEval] new calendar day — running daily point evaluation (today=\(todayString))")
            let tally = await withCheckedContinuation { (continuation: CheckedContinuation<YesterdayTaskProofTallyResult, Never>) in
                firebaseManager.fetchYesterdayTaskProofTallyForPoints(evaluationDate: Date()) { result in
                    continuation.resume(returning: result)
                }
            }
            proofTallyForCleanup = tally
            print("[DailyEval] proof tally complete — qualifyingPosts=\(tally.qualifyingPostIds.count) yesterdayPosts=\(tally.allYesterdayPostIds.count) eligibleLocalTasks=\(tally.eligibleLocalTaskIds.count) eligibleSharedTasks=\(tally.eligibleSharedTaskIds.count) → calling evaluateDailyPoints")
            _ = PointManager.evaluateDailyPoints(
                context: modelContext,
                tasks: allTodoItems,
                proofBonusEligibleLocalTaskIds: tally.eligibleLocalTaskIds,
                proofBonusEligibleSharedTaskIds: tally.eligibleSharedTaskIds,
                proofVoteRollupsByLocalTaskId: tally.proofVoteRollupsByLocalTaskId,
                proofVoteRollupsBySharedTaskId: tally.proofVoteRollupsBySharedTaskId
            )

            // Clear stale proofPostId references locally and remotely before deleteOldDoneTasks tombstones the items.
            if !tally.allYesterdayPostIds.isEmpty {
                let idsToClear = Set(tally.allYesterdayPostIds)
                let currentUserId = FirebaseAuth.Auth.auth().currentUser?.uid
                var clearedProofIds = 0
                for item in allTodoItems {
                    guard let pid = item.proofPostId, idsToClear.contains(pid) else { continue }
                    item.proofPostId = nil
                    clearedProofIds += 1
                    if let uid = currentUserId {
                        let codable = TodoItemCodable(from: item, userId: uid)
                        firebaseManager.saveTodoItem(codable) { error in
                            if let error = error {
                                print("[DailyEval] saveTodoItem after proof clear failed for \(item.localTaskId): \(error.localizedDescription)")
                            }
                        }
                    }
                }
                print("[DailyEval] cleared proofPostId on \(clearedProofIds) local TodoItem(s)")
            }

            await deleteOldDoneTasks()

            lastDailyEvaluationDateString = todayString
            shouldSyncStats = true
        }

        if lastDailyEvaluationDateString == todayString, todayString != lastSummaryDateString {
            newDayEvaluationTriggeredLastDayView = true
            showLastDayView = true
            shouldSyncStats = true
        } else {
            newDayEvaluationTriggeredLastDayView = false
        }

        do {
            try modelContext.save()
            if shouldSyncStats {
                loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: stats)
            }
            if let tally = proofTallyForCleanup, !tally.allYesterdayPostIds.isEmpty {
                print("[DailyEval] deleting \(tally.allYesterdayPostIds.count) yesterday proof post(s) from Firestore/Storage (\(tally.qualifyingPostIds.count) earned the 1.5× bonus)")
                for postId in tally.allYesterdayPostIds {
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
            } else if proofTallyForCleanup != nil {
                print("[DailyEval] no yesterday proof posts to delete")
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
            // Final push for any Trello-mirrored tasks whose completion may not have
            // synced yet — ensures dueComplete=true on Trello so the next daily import
            // won't re-create the card as an incomplete task.
            for task in tasksToDelete where task.trelloCardId != nil {
                await TrelloTaskSyncService.pushCompletion(for: task)
            }
            for task in tasksToDelete { modelContext.delete(task) }
            try modelContext.save()
        } catch {
            // Error deleting old done tasks
        }
    }
}
