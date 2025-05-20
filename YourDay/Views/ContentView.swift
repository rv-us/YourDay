import SwiftUI
import SwiftData
import GoogleSignIn // For .onOpenURL

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.modelContext) private var context
    // Query for local PlayerStats.
    @Query(sort: \PlayerStats.playerLevel) private var localPlayerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? {
        // This fetches the first PlayerStats object. If you have a multi-user local setup
        // or need to ensure it's the *correct* user's stats, this might need a predicate
        // based on a userID stored in PlayerStats @Model, if you implement that.
        // For a single-user app after login, this is usually sufficient.
        localPlayerStatsList.first
    }

    @StateObject private var loginViewModel = LoginViewModel() // From login_view_model_swift_final_sync

    // UI States
    @State private var showSignOutErrorAlert = false
    @State private var signOutErrorMessage = ""
    @State private var showLastDayView = false // From original ContentView
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = "" // From original

    // Other ViewModels / Data (from original ContentView)
    @Query private var allTasks: [TodoItem] // For checkIfShouldEvaluatePoints
    @StateObject private var todoViewModel = TodoViewModel() // For NotificationSettingsView

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated {
                TabView {
                    GardenView()
                        .tabItem { Label("Garden", systemImage: "leaf.fill") }
                        .environmentObject(loginViewModel)
                        // Example of how GardenView might sync data:
                        // func updateAndSyncPlayerStats() {
                        //     if let stats = currentPlayerStats {
                        //         stats.totalPoints += 10 // Make local change
                        //         try? modelContext.save() // Save local change
                        //         loginViewModel.syncLocalPlayerStatsToFirestore(playerStatsModel: stats)
                        //     }
                        // }

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
                        onSignOutRequested: { // Pass the sign-out handler
                            requestSignOut()
                        }
                    )
                         .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                }
                .task {
                    checkIfShouldEvaluatePoints()
                }
                .sheet(isPresented: $showLastDayView) {
                    NavigationView {
                        LastDayView(isModal: true)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { showLastDayView = false }
                                }
                            }
                    }
                }
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            print("ContentView: .onAppear. Current auth state from ViewModel: \(loginViewModel.isAuthenticated)")
            // LoginViewModel's init calls its own checkAuthenticationState.
            // If already authenticated when ContentView appears, trigger session handling.
            if loginViewModel.isAuthenticated {
                // It's NOT a "fresh login event" from Google Sign-In button at this point.
                // LoginViewModel's isProcessingFreshLogin should be false.
                print("ContentView: .onAppear - User is authenticated. Calling handleUserSession.")
                loginViewModel.handleUserSession(localPlayerStats: currentPlayerStats, modelContext: modelContext)
            } else {
                print("ContentView: .onAppear - User is NOT authenticated.")
            }
        }
        .onChange(of: loginViewModel.isAuthenticated) { _, userIsAuthenticated in
            print("ContentView: loginViewModel.isAuthenticated changed to \(userIsAuthenticated).")
            if userIsAuthenticated {
                // This block is hit AFTER a successful sign-in process (where isProcessingFreshLogin would be true in ViewModel)
                // OR if auth state changes for other reasons while app is running.
                // Fetch the most current local stats before calling handleUserSession.
                let currentLocalStatsOnChange = localPlayerStatsList.first // Re-fetch, though currentPlayerStats computed property might suffice
                print("ContentView: .onChange(isAuthenticated) - User became authenticated. Calling handleUserSession. isProcessingFreshLogin: \(loginViewModel.isProcessingFreshLogin)")
                loginViewModel.handleUserSession(localPlayerStats: currentLocalStatsOnChange, modelContext: modelContext)
            } else {
                // User logged out
                print("ContentView: .onChange(isAuthenticated) - User logged out. Clearing local SwiftData.")
                clearAllLocalUserDataOnLogout() // Ensure this is comprehensive
            }
        }
        .onOpenURL { url in // Best placed in @main App struct for global handling
            print("ContentView: Handling URL for Google Sign-In: \(url)")
            GIDSignIn.sharedInstance.handle(url)
        }
        .alert("Sign Out Issue", isPresented: $showSignOutErrorAlert) { // Changed title for clarity
            Button("OK", role: .cancel) { }
        } message: {
            Text(signOutErrorMessage)
        }
    }

    /// Initiates the sign-out process, including pre-syncing data.
    private func requestSignOut() {
        print("ContentView: Sign out requested by UI.")
        // currentPlayerStats will be the latest from the @Query
        loginViewModel.attemptSignOut(currentPlayerStatsToSync: currentPlayerStats) { didSignOut, errorMessageText in
            if !didSignOut {
                self.signOutErrorMessage = errorMessageText ?? "An unknown error occurred during sign out."
                self.showSignOutErrorAlert = true
                print("ContentView: Sign out attempt failed or was blocked: \(self.signOutErrorMessage)")
            } else {
                // Sign out was successful from Firebase/Google perspective.
                // loginViewModel.isAuthenticated will become false, triggering .onChange,
                // which then calls clearAllLocalUserDataOnLogout().
                print("ContentView: Sign out process reported successful by ViewModel. Local data will be cleared by .onChange.")
            }
        }
    }

    /// Clears all user-specific SwiftData when the user logs out.
    private func clearAllLocalUserDataOnLogout() {
        print("ContentView: Clearing all user-specific local SwiftData due to logout.")
        
        deleteSwiftData(modelType: PlayerStats.self, modelName: "PlayerStats")
        deleteSwiftData(modelType: TodoItem.self, modelName: "TodoItems") // Assuming TodoItem is your @Model
        deleteSwiftData(modelType: NoteItem.self, modelName: "NoteItems") // Assuming NoteItem is your @Model
        deleteSwiftData(modelType: DailySummaryTask.self, modelName: "DailySummaryTasks") // Assuming DailySummaryTask is your @Model
        // Add other user-specific models here if necessary

        do {
            try modelContext.save()
            print("ContentView: Successfully saved context after clearing all local data.")
        } catch {
            print("ContentView: Error saving context after clearing all local data: \(error.localizedDescription)")
            // Potentially show an error to the user if this fails, though less critical than login/sync errors.
        }
    }

    /// Generic helper to delete all instances of a given SwiftData Model type.
    private func deleteSwiftData<T: PersistentModel>(modelType: T.Type, modelName: String) {
        let descriptor = FetchDescriptor<T>()
        do {
            let fetchedItems = try modelContext.fetch(descriptor)
            if fetchedItems.isEmpty {
                print("ContentView: No local \(modelName) found to delete.")
                return
            }
            var count = 0
            for item in fetchedItems {
                modelContext.delete(item)
                count += 1
            }
            print("ContentView: Deleted \(count) local \(modelName).")
        } catch {
            print("ContentView: Error fetching local \(modelName) for deletion: \(error.localizedDescription)")
        }
    }

    func checkIfShouldEvaluatePoints() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        // Only evaluate if we haven't shown it today
        if todayString != lastSummaryDateString {
            let (points, _) = PointManager.evaluateDailyPoints(context: context, tasks: allTasks)
            print("🧮 Evaluated: \(points) points")

            if points > 0 {
                showLastDayView = true
                lastSummaryDateString = todayString
            }
        }
    }
}
