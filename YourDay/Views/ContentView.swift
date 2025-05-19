import SwiftUI
import GoogleSignIn
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TodoItem] // Assuming TodoItem is your SwiftData model for tasks

    @State private var showLastDayView = false
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""

    // ViewModel for authentication state
    @StateObject private var loginViewModel = LoginViewModel()

    var body: some View {
        Group {
            if loginViewModel.isAuthenticated {
                // Main app content when authenticated
                TabView {
                    GardenView() // Assuming GardenView is defined
                        .tabItem {
                            Label("Garden", systemImage: "leaf.fill")
                        }
                    Todoview() // Assuming Todoview is defined
                        .tabItem {
                            Label("Tasks", systemImage: "checkmark.circle")
                        }

                    AddNotesView() // Assuming AddNotesView is defined
                        .tabItem {
                            Label("Notes", systemImage: "square.and.pencil")
                        }

                    LastDayView(isModal: false) // Assuming LastDayView is defined
                        .tabItem {
                            Label("Summary", systemImage: "star.fill")
                        }

                }
                .task {
                    checkIfShouldEvaluatePoints()
                }
                .sheet(isPresented: $showLastDayView) {
                    NavigationView {
                        LastDayView(isModal: true)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") {
                                        showLastDayView = false
                                    }
                                }
                            }
                    }
                }
            } else {
                // LoginView when not authenticated
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            // Check authentication state when the ContentView first appears
            // The LoginViewModel's init also sets up a listener, but this ensures
            // the UI updates correctly on initial launch if state is already known.
            loginViewModel.checkAuthenticationState()
        }
        // Handle the Google Sign-In URL callback if using SwiftUI App lifecycle
        // This needs to be on a view that's part of the scene.
        // If your App struct is the entry point, you might put it there.
        // For simplicity, adding it here, but ensure it's effective in your app structure.
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
    }

    func checkIfShouldEvaluatePoints() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: today)

        if todayString != lastSummaryDateString {
            // Ensure PointManager and TodoItem are correctly defined and accessible
            // let (points, _) = PointManager.evaluateDailyPoints(context: context, tasks: allTasks)
            // print("🧮 Evaluated: \(points) points")
            //
            // if points > 0 {
            //     showLastDayView = true
            //     lastSummaryDateString = todayString
            // }
            print("Placeholder for PointManager.evaluateDailyPoints")
        }
    }
}




