// LastDayView.swift

import SwiftUI
import SwiftData

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium // e.g., "May 8, 2025"
    return formatter.string(from: date)
}

struct LastDayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: [SortDescriptor(\DailySummaryTask.date, order: .reverse)])
    private var allSummaries: [DailySummaryTask]

    // Query all TodoItems to calculate total tasks for the pie chart denominator
    @Query private var allTodoItems: [TodoItem] // Removed sort, count is what matters
    
    @State private var dateOffset: Int = 0
    @State private var animatedPoints: Double = 0
    @State private var showContinueButton: Bool = false
    
    var isModal: Bool

    private var uniqueSortedDates: [Date] {
        let uniqueDates = Set(allSummaries.map { Calendar.current.startOfDay(for: $0.date) })
        return Array(uniqueDates).sorted(by: >)
    }

    private var currentDisplayDate: Date? {
        guard !uniqueSortedDates.isEmpty, dateOffset < uniqueSortedDates.count, dateOffset >= 0 else {
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
            let subtasks = zip(summary.subtaskTitles, summary.subtaskPoints)
                .map { (title: $0.0, earned: $0.1) }
            return TaskPointResult(
                title: summary.taskTitle,
                date: summary.date,
                basePoints: summary.taskMaxPossiblePoints,
                subtaskPoints: subtasks,
                totalPoints: summary.totalPoints,
                mainTaskCompletedOnTargetDay: summary.mainTaskCompleted
            )
        }
    }

    private var totalPointsForDisplayDate: Double {
        breakdownForDisplayDate.reduce(0) { $0 + $1.totalPoints }
    }

    var body: some View {
        VStack(spacing: 16) {
            if let displayDate = currentDisplayDate {
                HStack {
                    Button {
                        if dateOffset < uniqueSortedDates.count - 1 {
                            dateOffset += 1
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
                    .id("animatedPointsText-\(dateOffset)")


                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(breakdownForDisplayDate) { taskResult in
                            if taskResult.totalPoints > 0 || taskResult.mainTaskCompletedOnTargetDay {
                                TaskSummaryRow(taskResult: taskResult)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 5)
                }

                Spacer()

                // Pass allTodoItems.count to the progress view if needed directly,
                // or let it query itself if that's cleaner.
                // For this change, TasksCompletionProgressView will use its own allTodoItems query.
                TasksCompletionProgressView(
                    displayDate: currentDisplayDate ?? Date(), // Still needed for numerator
                    allTodoItemsFromLastDayView: allTodoItems, // Pass all items for the denominator
                    summariesForDate: summariesForDisplayDate // For numerator
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
            let initialPoints = totalPointsForDisplayDate
            self.animatedPoints = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.0)) {
                    self.animatedPoints = initialPoints
                }
                updateContinueButtonVisibility(points: initialPoints, isInitialAppearance: true)
            }
        }
        .onChange(of: currentDisplayDate) { oldDate, newDate in
            guard oldDate != newDate else { return }

            let newTotalPoints = totalPointsForDisplayDate
            
            self.animatedPoints = 0
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
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
                if !isInitialAppearance || (isInitialAppearance && points > 0) {
                    self.showContinueButton = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + (isInitialAppearance ? 0.1 : 1.0) ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                        self.showContinueButton = true
                    }
                }
            } else {
                self.showContinueButton = true
            }
        }
    }
}

struct TaskSummaryRow: View {
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
                Text("+\(Int(taskResult.totalPoints)) / \(Int(taskResult.basePoints))")
                    .font(.caption)
                    .fontWeight(.semibold)
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

struct TasksCompletionProgressView: View {
    let displayDate: Date // Still needed to filter summaries for the numerator
    let allTodoItemsFromLastDayView: [TodoItem] // All tasks for the denominator
    let summariesForDate: [DailySummaryTask] // Summaries for the specific displayDate (for numerator)

    // Numerator: Number of main tasks completed on the displayDate
    private var completedTasksOnDisplayDate: Int {
        summariesForDate.filter { $0.mainTaskCompleted }.count
    }
        
    // Denominator: Total number of tasks in the entire list
    private var totalTasksInList: Int {
        allTodoItemsFromLastDayView.count
    }
        
    var progress: Double {
        guard totalTasksInList > 0 else { return 0 }
        // Calculate progress: (completed on displayDate) / (total tasks in list)
        return Double(completedTasksOnDisplayDate) / Double(totalTasksInList)
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
                // Updated text to reflect the new meaning
                Text(totalTasksInList > 0 ? "Of All Tasks" : "No Tasks")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(totalTasksInList > 0 ? "Done Today" : "In List")
                    .font(.caption)
                    .foregroundColor(.gray)

            }
            .multilineTextAlignment(.center) // Center the text if it wraps
        }
    }
}


// Helper Calendar extension
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
