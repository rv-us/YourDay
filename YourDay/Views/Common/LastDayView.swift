import SwiftUI
import SwiftData

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter.string(from: date)
}

struct XPDisplayInfo {
    let levelBefore: Int
    let xpBefore: Double
    let levelAfter: Int
    let xpAfter: Double
    let xpEarnedToday: Double
    let xpToNextLevel: Double
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
    
    init(currentStats: PlayerStats?) {
        if let stats = currentStats {
            self.levelBefore = stats.playerLevel
            self.xpBefore = stats.currentXP
            self.levelAfter = stats.playerLevel
            self.xpAfter = stats.currentXP
            self.xpEarnedToday = 0
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

    @Query private var playerStatsList: [PlayerStats]

    @State private var dateOffset: Int = 1
    @State private var animatedPointsTotal: Double = 0
    @State private var showContinueButton: Bool = false
    
    var isModal: Bool

    private static let numberOfNavigableDays = 30

    /// Last N days (index 0 = today, 1 = yesterday, …) so we can always switch between days.
    private var navigableDates: [Date] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return (0..<Self.numberOfNavigableDays).compactMap { calendar.date(byAdding: .day, value: -$0, to: startOfToday) }
    }

    private var currentDisplayDate: Date? {
        guard dateOffset >= 0, dateOffset < navigableDates.count else {
            return Calendar.current.startOfDay(for: Date())
        }
        return navigableDates[dateOffset]
    }
    
    private var summariesForDisplayDate: [DailySummaryTask] {
        guard let displayDate = currentDisplayDate else { return [] }
        return allSummaries.filter { Calendar.current.isDate($0.date, inSameDayAs: displayDate) }
    }

    private var breakdownForDisplayDate: [TaskPointResult] {
        summariesForDisplayDate.map { taskPointResult(from: $0) }
    }

    private func taskPointResult(from summary: DailySummaryTask) -> TaskPointResult {
        let subtasks = zip(summary.subtaskTitles, summary.subtaskPoints)
            .map { (title: $0.0, earned: $0.1) }
        return TaskPointResult(
            title: summary.taskTitle, date: summary.date,
            basePoints: summary.taskMaxPossiblePoints, subtaskPoints: subtasks,
            totalPoints: summary.totalPoints, mainTaskCompletedOnTargetDay: summary.mainTaskCompleted,
            origin: summary.origin,
            localTaskId: "",
            sharedTaskId: nil
        )
    }

    private var totalPointsForDisplayDate: Double {
        summariesForDisplayDate.first?.xpEarnedOnDate ?? 0.0
    }

    private var completionSnapshotForPieChart: (completed: Int, total: Int)? {
        guard let firstSummaryForDate = summariesForDisplayDate.first else { return nil }
        return (completed: firstSummaryForDate.dayCompletionSnapshot_CompletedCount,
                total: firstSummaryForDate.dayCompletionSnapshot_TotalTasksCount)
    }
    
    private var xpInfoForDisplayDate: XPDisplayInfo {
        if let summary = summariesForDisplayDate.first {
            return XPDisplayInfo(from: summary)
        } else {
            return XPDisplayInfo(currentStats: playerStatsList.first)
        }
    }

    /// Hero title: "Today", "Yesterday", or "Summary for [date]"
    private var heroTitle: String {
        guard let displayDate = currentDisplayDate else { return "Summary" }
        if dateOffset == 0 { return "Today" }
        if dateOffset == 1 { return "Yesterday" }
        return "Summary for \(formatDate(displayDate))"
    }

    /// Short date subtitle (e.g. "Mon, Dec 23")
    private var dateSubtitle: String? {
        guard let displayDate = currentDisplayDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: displayDate)
    }

    /// Total points for the day before current display date (for comparison)
    private var totalPointsPreviousDay: Double? {
        guard dateOffset + 1 < navigableDates.count else { return nil }
        let prevDate = navigableDates[dateOffset + 1]
        let prevSummaries = allSummaries.filter { Calendar.current.isDate($0.date, inSameDayAs: prevDate) }
        return prevSummaries.first?.xpEarnedOnDate
    }

    /// Top task by points for insights
    private var topTaskByPoints: TaskPointResult? {
        breakdownForDisplayDate
            .filter { $0.totalPoints > 0 || $0.mainTaskCompletedOnTargetDay }
            .max(by: { $0.totalPoints < $1.totalPoints })
    }

    private var hasContent: Bool {
        !summariesForDisplayDate.isEmpty || (isModal && dateOffset == 0)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Date navigation header
            if currentDisplayDate != nil {
                HStack {
                    Button { if dateOffset < navigableDates.count - 1 { dateOffset += 1 }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title2)
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .disabled(dateOffset >= navigableDates.count - 1)
                    Spacer()
                    VStack(spacing: 2) {
                        Text(heroTitle)
                            .font(isModal ? .title2 : .title)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(dynamicTextColor)
                        if let subtitle = dateSubtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                    Spacer()
                    Button { if dateOffset > 0 { dateOffset -= 1 }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title2)
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .disabled(dateOffset <= 0)
                }
                .padding(.horizontal)
            } else {
                Text("No Summary Data Available")
                    .font(.title2)
                    .foregroundColor(dynamicSecondaryTextColor)
            }

            if hasContent {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Points card
                        lastDayCard {
                            VStack(spacing: 4) {
                                Text("+\(Int(animatedPointsTotal))")
                                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                                    .foregroundColor(dynamicSecondaryColor)
                                    .id("animatedPointsText-\(dateOffset)")
                                Text("points earned")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        // XP / Level card
                        lastDayCard {
                            XPProgressView(
                                levelBefore: xpInfoForDisplayDate.levelBefore,
                                xpBefore: xpInfoForDisplayDate.xpBefore,
                                levelAfter: xpInfoForDisplayDate.levelAfter,
                                xpAfter: xpInfoForDisplayDate.xpAfter,
                                xpGainedThisSession: xpInfoForDisplayDate.xpEarnedToday,
                                xpForNextLevel: xpInfoForDisplayDate.xpToNextLevel,
                                didLevelUp: xpInfoForDisplayDate.didLevelUp
                            )
                            .id("xpProgressView-\(dateOffset)")
                        }

                        // Insights card
                        if let snapshot = completionSnapshotForPieChart, snapshot.total > 0 {
                            lastDayCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("At a glance")
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)
                                    VStack(alignment: .leading, spacing: 6) {
                                        insightRow(icon: "checkmark.circle.fill", text: "You completed \(snapshot.completed) of \(snapshot.total) tasks.")
                                        insightRow(icon: "star.fill", text: "You earned \(Int(totalPointsForDisplayDate)) points.")
                                        if let top = topTaskByPoints, !top.title.isEmpty {
                                            insightRow(icon: "trophy.fill", text: "Most points from: \(top.title)")
                                        }
                                        if let prev = totalPointsPreviousDay, dateOffset <= 1 {
                                            let diff = totalPointsForDisplayDate - prev
                                            if diff > 0 {
                                                insightRow(icon: "arrow.up.right", text: "\(Int(diff)) more points than the day before.")
                                            } else if diff < 0 {
                                                insightRow(icon: "arrow.down.right", text: "\(Int(-diff)) fewer points than the day before.")
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        // Task breakdown card
                        if !breakdownForDisplayDate.filter({ $0.totalPoints > 0 || $0.mainTaskCompletedOnTargetDay }).isEmpty {
                            lastDayCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Task breakdown")
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)
                                    ForEach(summariesForDisplayDate, id: \.id) { summary in
                                        let taskResult = taskPointResult(from: summary)
                                        if taskResult.totalPoints > 0 || taskResult.mainTaskCompletedOnTargetDay {
                                            TaskSummaryRow(
                                                taskResult: taskResult,
                                                hasProofFeedBreakdown: summary.hasProofFeedBreakdown,
                                                proofFeedCheckVotes: summary.proofFeedCheckVotes,
                                                proofFeedXVotes: summary.proofFeedXVotes,
                                                proofFeedPointsMultiplierApplied: summary.proofFeedPointsMultiplierApplied,
                                                proofFeedBonusExtraPoints: summary.proofFeedBonusExtraPoints
                                            )
                                        }
                                    }
                                }
                            }
                        }

                        // Completion circle card
                        if let snapshot = completionSnapshotForPieChart, snapshot.total > 0 {
                            lastDayCard {
                                VStack(spacing: 8) {
                                    TasksCompletionProgressView(completedTasks: snapshot.completed, totalTasks: snapshot.total)
                                        .frame(width: 120, height: 120)
                                        .id("taskProgressView-\(dateOffset)")
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 48))
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.6))
                    Text("No task activity recorded for this day.")
                        .font(.title3)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Text("Complete tasks to see your summary here.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            }

            if isModal {
                Button(action: { withAnimation { dismiss() } }) {
                    Text(totalPointsForDisplayDate > 0 && !summariesForDisplayDate.isEmpty ? "Awesome!" : "Close")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            totalPointsForDisplayDate > 0 && !summariesForDisplayDate.isEmpty ? dynamicSecondaryColor : dynamicSecondaryTextColor
                        )
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .opacity(showContinueButton || summariesForDisplayDate.isEmpty ? 1 : 0)
                .animation(.easeInOut.delay(0.2), value: showContinueButton)
            }
        }
        .padding(.vertical, 16)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .onAppear {
            let initialPoints = totalPointsForDisplayDate
            self.animatedPointsTotal = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.0)) { self.animatedPointsTotal = initialPoints }
                updateContinueButtonVisibility(points: initialPoints, isInitialAppearance: true)
            }
        }
        .onChange(of: dateOffset) { _, _ in
            let newTotalPoints = totalPointsForDisplayDate
            self.animatedPointsTotal = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.5)) { self.animatedPointsTotal = newTotalPoints }
                updateContinueButtonVisibility(points: newTotalPoints)
            }
        }
    }
    
    private func updateContinueButtonVisibility(points: Double, isInitialAppearance: Bool = false) {
        if isModal {
            if points > 0 && !summariesForDisplayDate.isEmpty {
                if !isInitialAppearance { self.showContinueButton = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + (isInitialAppearance ? 0.1 : 1.0) ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { self.showContinueButton = true }
                }
            } else { self.showContinueButton = true }
        }
    }

    @ViewBuilder
    private func lastDayCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(dynamicSecondaryBackgroundColor)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }

    private func insightRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(dynamicPrimaryColor)
                .frame(width: 22, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundColor(dynamicTextColor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct TaskSummaryRow: View {
    let taskResult: TaskPointResult
    var hasProofFeedBreakdown: Bool = false
    var proofFeedCheckVotes: Int = 0
    var proofFeedXVotes: Int = 0
    var proofFeedPointsMultiplierApplied: Double = 1.0
    var proofFeedBonusExtraPoints: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: taskResult.mainTaskCompletedOnTargetDay ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(taskResult.mainTaskCompletedOnTargetDay ? dynamicSecondaryColor : dynamicAccentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(taskResult.title)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(dynamicTextColor)
                    Text(taskResult.origin == .today ? "Today" : "Master List")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(taskResult.origin == .today ? dynamicPrimaryColor : dynamicAccentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            taskResult.origin == .today ?
                                dynamicPrimaryColor.opacity(0.15) :
                                dynamicAccentColor.opacity(0.15)
                        )
                        .cornerRadius(6)
                }
                Spacer()
                Text("+\(Int(taskResult.totalPoints)) / \(Int(taskResult.basePoints))")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(dynamicPrimaryColor)
            }
            if hasProofFeedBreakdown {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .frame(width: 18, alignment: .center)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Label("\(proofFeedCheckVotes)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Label("\(proofFeedXVotes)", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        if proofFeedPointsMultiplierApplied > 1.0 + 0.001 {
                            Text("Proof boost: \(String(format: "%.1f×", proofFeedPointsMultiplierApplied)) (+\(Int((proofFeedBonusExtraPoints).rounded()))) pts)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(dynamicPrimaryColor)
                        } else {
                            Text("Proof boost: none (need friends to vote more checks than Xs)")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                }
                .padding(.leading, 4)
            }
            if !taskResult.subtaskPoints.isEmpty {
                ForEach(taskResult.subtaskPoints.filter { $0.earned > 0 }, id: \.title) { sub in
                    HStack {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(sub.title)
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Spacer()
                        Text("+\(Int(sub.earned))")
                            .font(.subheadline)
                            .foregroundColor(dynamicPrimaryColor.opacity(0.8))
                    }.padding(.leading, 25)
                }
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

struct TasksCompletionProgressView: View {
    let completedTasks: Int
    let totalTasks: Int
    var progress: Double {
        guard totalTasks > 0 else { return 0 }
        let validCompletedTasks = min(completedTasks, totalTasks)
        return Double(validCompletedTasks) / Double(totalTasks)
    }
    var body: some View {
        ZStack {
            Circle()
                .stroke(dynamicSecondaryTextColor.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0.0, to: max(0.0, min(1.0, progress)))
                .stroke(dynamicPrimaryColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.interpolatingSpring(stiffness: 100, damping: 10), value: progress)
            VStack {
                Text("\(Int(progress * 100))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
                Text(totalTasks > 0 ? "Day's Tasks" : "No Tasks")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Text(totalTasks > 0 ? "Completed" : "Recorded")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }.multilineTextAlignment(.center)
        }
    }
}

struct XPProgressView: View {
    let levelBefore: Int
    let xpBefore: Double
    let levelAfter: Int
    let xpAfter: Double
    let xpGainedThisSession: Double
    let xpForNextLevel: Double
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
        
        _displayedLevel = State(initialValue: levelBefore)
        _animatedXP = State(initialValue: xpBefore)
        _displayedXPForNextLevel = State(initialValue: PlayerStats.xpRequiredForNextLevel(currentLevel: levelBefore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Level: \(displayedLevel)")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                    .animation(nil, value: displayedLevel)
                Spacer()
                if showLevelUpMessage {
                    Text("LEVEL UP!")
                        .font(.headline)
                        .foregroundColor(dynamicAccentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            ProgressView(value: animatedXP, total: displayedXPForNextLevel) {
            } currentValueLabel: {
                Text("\(Int(animatedXP)) / \(Int(displayedXPForNextLevel)) XP")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            .progressViewStyle(LinearProgressViewStyle(tint: dynamicPrimaryColor))
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(dynamicSecondaryColor.opacity(0.2))
            )
            .cornerRadius(5)
            .animation(.easeInOut(duration: 1.0), value: animatedXP)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    if didLevelUp {
                        let xpForLevelBefore = PlayerStats.xpRequiredForNextLevel(currentLevel: levelBefore)
                        animatedXP = xpForLevelBefore

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation {
                                showLevelUpMessage = true
                                displayedLevel = levelAfter
                            }
                            animatedXP = 0
                            displayedXPForNextLevel = xpForNextLevel
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    animatedXP = xpAfter
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                     withAnimation { showLevelUpMessage = false }
                                }
                            }
                        }
                    } else {
                        displayedLevel = levelAfter
                        displayedXPForNextLevel = xpForNextLevel
                        animatedXP = xpAfter
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

extension Calendar {
    func isDate(_ date1: Date, equalToOrBefore date2: Date) -> Bool { return compare(date1, to: date2, toGranularity: .day) != .orderedDescending }
    func isDate(_ date1: Date, equalToOrLaterThan date2: Date) -> Bool { return compare(date1, to: date2, toGranularity: .day) != .orderedAscending }
    func isDate(_ date1: Date, onDayBefore date2: Date) -> Bool {
        guard let dayBefore = self.date(byAdding: .day, value: -1, to: date2) else { return false }
        return isDate(date1, inSameDayAs: dayBefore)
    }
}
