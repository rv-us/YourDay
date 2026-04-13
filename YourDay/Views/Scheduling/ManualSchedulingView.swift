//
//  ManualSchedulingView.swift
//  YourDay
//
//  Place a Today-list task on the calendar and create or update a Google Calendar event.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct ManualSchedulingView: View {
    @Binding var selectedDate: Date
    let todoItems: [TodoItem]
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @EnvironmentObject private var firebaseManager: FirebaseManager
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTaskId: String?
    @State private var proposedStartTime = Date()
    @State private var proposedDuration = 60
    @State private var showingCalendarSheet = false
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var showAlert = false

    private var todayTasks: [TodoItem] {
        todoItems.filter { $0.origin == .today && !$0.isDone }
    }

    private var selectedTask: TodoItem? {
        guard let id = selectedTaskId else { return nil }
        return todayTasks.first { $0.localTaskId == id }
    }

    private var proposedEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: proposedDuration, to: proposedStartTime) ?? proposedStartTime
    }

    private var hasLinkedManualCalendarEvent: Bool {
        guard let id = selectedTask?.manualScheduleGoogleEventId else { return false }
        return !id.isEmpty
    }

    private var primaryActionTitle: String {
        if isSaving { return "Saving…" }
        return hasLinkedManualCalendarEvent ? "Update Google Calendar" : "Add to Google Calendar"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            introCopy
            calendarFetchBanner
            todayTasksCard
            timeAndSaveCard
        }
        .onAppear {
            schedulingViewModel.selectedDate = selectedDate
            schedulingViewModel.fetchCalendarEvents(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            schedulingViewModel.selectedDate = newDate
            alignProposedStartToSelectedDay(newDate)
            schedulingViewModel.fetchCalendarEvents(for: newDate)
        }
        .onChange(of: selectedTaskId) { _, _ in
            refreshProposedTimesForSelection()
        }
        .onChange(of: schedulingViewModel.calendarEvents) { _, _ in
            if selectedTask != nil {
                refreshProposedTimesForSelection()
            }
        }
        .sheet(isPresented: $showingCalendarSheet) {
            if let task = selectedTask {
                DraggableCalendarView(
                    proposedStartTime: $proposedStartTime,
                    proposedDuration: $proposedDuration,
                    events: schedulingViewModel.calendarEvents,
                    selectedDate: Calendar.current.startOfDay(for: selectedDate),
                    sessionTitle: task.title,
                    allowsDurationResize: true
                )
            }
        }
        .alert("Calendar", isPresented: $showAlert, actions: {
            Button("OK", role: .cancel) {
                alertMessage = nil
            }
        }, message: {
            Text(alertMessage ?? "")
        })
    }

    private var introCopy: some View {
        Text("Pick a task from Today, place it on your calendar, then add or update it on Google Calendar.")
            .font(.subheadline)
            .foregroundColor(dynamicSecondaryTextColor)
    }

    @ViewBuilder
    private var calendarFetchBanner: some View {
        if let fetchError = schedulingViewModel.calendarFetchError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(fetchError)
                    .font(.caption)
                    .foregroundColor(dynamicTextColor)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(dynamicSecondaryBackgroundColor)
            .cornerRadius(10)
        }
    }

    private var todayTasksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            if todayTasks.isEmpty {
                Text("No incomplete tasks on your Today list.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            } else {
                ForEach(todayTasks, id: \.localTaskId) { task in
                    todayTaskRow(task: task)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }

    private func todayTaskRow(task: TodoItem) -> some View {
        let isSelected = selectedTaskId == task.localTaskId
        return Button {
            selectedTaskId = task.localTaskId
            refreshProposedTimesForSelection()
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                        .multilineTextAlignment(.leading)
                    if let eid = task.manualScheduleGoogleEventId, !eid.isEmpty {
                        Text("Already on calendar — saving moves this event")
                            .font(.caption2)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var timeAndSaveCard: some View {
        if selectedTask != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Time")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)

                Button {
                    showingCalendarSheet = true
                } label: {
                    HStack {
                        Image(systemName: "calendar.day.timeline.left")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CalendarTimeFormatter.formatTimeRange(start: proposedStartTime, end: proposedEndTime))
                                .font(.subheadline)
                                .foregroundColor(dynamicTextColor)
                            Text("Drag to move, drag bottom edge to change duration")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: addToGoogleCalendar) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: hasLinkedManualCalendarEvent ? "calendar.badge.clock" : "calendar.badge.plus")
                        }
                        Text(primaryActionTitle)
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(dynamicPrimaryColor)
                    .cornerRadius(10)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isSaving)
            }
            .padding()
            .background(dynamicSecondaryBackgroundColor.opacity(0.6))
            .cornerRadius(12)
        }
    }

    private func applyDefaultScheduleForSelection() {
        let cal = Calendar.current
        let sod = cal.startOfDay(for: selectedDate)
        proposedStartTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: sod) ?? sod
        proposedDuration = 60
    }

    /// Returns `true` if times were taken from the linked Google event in the current fetch.
    @discardableResult
    private func applyProposedFromStoredEventIfPossible() -> Bool {
        guard let task = selectedTask,
              let eid = task.manualScheduleGoogleEventId,
              !eid.isEmpty,
              let match = schedulingViewModel.calendarEvents.first(where: { $0.id == eid }),
              let start = match.start.startDate else {
            return false
        }
        let cal = Calendar.current
        let end = match.end?.startDate ?? cal.date(byAdding: .hour, value: 1, to: start) ?? start
        proposedStartTime = start
        let mins = Int(round(end.timeIntervalSince(start) / 60.0))
        proposedDuration = max(15, min(480, mins))
        return true
    }

    private func refreshProposedTimesForSelection() {
        if !applyProposedFromStoredEventIfPossible() {
            applyDefaultScheduleForSelection()
        }
    }

    private func alignProposedStartToSelectedDay(_ day: Date) {
        let cal = Calendar.current
        let sod = cal.startOfDay(for: day)
        let h = cal.component(.hour, from: proposedStartTime)
        let m = cal.component(.minute, from: proposedStartTime)
        proposedStartTime = cal.date(bySettingHour: h, minute: m, second: 0, of: sod) ?? sod
    }

    private func syncTodoItemToFirebase(_ task: TodoItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let codable = TodoItemCodable(from: task, userId: userId)
        firebaseManager.saveTodoItem(codable) { error in
            if let error = error {
                print("ManualSchedulingView: Failed to sync todo after manual schedule: \(error.localizedDescription)")
            }
        }
    }

    private func addToGoogleCalendar() {
        guard let task = selectedTask else { return }
        isSaving = true
        alertMessage = nil

        let cal = Calendar.current
        let start = proposedStartTime
        guard let end = cal.date(byAdding: .minute, value: proposedDuration, to: start) else {
            isSaving = false
            alertMessage = "Invalid end time."
            showAlert = true
            return
        }

        let detailLine = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let descriptionBody: String
        if detailLine.isEmpty {
            descriptionBody = "Tasks:\n• \(task.title)\(scheduledTaskMarker)"
        } else {
            descriptionBody = "Tasks:\n• \(task.title)\n\n\(detailLine)\(scheduledTaskMarker)"
        }

        let calendarManager = GoogleCalendarManager.shared

        func finishSuccess(eventId: String) {
            task.manualScheduleGoogleEventId = eventId
            try? modelContext.save()
            syncTodoItemToFirebase(task)

            firebaseManager.saveScheduledEvent(
                eventId: eventId,
                taskTitle: task.title,
                tasks: [task.title],
                startTime: start,
                endTime: end
            ) { saveError in
                DispatchQueue.main.async {
                    self.isSaving = false
                    if let saveError = saveError {
                        self.alertMessage = saveError.localizedDescription
                        self.showAlert = true
                        return
                    }

                    NotificationManager.shared.scheduleJournalPromptNotification(
                        eventId: eventId,
                        taskTitle: task.title,
                        scheduledEndTime: end
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.schedulingViewModel.fetchCalendarEvents(for: self.selectedDate)
                    }
                }
            }
        }

        func handleCreate() {
            calendarManager.createCalendarEvent(
                title: task.title,
                start: start,
                end: end,
                description: descriptionBody
            ) { eventId, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.isSaving = false
                        self.alertMessage = error.localizedDescription
                        self.showAlert = true
                        return
                    }
                    guard let eventId = eventId, !eventId.isEmpty else {
                        self.isSaving = false
                        self.alertMessage = "Could not confirm the calendar event."
                        self.showAlert = true
                        return
                    }
                    finishSuccess(eventId: eventId)
                }
            }
        }

        func handleUpdate(existingId: String) {
            calendarManager.updateCalendarEvent(
                eventId: existingId,
                title: task.title,
                start: start,
                end: end,
                description: descriptionBody
            ) { returnedId, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let ns = error as NSError
                        if ns.code == 404 || ns.code == 410 {
                            task.manualScheduleGoogleEventId = nil
                            try? self.modelContext.save()
                            self.syncTodoItemToFirebase(task)
                            handleCreate()
                            return
                        }
                        self.isSaving = false
                        self.alertMessage = error.localizedDescription
                        self.showAlert = true
                        return
                    }
                    guard let eventId = returnedId, !eventId.isEmpty else {
                        self.isSaving = false
                        self.alertMessage = "Could not confirm the calendar event."
                        self.showAlert = true
                        return
                    }
                    finishSuccess(eventId: eventId)
                }
            }
        }

        calendarManager.ensureCalendarWriteAccess { accessResult in
            DispatchQueue.main.async {
                switch accessResult {
                case .failure(let err):
                    self.isSaving = false
                    self.alertMessage = err.localizedDescription
                    self.showAlert = true
                case .success:
                    if let existingId = task.manualScheduleGoogleEventId, !existingId.isEmpty {
                        handleUpdate(existingId: existingId)
                    } else {
                        handleCreate()
                    }
                }
            }
        }
    }
}
