import SwiftUI
import SwiftData
import GoogleSignIn

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlayerStats.playerLevel) private var localPlayerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? {
        localPlayerStatsList.first
    }

    @StateObject private var loginViewModel = LoginViewModel()

    @State private var showSignOutErrorAlert = false
    @State private var signOutErrorMessage = ""
    @State private var showLastDayView = false
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""

    @State private var showMigrateTasksView = false
    @State private var newDayEvaluationTriggeredLastDayView = false

    @Query private var allTodoItems: [TodoItem]
    @StateObject private var todoViewModel = TodoViewModel()

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated {
                TabView {
                    GardenView()
                        .tabItem { Label("Garden", systemImage: "leaf.fill") }
                        .environmentObject(loginViewModel)

                    Todoview()
                        .tabItem { Label("Tasks", systemImage: "checkmark.circle") }
                        .environmentObject(loginViewModel)

                    AddNotesView()
                        .tabItem { Label("Notes", systemImage: "square.and.pencil") }
                        .environmentObject(loginViewModel)

                    LastDayView(isModal: false)
                        .tabItem { Label("Summary", systemImage: "star.fill") }
                        .environmentObject(loginViewModel)
                    
                    NotificationSettingsView(
                        todoViewModel: todoViewModel,
                        loginViewModel: loginViewModel,
                        onSignOutRequested: {
                            requestSignOut()
                        }
                    )
                         .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
                .task {
                    await processNewDayLogicIfNeeded()
                }
                .sheet(isPresented: $showLastDayView, onDismiss: {
                    if newDayEvaluationTriggeredLastDayView {
                        newDayEvaluationTriggeredLastDayView = false
                        
                        // Check if there are tasks that MigrateTasksView would display
                        // This check is performed AFTER old completed tasks are deleted.
                        let tasksThatNeedReview = allTodoItems.filter { todoItem in
                             !todoItem.isDone || todoItem.subtasks.contains(where: { !$0.isDone })
                         }
                        if !tasksThatNeedReview.isEmpty {
                            self.showMigrateTasksView = true
                        } else {
                             print("ContentView: No tasks to migrate after LastDayView dismissal.")
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
                .sheet(isPresented: $showMigrateTasksView) {
                    NavigationView {
                        MigrateTasksView()
                            .environment(\.modelContext, modelContext)
                    }
                }
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            if loginViewModel.isAuthenticated {
                loginViewModel.handleUserSession(localPlayerStats: currentPlayerStats, modelContext: modelContext)
            }
        }
        .onChange(of: loginViewModel.isAuthenticated) { _, userIsAuthenticated in
            if userIsAuthenticated {
                let currentLocalStatsOnChange = localPlayerStatsList.first
                loginViewModel.handleUserSession(localPlayerStats: currentLocalStatsOnChange, modelContext: modelContext)
            } else {
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
        loginViewModel.attemptSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessageText in
            if !didSignOut {
                self.signOutErrorMessage = errorMessageText ?? "An unknown error occurred during sign out."
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
            print("ContentView: Error saving context after clearing all local data: \(error.localizedDescription)")
        }
    }

    private func deleteSwiftData<T: PersistentModel>(modelType: T.Type) {
        let descriptor = FetchDescriptor<T>()
        do {
            let fetchedItems = try modelContext.fetch(descriptor)
            if fetchedItems.isEmpty {
                return
            }
            for item in fetchedItems {
                modelContext.delete(item)
            }
        } catch {
            print("ContentView: Error fetching local \(String(describing:modelType)) for deletion: \(error.localizedDescription)")
        }
    }

    private func processNewDayLogicIfNeeded() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        if todayString != lastSummaryDateString {
            print("ContentView: New day detected. Processing end-of-day tasks.")
            
            // 1. Evaluate points for the day that just ended (using tasks before any cleanup)
            let (points, _) = PointManager.evaluateDailyPoints(context: modelContext, tasks: allTodoItems)
            print("ContentView: Points evaluated for the previous day: \(points)")

            // 2. Delete tasks from previous days that are marked as done
            await deleteOldDoneTasks() // Renamed for clarity
            
            // 3. Check for tasks that MigrateTasksView would display
            let tasksThatNeedReview = allTodoItems.filter { todoItem in
                !todoItem.isDone || todoItem.subtasks.contains(where: { !$0.isDone })
            }

            if points > 0 {
                newDayEvaluationTriggeredLastDayView = true
                showLastDayView = true
            } else {
                newDayEvaluationTriggeredLastDayView = false
                if !tasksThatNeedReview.isEmpty {
                     print("ContentView: New day, no points, but tasks to review exist. Showing MigrateTasksView directly.")
                     showMigrateTasksView = true
                } else {
                    print("ContentView: New day, no points, and no tasks to migrate/review.")
                }
            }
            lastSummaryDateString = todayString
        } else {
            newDayEvaluationTriggeredLastDayView = false
        }
    }

    // Renamed and simplified to delete old tasks that are simply marked "isDone"
    private func deleteOldDoneTasks() async {
        print("ContentView: Attempting to delete old tasks marked as done...")
        let startOfToday = Calendar.current.startOfDay(for: Date())
        
        // Predicate for tasks due before today AND are marked as done
        let oldDoneTasksPredicate = #Predicate<TodoItem> {
            $0.isDone == true
        }
        let descriptor = FetchDescriptor<TodoItem>(predicate: oldDoneTasksPredicate)

        do {
            let tasksToDelete = try modelContext.fetch(descriptor)
            if tasksToDelete.isEmpty {
                print("ContentView: No old tasks marked as done found to delete.")
                return
            }

            print("ContentView: Found \(tasksToDelete.count) old tasks marked as done to delete.")
            for task in tasksToDelete {
                modelContext.delete(task)
            }
            try modelContext.save()
            print("ContentView: Successfully deleted old tasks marked as done.")
        } catch {
            print("ContentView: Error deleting old tasks marked as done: \(error.localizedDescription)")
        }
    }
}
