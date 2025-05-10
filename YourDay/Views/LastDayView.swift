// LastDayView.swift

import SwiftUI
import SwiftData

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

// Struct to hold all necessary XP info for the progress bar
struct XPDisplayInfo {
    let levelBefore: Int
    let xpBefore: Double
    let levelAfter: Int
    let xpAfter: Double
    let xpEarnedToday: Double
    let xpToNextLevel: Double // XP needed for the level the player is currently on (levelAfter)
    let didLevelUp: Bool

    init(from summary: DailySummaryTask?) {
        if let summary = summary {
            self.levelBefore = summary.levelBeforeXP
            self.xpBefore = summary.xpBeforeXP
            self.levelAfter = summary.levelAfterXP
            self.xpAfter = summary.xpAfterXP
            self.xpEarnedToday = summary.xpEarnedOnDate
            self.xpToNextLevel = summary.xpToNextLevelAfterXP
            self.didLevelUp = summary.levelAfterXP > summary.levelBeforeXP
        } else { // Default/fallback if no summary
            self.levelBefore = 1
            self.xpBefore = 0
            self.levelAfter = 1
            self.xpAfter = 0
            self.xpEarnedToday = 0
            self.xpToNextLevel = PlayerStats.xpRequiredForNextLevel(currentLevel: 1)
            self.didLevelUp = false
        }
    }
    
    // Initializer for when there's no summary, using current PlayerStats
    init(currentStats: PlayerStats?) {
        if let stats = currentStats {
            self.levelBefore = stats.playerLevel // Assuming no XP gain to show for "current"
            self.xpBefore = stats.currentXP
            self.levelAfter = stats.playerLevel
            self.xpAfter = stats.currentXP
            self.xpEarnedToday = 0 // No "today's gain" to animate
            self.xpToNextLevel = PlayerStats.xpRequiredForNextLevel(currentLevel: stats.playerLevel)
            self.didLevelUp = false
        } else {
            self.levelBefore = 1
            self.xpBefore = 0
            self.levelAfter = 1
            self.xpAfter = 0
            self.xpEarnedToday = 0
            self.xpToNextLevel = PlayerStats.xpRequiredForNextLevel(currentLevel: 1)
            self.didLevelUp = false
        }
    }
}


struct LastDayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: [SortDescriptor(\DailySummaryTask.date, order: .reverse)])
    private var allSummaries: [DailySummaryTask]

    @Query private var playerStatsList: [PlayerStats] // For fallback XP display

    @State private var dateOffset: Int = 0
    @State private var animatedPointsTotal: Double = 0 // Renamed to avoid conflict
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
                title: summary.taskTitle, date: summary.date,
                basePoints: summary.taskMaxPossiblePoints, subtaskPoints: subtasks,
                totalPoints: summary.totalPoints, mainTaskCompletedOnTargetDay: summary.mainTaskCompleted
            )
        }
    }

    private var totalPointsForDisplayDate: Double {
        // Sum totalPoints from the first summary for the date, as xpEarnedOnDate has the total for the day
        summariesForDisplayDate.first?.xpEarnedOnDate ?? 0.0
    }

    private var completionSnapshotForPieChart: (completed: Int, total: Int)? {
        guard let firstSummaryForDate = summariesForDisplayDate.first else { return nil }
        return (completed: firstSummaryForDate.dayCompletionSnapshot_CompletedCount,
                total: firstSummaryForDate.dayCompletionSnapshot_TotalTasksCount)
    }
    
    // XP Info for the current display date
    private var xpInfoForDisplayDate: XPDisplayInfo {
        if let summary = summariesForDisplayDate.first {
            return XPDisplayInfo(from: summary)
        } else {
            // Fallback for days with no summary (e.g., future dates or if summary failed)
            // Or if it's the "current day" view being presented immediately without a summary yet.
            // This might need adjustment based on when LastDayView is shown.
            // If always shown for "yesterday", a summary should exist.
            return XPDisplayInfo(currentStats: playerStatsList.first)
        }
    }


    var body: some View {
        VStack(spacing: 16) {
            if let displayDate = currentDisplayDate {
                HStack { /* Navigation buttons */
                    Button { if dateOffset < uniqueSortedDates.count - 1 { dateOffset += 1 }
                    } label: { Image(systemName: "chevron.left.circle.fill").font(.title2) }
                    .disabled(uniqueSortedDates.isEmpty || dateOffset >= uniqueSortedDates.count - 1)
                    Spacer()
                    Text("Summary for \(formatDate(displayDate))")
                        .font(isModal ? .title2 : .title).fontWeight(.bold).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    Button { if dateOffset > 0 { dateOffset -= 1 }
                    } label: { Image(systemName: "chevron.right.circle.fill").font(.title2) }
                    .disabled(uniqueSortedDates.isEmpty || dateOffset <= 0)
                }.padding(.horizontal)
            } else {
                 Text("No Summary Data Available").font(.title2).foregroundColor(.gray)
            }
            
            let currentXPInfo = xpInfoForDisplayDate

            // Main content area
            if !summariesForDisplayDate.isEmpty || (isModal && currentXPInfo.xpEarnedToday == 0 && uniqueSortedDates.isEmpty) {
                Text("+\(Int(animatedPointsTotal)) Points!")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
                    .id("animatedPointsText-\(dateOffset)")
                
                // XP Progress View
                XPProgressView(
                    levelBefore: currentXPInfo.levelBefore,
                    xpBefore: currentXPInfo.xpBefore,
                    levelAfter: currentXPInfo.levelAfter,
                    xpAfter: currentXPInfo.xpAfter,
                    xpGainedThisSession: currentXPInfo.xpEarnedToday, // XP gained on the summary date
                    xpForNextLevel: currentXPInfo.xpToNextLevel, // XP needed for levelAfter
                    didLevelUp: currentXPInfo.didLevelUp
                )
                .padding(.horizontal)
                .id("xpProgressView-\(dateOffset)")


                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(breakdownForDisplayDate) { taskResult in
                            if taskResult.totalPoints > 0 || taskResult.mainTaskCompletedOnTargetDay {
                                TaskSummaryRow(taskResult: taskResult)
                            }
                        }
                    }
                    .padding(.horizontal).padding(.top, 5)
                }

                Spacer()

                if let snapshot = completionSnapshotForPieChart, snapshot.total > 0 {
                    TasksCompletionProgressView(completedTasks: snapshot.completed, totalTasks: snapshot.total)
                        .frame(width: 120, height: 120).padding(.bottom, 10).id("taskProgressView-\(dateOffset)")
                }


            } else {
                Spacer()
                Text(uniqueSortedDates.isEmpty ? "No summary data found." : "No task activity recorded for this day.")
                    .font(.title3).foregroundColor(.gray).multilineTextAlignment(.center).padding()
                Spacer()
            }

            if isModal { /* Dismiss button */
                Button(action: { withAnimation { dismiss() } }) {
                    Text(totalPointsForDisplayDate > 0 && !summariesForDisplayDate.isEmpty ? "Awesome!" : "Close")
                        .font(.headline).padding().frame(maxWidth: .infinity)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(12).padding(.horizontal)
                }
                .opacity(showContinueButton || summariesForDisplayDate.isEmpty ? 1 : 0)
                .animation(.easeInOut.delay(0.2), value: showContinueButton)
            }
        }
        .padding(.vertical)
        .onAppear {
            let initialPoints = totalPointsForDisplayDate
            self.animatedPointsTotal = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.0)) { self.animatedPointsTotal = initialPoints }
                updateContinueButtonVisibility(points: initialPoints, isInitialAppearance: true)
            }
        }
        .onChange(of: currentDisplayDate) { oldDate, newDate in
            guard oldDate != newDate else { return }
            let newTotalPoints = totalPointsForDisplayDate
            self.animatedPointsTotal = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 1.0)) { self.animatedPointsTotal = newTotalPoints }
                updateContinueButtonVisibility(points: newTotalPoints)
            }
        }
    }
    
    private func updateContinueButtonVisibility(points: Double, isInitialAppearance: Bool = false) {
        if isModal {
            if points > 0 && !summariesForDisplayDate.isEmpty {
                if !isInitialAppearance || (isInitialAppearance && points > 0) { self.showContinueButton = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + (isInitialAppearance ? 0.1 : 1.0) ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { self.showContinueButton = true }
                }
            } else { self.showContinueButton = true }
        }
    }
}

struct TaskSummaryRow: View { /* Remains the same */
    let taskResult: TaskPointResult
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: taskResult.mainTaskCompletedOnTargetDay ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(taskResult.mainTaskCompletedOnTargetDay ? .green : .orange)
                Text(taskResult.title).font(.headline).fontWeight(.medium)
                Spacer()
                Text("+\(Int(taskResult.totalPoints)) / \(Int(taskResult.basePoints))")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.blue)
            }
            if !taskResult.subtaskPoints.isEmpty {
                ForEach(taskResult.subtaskPoints.filter { $0.earned > 0 }, id: \.title) { sub in
                    HStack {
                        Image(systemName: "arrow.turn.down.right").font(.caption).foregroundColor(.gray)
                        Text(sub.title).font(.subheadline)
                        Spacer()
                        Text("+\(Int(sub.earned))").font(.subheadline).foregroundColor(.blue.opacity(0.8))
                    }.padding(.leading, 25)
                }
            }
        }.padding().background(Color(UIColor.secondarySystemGroupedBackground)).cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
    }
}

struct TasksCompletionProgressView: View { /* Remains the same */
    let completedTasks: Int
    let totalTasks: Int
    var progress: Double {
        guard totalTasks > 0 else { return 0 }
        let validCompletedTasks = min(completedTasks, totalTasks)
        return Double(validCompletedTasks) / Double(totalTasks)
    }
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.2), lineWidth: 10)
            Circle().trim(from: 0.0, to: progress)
                .stroke(Color.purple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.interpolatingSpring(stiffness: 100, damping: 10), value: progress)
            VStack {
                Text("\(Int(progress * 100))%").font(.title3).fontWeight(.bold)
                Text(totalTasks > 0 ? "Day's Tasks" : "No Tasks").font(.caption).foregroundColor(.gray)
                Text(totalTasks > 0 ? "Completed" : "Recorded").font(.caption).foregroundColor(.gray)
            }.multilineTextAlignment(.center)
        }
    }
}

// New XP Progress View
struct XPProgressView: View {
    let levelBefore: Int
    let xpBefore: Double
    let levelAfter: Int
    let xpAfter: Double
    let xpGainedThisSession: Double
    let xpForNextLevel: Double // XP needed for the level player is at (levelAfter)
    let didLevelUp: Bool

    @State private var animatedXP: Double = 0
    @State private var displayedLevel: Int
    @State private var displayedXPForNextLevel: Double
    @State private var showLevelUpMessage: Bool = false

    init(levelBefore: Int, xpBefore: Double, levelAfter: Int, xpAfter: Double, xpGainedThisSession: Double, xpForNextLevel: Double, didLevelUp: Bool) {
        self.levelBefore = levelBefore
        self.xpBefore = xpBefore
        self.levelAfter = levelAfter
        self.xpAfter = xpAfter
        self.xpGainedThisSession = xpGainedThisSession
        self.xpForNextLevel = xpForNextLevel
        self.didLevelUp = didLevelUp
        
        // Initial state for animation
        _displayedLevel = State(initialValue: levelBefore)
        _animatedXP = State(initialValue: xpBefore)
        _displayedXPForNextLevel = State(initialValue: PlayerStats.xpRequiredForNextLevel(currentLevel: levelBefore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level: \(displayedLevel)")
                    .font(.headline)
                    .animation(nil, value: displayedLevel) // No animation for level text itself during XP bar fill
                Spacer()
                if showLevelUpMessage {
                    Text("LEVEL UP!")
                        .font(.headline)
                        .foregroundColor(.yellow)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            ProgressView(value: animatedXP, total: displayedXPForNextLevel) {
                // Label for the progress bar (optional)
            } currentValueLabel: {
                Text("\(Int(animatedXP)) / \(Int(displayedXPForNextLevel)) XP")
                    .font(.caption)
            }
            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
            .animation(.easeInOut(duration: 1.0), value: animatedXP) // Animate the bar filling
            .onAppear {
                // Start the animation sequence
                // 1. Set initial state (already done in init)
                // 2. Animate XP gain
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { // Slight delay for view to appear
                    if didLevelUp {
                        // Animate to fill the bar for the level *before* level up
                        let xpForLevelBefore = PlayerStats.xpRequiredForNextLevel(currentLevel: levelBefore)
                        animatedXP = xpForLevelBefore // Fill up current level's bar

                        // After that animation, handle level up
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Duration of bar fill
                            withAnimation {
                                showLevelUpMessage = true
                                displayedLevel = levelAfter // Update level text
                            }
                            // Reset bar for new level and animate remaining XP
                            animatedXP = 0 // Reset for new level bar
                            displayedXPForNextLevel = xpForNextLevel // Update total for new level
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // After level up message
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    animatedXP = xpAfter // Animate to final XP in new level
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                     withAnimation { showLevelUpMessage = false }
                                }
                            }
                        }
                    } else {
                        // No level up, just animate the XP gain
                         displayedLevel = levelAfter // Ensure level is current
                         displayedXPForNextLevel = xpForNextLevel // Ensure total is current
                         animatedXP = xpAfter
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}




// Helper Calendar extension (remains the same)
extension Calendar {
    func isDate(_ date1: Date, equalToOrBefore date2: Date) -> Bool { return compare(date1, to: date2, toGranularity: .day) != .orderedDescending }
    func isDate(_ date1: Date, equalToOrLaterThan date2: Date) -> Bool { return compare(date1, to: date2, toGranularity: .day) != .orderedAscending }
    func isDate(_ date1: Date, onDayBefore date2: Date) -> Bool {
        guard let dayBefore = self.date(byAdding: .day, value: -1, to: date2) else { return false }
        return isDate(date1, inSameDayAs: dayBefore)
    }
}
