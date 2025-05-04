//
//  ContentView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 4/27/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTasks: [TodoItem]

    @State private var showLastDayView = false
    @State private var lastDayData: (Double, [TaskPointResult]) = (0.0, [])

    @AppStorage("lastSummaryDate") private var lastSummaryDateString: String = ""

    var body: some View {
        TabView {
            Todoview()
                .tabItem {
                    Label("Tasks", systemImage: "checkmark.circle")
                }

            AddNotesView()
                .tabItem {
                    Label("Notes", systemImage: "square.and.pencil")
                }

            LastDayView(
                totalPoints: lastDayData.0,
                taskBreakdown: lastDayData.1,
                isModal: false
            )
            .tabItem {
                Label("Summary", systemImage: "star.fill")
            }
        }
        .onAppear {
            checkIfShouldShowLastDayView()
        }
        .sheet(isPresented: $showLastDayView) {
            NavigationView {
                LastDayView(
                    totalPoints: lastDayData.0,
                    taskBreakdown: lastDayData.1,
                    isModal: true
                )
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

    func checkIfShouldShowLastDayView() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        // Only show if we haven’t shown it today
        if todayString != lastSummaryDateString {
            let (points, breakdown) = PointManager.evaluateDailyPoints(context: context, tasks: allTasks)
            if points > 0 {
                self.lastDayData = (points, breakdown)
                self.showLastDayView = true
                self.lastSummaryDateString = todayString
            }
        }
    }
}

#Preview {
    ContentView()
}
