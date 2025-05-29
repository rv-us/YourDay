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

    @Query private var allTasks: [TodoItem]
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
                    checkIfShouldEvaluatePoints()
                }
                .sheet(isPresented: $showLastDayView, onDismiss: {
                    if newDayEvaluationTriggeredLastDayView {
                        newDayEvaluationTriggeredLastDayView = false
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
            print("Error saving context after clearing all local data: \(error.localizedDescription)")
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
            print("Error fetching local \(String(describing:modelType)) for deletion: \(error.localizedDescription)")
        }
    }

    func checkIfShouldEvaluatePoints() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        if todayString != lastSummaryDateString {
            let (points, _) = PointManager.evaluateDailyPoints(context: modelContext, tasks: allTasks)
            
            if points > 0 {
                newDayEvaluationTriggeredLastDayView = true
                showLastDayView = true
                lastSummaryDateString = todayString
            } else {
                lastSummaryDateString = todayString
                newDayEvaluationTriggeredLastDayView = false
            }
        } else {
            newDayEvaluationTriggeredLastDayView = false
        }
    }
}
