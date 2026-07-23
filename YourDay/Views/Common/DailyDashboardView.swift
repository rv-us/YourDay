//
//  DailyDashboardView.swift
//  YourDay
//
//  The "Start your day" popup shown after the last-day summary on a new day. A 2x2
//  grid of tiles — Migrate / Schedule / New tasks / Recap — replaces the old forced
//  chain of sheets. Each tile opens its sub-flow and checks off (faded green) ONLY
//  once the real action actually happened (a migration confirmed, a task scheduled, a
//  new task added, the recap opened). Backing out / Skip leaves a tile unchecked.
//
//  "Do this later" dismisses but lets the popup reappear on the next app open; the
//  reappear gate (Migrate + Schedule + New tasks) lives in DailyChecklistStore and is
//  read by ContentView. Recap is a shortcut only and does not gate reappearing.
//

import SwiftUI
import SwiftData

struct DailyDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var firebaseManager: FirebaseManager

    @Query private var allTodoItems: [TodoItem]
    @Query(sort: [SortDescriptor(\DailySummaryTask.date, order: .reverse)])
    private var allSummaries: [DailySummaryTask]

    // Shared with DailyChecklistStore via the same UserDefaults keys.
    @AppStorage(DailyChecklistStore.migrateDoneKey) private var migrateDoneDate = ""
    @AppStorage(DailyChecklistStore.scheduleDoneKey) private var scheduleDoneDate = ""
    @AppStorage(DailyChecklistStore.newTasksDoneKey) private var newTasksDoneDate = ""
    @AppStorage(DailyChecklistStore.recapViewedKey) private var recapViewedDate = ""

    /// Dismiss but allow the popup to reappear next open.
    var onDismissForLater: () -> Void
    /// Dismiss and suppress the popup for the rest of the day.
    var onSkip: () -> Void

    private enum Subflow: Int, Identifiable {
        case migrate, schedule, newTasks, recap
        var id: Int { rawValue }
    }
    @State private var activeSubflow: Subflow?
    @State private var lastOpened: Subflow?
    @State private var scheduledCountAtOpen = 0
    @State private var todayCountAtOpen = 0

    // MARK: - Live counts (reuse the exact filters the sub-flows use)

    /// Matches MigrateTasksView.tasksToReview — any task with incomplete work.
    private var migrateCount: Int {
        allTodoItems.filter { !$0.isDone || $0.subtasks.contains { !$0.isDone } }.count
    }

    /// Today tasks not yet placed on the calendar (ManualSchedulingView.todayTasks + unscheduled gate).
    private var scheduleCount: Int {
        allTodoItems.filter {
            $0.origin == .today && !$0.isDone && isUnscheduled($0)
        }.count
    }

    /// Today tasks that already have a calendar block — grows when the user schedules something.
    private var scheduledTodayCount: Int {
        allTodoItems.filter { $0.origin == .today && !isUnscheduled($0) }.count
    }

    /// All today tasks — grows when the user adds a new task.
    private var todayCount: Int {
        allTodoItems.filter { $0.origin == .today }.count
    }

    private func isUnscheduled(_ task: TodoItem) -> Bool {
        (task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?? true
    }

    private var recapSummary: DailySummaryTask? { allSummaries.first }

    private var recapProgress: Double {
        guard let s = recapSummary, s.dayCompletionSnapshot_TotalTasksCount > 0 else { return 0 }
        let done = min(s.dayCompletionSnapshot_CompletedCount, s.dayCompletionSnapshot_TotalTasksCount)
        return Double(done) / Double(s.dayCompletionSnapshot_TotalTasksCount)
    }

    // MARK: - Completion state

    private var today: String { DailyChecklistStore.todayString() }
    private var migrateDone: Bool { migrateDoneDate == today }
    private var scheduleDone: Bool { scheduleDoneDate == today }
    private var newTasksDone: Bool { newTasksDoneDate == today }
    private var recapViewed: Bool { recapViewedDate == today }
    private var gateComplete: Bool { migrateDone && scheduleDone && newTasksDone }

    private var dateSubtitle: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date())
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    migrateTile
                    scheduleTile
                    newTasksTile
                    recapTile
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            footer
        }
        .background(dynamicBackgroundColor.ignoresSafeArea())
        .sheet(item: $activeSubflow, onDismiss: evaluateCompletion) { flow in
            subflowView(flow)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("Start your day")
                .font(.title2.weight(.bold))
                .foregroundColor(dynamicTextColor)
            Text(dateSubtitle)
                .font(.subheadline)
                .foregroundColor(dynamicSecondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 4)
        .padding(.horizontal)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                onDismissForLater()
            } label: {
                Text(gateComplete ? "Done" : "Do this later")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(gateComplete ? dynamicSecondaryColor : dynamicPrimaryColor)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .buttonStyle(ScaleButtonStyle())

            if !gateComplete {
                Button("Skip for today") { onSkip() }
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
    }

    // MARK: - Tiles

    private var migrateTile: some View {
        checklistTile(
            title: "Migrate tasks",
            subtitle: "From yesterday & master list",
            isDone: migrateDone,
            top: { iconCircle(icon: "tray.and.arrow.down.fill", tint: migrateDone ? dynamicPrimaryColor : dynamicPrimaryColor) },
            badge: { countBadge(migrateCount, label: "pending", show: !migrateDone && migrateCount > 0) },
            action: openMigrate
        )
    }

    private var scheduleTile: some View {
        checklistTile(
            title: "Schedule tasks",
            subtitle: "Put today's tasks on your calendar",
            isDone: scheduleDone,
            top: { iconCircle(icon: "calendar.badge.clock", tint: scheduleDone ? dynamicPrimaryColor : dynamicSecondaryColor) },
            badge: { countBadge(scheduleCount, label: "to schedule", show: !scheduleDone && scheduleCount > 0) },
            action: openSchedule
        )
    }

    private var newTasksTile: some View {
        checklistTile(
            title: "New tasks",
            subtitle: "Plan what else is on today",
            isDone: newTasksDone,
            top: { iconCircle(icon: "sparkles", tint: newTasksDone ? dynamicPrimaryColor : dynamicPrimaryColor) },
            badge: { EmptyView() },
            action: openNewTasks
        )
    }

    private var recapTile: some View {
        checklistTile(
            title: "Last day recap",
            subtitle: recapSummary != nil ? "\(Int(recapSummary?.xpEarnedOnDate ?? 0)) pts earned" : "View your summary",
            isDone: recapViewed,
            top: {
                if recapSummary != nil {
                    miniRing(progress: recapProgress)
                } else {
                    iconCircle(icon: "chart.pie.fill", tint: dynamicPrimaryColor)
                }
            },
            badge: { EmptyView() },
            action: openRecap
        )
    }

    // MARK: - Tile builder

    private func checklistTile<Top: View, Badge: View>(
        title: String,
        subtitle: String,
        isDone: Bool,
        @ViewBuilder top: () -> Top,
        @ViewBuilder badge: () -> Badge,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                top()
                VStack(spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(isDone ? dynamicSecondaryTextColor : dynamicTextColor)
                        .multilineTextAlignment(.center)
                    Text(isDone ? "Done" : subtitle)
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                badge()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 158)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(isDone ? dynamicPrimaryColor.opacity(0.12) : dynamicSecondaryBackgroundColor)
            .cornerRadius(14)
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(dynamicPrimaryColor)
                        .padding(8)
                }
            }
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private func iconCircle(icon: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 54, height: 54)
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundColor(tint)
        }
    }

    private func miniRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(dynamicSecondaryTextColor.opacity(0.2), lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(dynamicPrimaryColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))%")
                .font(.caption.weight(.bold))
                .foregroundColor(dynamicTextColor)
        }
        .frame(width: 54, height: 54)
    }

    private func countBadge(_ count: Int, label: String, show: Bool) -> some View {
        Group {
            if show {
                HStack(spacing: 5) {
                    Text("\(count)")
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    Text(label)
                        .font(.caption2.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(dynamicSecondaryColor))
            } else {
                Color.clear.frame(height: 1)
            }
        }
    }

    // MARK: - Tile actions

    private func openMigrate() {
        lastOpened = .migrate
        activeSubflow = .migrate
    }

    private func openSchedule() {
        scheduledCountAtOpen = scheduledTodayCount
        lastOpened = .schedule
        activeSubflow = .schedule
    }

    private func openNewTasks() {
        todayCountAtOpen = todayCount
        lastOpened = .newTasks
        activeSubflow = .newTasks
    }

    private func openRecap() {
        recapViewedDate = today   // viewing is the action (cosmetic, non-gating)
        lastOpened = .recap
        activeSubflow = .recap
    }

    /// Detect whether the real action happened while the sub-flow was open.
    private func evaluateCompletion() {
        switch lastOpened {
        case .schedule:
            if scheduledTodayCount > scheduledCountAtOpen { scheduleDoneDate = today }
        case .newTasks:
            if todayCount > todayCountAtOpen { newTasksDoneDate = today }
        case .migrate, .recap, .none:
            break   // migrate is marked in its callback; recap on open
        }
        lastOpened = nil
    }

    // MARK: - Sub-flow presentation

    @ViewBuilder
    private func subflowView(_ flow: Subflow) -> some View {
        switch flow {
        case .migrate:
            NavigationView {
                MigrateTasksView(onMigrationConfirmed: { count in
                    if count >= 1 { migrateDoneDate = today }
                })
                .environment(\.modelContext, modelContext)
                .environmentObject(firebaseManager)
            }
        case .schedule:
            SmartSchedulingView(
                initialDate: Calendar.current.startOfDay(for: Date()),
                autoStart: false,
                onSkip: { activeSubflow = nil }
            )
            .environment(\.modelContext, modelContext)
            .environmentObject(firebaseManager)
        case .newTasks:
            DailyPlanningNoteView(isPresented: Binding(
                get: { activeSubflow == .newTasks },
                set: { if !$0 { activeSubflow = nil } }
            ))
            .environment(\.modelContext, modelContext)
        case .recap:
            NavigationView {
                LastDayView(isModal: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSubflow = nil }
                        }
                    }
            }
            .environment(\.modelContext, modelContext)
        }
    }
}
