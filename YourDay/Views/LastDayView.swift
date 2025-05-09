// LastDayView.swift

import SwiftUI
import SwiftData

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

struct LastDayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: [SortDescriptor(\DailySummaryTask.date, order: .reverse)])
    private var allSummaries: [DailySummaryTask]

    @Query(sort: [SortDescriptor(\TodoItem.dueDate)])
    private var allTodoItems: [TodoItem]
    
    @State private var dateOffset: Int = 0
    @State private var animatedPoints: Double = 0
    @State private var showContinueButton: Bool = false
    
    var isModal: Bool

    private var uniqueSortedDates: [Date] {
        let uniqueDates = Set(allSummaries.map { Calendar.current.startOfDay(for: $0.date) })
        return Array(uniqueDates).sorted(by: >)
    }

    // This is the key computed property that will drive the animation changes
    private var currentDisplayDate: Date? {
        guard !uniqueSortedDates.isEmpty, dateOffset < uniqueSortedDates.count, dateOffset >= 0 else {
            // Default to yesterday if no summaries or offset is out of bounds.
            // This ensures the view has a date to display in its title, even if data is empty.
            return Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))
        }
        return uniqueSortedDates[dateOffset]
    }
    
    private var summariesForDisplayDate: [DailySummaryTask] {
        guard let displayDate = currentDisplayDate else { return [] }
        return allSummaries.filter { Calendar.current.isDate($0.date, inSameDayAs: displayDate) }
    }

    private var breakdownForDisplayDate: [TaskPointResult] {
        summariesForDisplayDate.map { summary in
            // Ensure this mapping includes the mainTaskCompletedOnTargetDay field if PointManager.TaskPointResult has it
            // For now, assuming the TaskPointResult structure used here matches previous definitions
            let subtasks = zip(summary.subtaskTitles, summary.subtaskPoints)
                .map { (title: $0.0, earned: $0.1) }
            return TaskPointResult(
                title: summary.taskTitle,
                date: summary.date,
                basePoints: PointManager.maxPointsPerDay * PointManager.maxPerTaskPercentage, // Example
                subtaskPoints: subtasks,
                totalPoints: summary.totalPoints,
                mainTaskCompletedOnTargetDay: summary.mainTaskCompleted // Mapped from DailySummaryTask
            )
        }
    }

    private var totalPointsForDisplayDate: Double {
        breakdownForDisplayDate.reduce(0) { $0 + $1.totalPoints }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let displayDate = currentDisplayDate { // Ensure displayDate is not nil
                HStack {
                    Button {
                        if dateOffset < uniqueSortedDates.count - 1 {
                            dateOffset += 1
                            // Animation will be handled by .onChange(of: currentDisplayDate)
                        }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                    }
                    .disabled(uniqueSortedDates.isEmpty || dateOffset >= uniqueSortedDates.count - 1)

                    Spacer()
                    Text("Summary for \(formatDate(displayDate))")
                        .font(isModal ? .title2 : .title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer()

                    Button {
                        if dateOffset > 0 {
                            dateOffset -= 1
                            // Animation will be handled by .onChange(of: currentDisplayDate)
                        }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                    }
                    .disabled(uniqueSortedDates.isEmpty || dateOffset <= 0)
                }
                .padding(.horizontal)
            } else {
                 Text("No Summary Data Available")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            
            if !summariesForDisplayDate.isEmpty {
                Text("+\(Int(animatedPoints)) Points!")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
                    // The .id helps if other external factors might change this specific text view
                    // but the main animation trigger is now .onChange(of: currentDisplayDate)
                    .id("animatedPointsText-\(dateOffset)")


                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(breakdownForDisplayDate) { taskResult in
                            if taskResult.totalPoints > 0 {
                                TaskSummaryRow(taskResult: taskResult)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                }

                Spacer()

                TasksCompletionProgressView(
                    displayDate: currentDisplayDate ?? Date(),
                    allTodoItems: allTodoItems,
                    summariesForDate: summariesForDisplayDate
                )
                .frame(width: 120, height: 120)
                .padding(.bottom, 10)
                 .id("progressView-\(dateOffset)")


            } else {
                Spacer()
                Text(uniqueSortedDates.isEmpty ? "No summary data found." : "No tasks recorded for this day.")
                    .font(.title3)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }

            if isModal {
                Button(action: {
                    withAnimation { dismiss() }
                }) {
                    Text(totalPointsForDisplayDate > 0 && !summariesForDisplayDate.isEmpty ? "Awesome!" : "Close")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .opacity(showContinueButton || summariesForDisplayDate.isEmpty ? 1 : 0)
                .animation(.easeInOut.delay(0.2), value: showContinueButton)
            }
        }
        .padding(.vertical)
        .onAppear {
            // Initial animation setup when the view first appears
            let initialPoints = totalPointsForDisplayDate
            self.animatedPoints = 0 // Start from 0 for the animation
            // Slight delay to ensure the view is fully laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.animatedPoints = initialPoints
                }
                updateContinueButtonVisibility(points: initialPoints, isInitialAppearance: true)
            }
        }
        .onChange(of: currentDisplayDate) { oldDate, newDate in
            // This will trigger whenever currentDisplayDate changes,
            // which happens when dateOffset is modified.
            guard oldDate != newDate else { return } // Only proceed if the date actually changed

            let newTotalPoints = totalPointsForDisplayDate
            
            // Reset animatedPoints to 0 without animation
            self.animatedPoints = 0
            
            // Schedule animation to the new value with a slight delay
            // This delay helps SwiftUI register the reset to 0 before starting the new animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // A very short delay
                withAnimation(.easeOut(duration: 1.0)) {
                    self.animatedPoints = newTotalPoints
                }
                updateContinueButtonVisibility(points: newTotalPoints)
            }
        }
    }
    
    private func updateContinueButtonVisibility(points: Double, isInitialAppearance: Bool = false) {
        if isModal {
            if points > 0 {
                // If it's not the initial appearance, or if it is and we want the button animated
                // we hide it first, then show it after the points animation.
                if !isInitialAppearance || (isInitialAppearance && points > 0) { // Avoid hiding if initial and 0 points
                    self.showContinueButton = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + (isInitialAppearance ? 0.1 : 1.0) ) { // delay matches points animation
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        self.showContinueButton = true
                    }
                }
            } else { // No points
                self.showContinueButton = true // Show "Close" button immediately
            }
        }
    }
}

// Make sure TaskSummaryRow and TasksCompletionProgressView are defined as in the previous step.
// (Assuming TaskPointResult and other dependencies are correctly defined from before)

struct TaskSummaryRow: View { // Copied from previous correct version
    let taskResult: TaskPointResult
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: taskResult.mainTaskCompletedOnTargetDay ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(taskResult.mainTaskCompletedOnTargetDay ? .green : .orange)
                Text(taskResult.title)
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
                Text("+\(Int(taskResult.totalPoints))")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            if !taskResult.subtaskPoints.isEmpty {
                ForEach(taskResult.subtaskPoints.filter { $0.earned > 0 }, id: \.title) { sub in
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(sub.title)
                            .font(.subheadline)
                        Spacer()
                        Text("+\(Int(sub.earned))")
                           .font(.subheadline)
                           .foregroundColor(.blue.opacity(0.8))
                    }
                    .padding(.leading, 25)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

struct TasksCompletionProgressView: View { // Copied from previous correct version
    let displayDate: Date
    let allTodoItems: [TodoItem]
    let summariesForDate: [DailySummaryTask]

    private var activeTasksForDay: Int {
        let calendar = Calendar.current
        let startOfDisplayDate = calendar.startOfDay(for: displayDate)

        return allTodoItems.filter { item in
            let dueByDisplayDate = calendar.startOfDay(for: item.dueDate) <= startOfDisplayDate
            
            let notCompletedBeforeDisplayDate: Bool
            if let completedAt = item.completedAt {
                notCompletedBeforeDisplayDate = calendar.startOfDay(for: completedAt) >= startOfDisplayDate
            } else {
                notCompletedBeforeDisplayDate = true
            }
            
            return dueByDisplayDate && notCompletedBeforeDisplayDate
        }.count
    }

    private var trulyCompletedActiveTasks: Int {
        summariesForDate.filter { $0.mainTaskCompleted }.count
    }
        
    var progress: Double {
        guard activeTasksForDay > 0 else { return 0 }
        return Double(trulyCompletedActiveTasks) / Double(activeTasksForDay)
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 10)
            
            Circle()
                .trim(from: 0.0, to: progress)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.interpolatingSpring(stiffness: 100, damping: 10), value: progress)
            
            VStack {
                Text("\(Int(progress * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
                Text(activeTasksForDay > 0 ? "Tasks Done" : "No Tasks Due")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}


// Helper Calendar extension (if not globally available)
extension Calendar {
    func isDate(_ date1: Date, equalToOrBefore date2: Date) -> Bool {
        return compare(date1, to: date2, toGranularity: .day) != .orderedDescending
    }

    func isDate(_ date1: Date, equalToOrLaterThan date2: Date) -> Bool {
        return compare(date1, to: date2, toGranularity: .day) != .orderedAscending
    }
    
    func isDate(_ date1: Date, onDayBefore date2: Date) -> Bool {
        guard let dayBefore = self.date(byAdding: .day, value: -1, to: date2) else { return false }
        return isDate(date1, inSameDayAs: dayBefore)
    }
}
