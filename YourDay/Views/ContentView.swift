import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TodoItem]

    @State private var showLastDayView = false
    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""

    var body: some View {
        TabView {
            GardenView()
                .tabItem {
                    Label("Garden", systemImage: "leaf.fill")
                }
            Todoview()
                .tabItem {
                    Label("Tasks", systemImage: "checkmark.circle")
                }

            AddNotesView()
                .tabItem {
                    Label("Notes", systemImage: "square.and.pencil")
                }

            LastDayView(isModal: false)
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

#Preview {
    ContentView()
}
