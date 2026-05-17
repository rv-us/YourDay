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

    @State private var selectedTaskIds: Set<String> = []
    @State private var proposedStartTime = Date()
    @State private var proposedDuration = 60
    @State private var showingCalendarSheet = false
    @State private var isSaving = false
    @State private var alertMessage: String?
    @State private var showAlert = false
    @State private var showRemoveFromCalendarConfirm = false
    @State private var isRemovingFromCalendar = false

    private var todayTasks: [TodoItem] {
        todoItems.filter { $0.origin == .today && !$0.isDone }
    }

    private var selectedTasks: [TodoItem] {
        todayTasks.filter { selectedTaskIds.contains($0.localTaskId) }
    }

    private var selectedTask: TodoItem? {
        selectedTasks.first
    }

    private var proposedEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: proposedDuration, to: proposedStartTime) ?? proposedStartTime
    }

    private var selectedEventIds: [String] {
        Array(
            Set(
                selectedTasks
                    .compactMap(\.manualScheduleGoogleEventId)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
    }

    private var sharedSelectedEventId: String? {
        selectedEventIds.count == 1 ? selectedEventIds[0] : nil
    }

    private var hasLinkedManualCalendarEvent: Bool {
        sharedSelectedEventId != nil
    }

    /// Any selected task still linked to a Google Calendar event (for removal / merge cleanup).
    private var selectedTasksHaveCalendarLinks: Bool {
        selectedTasks.contains { t in
            let id = t.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !id.isEmpty
        }
    }

    /// Short label on the calendar drag block (one task name, or a count for several).
    private var proposedCalendarBlockTitle: String {
        if selectedTasks.count == 1, let t = selectedTasks.first {
            return t.title
        }
        if selectedTasks.isEmpty {
            return "Time block"
        }
        return "\(selectedTasks.count) tasks"
    }

    /// Shown as separate lines on the proposed block so titles don’t clump into one long string.
    private var proposedCalendarTaskLines: [String]? {
        guard selectedTasks.count > 1 else { return nil }
        return selectedTasks.map(\.title)
    }

    private func hasLinkedEventOnSelectedDate(_ task: TodoItem) -> Bool {
        guard let eventId = task.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !eventId.isEmpty,
              let event = schedulingViewModel.calendarEvents.first(where: { $0.id == eventId }),
              let startDate = event.start.startDate else {
            return false
        }
        return Calendar.current.isDate(startDate, inSameDayAs: selectedDate)
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
        .onChange(of: selectedTaskIds) { _, _ in
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
                    sessionTitle: proposedCalendarBlockTitle,
                    sessionTaskLines: proposedCalendarTaskLines,
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
        .alert("Remove from Google Calendar?", isPresented: $showRemoveFromCalendarConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                removeFromGoogleCalendar()
            }
        } message: {
            Text("The calendar event for the selected task\(selectedTasks.count == 1 ? "" : "s") will be deleted. You can add a new time later.")
        }
    }

    private var introCopy: some View {
        Text("Choose tasks from Today, set a time on your calendar, then add or update that block in Google Calendar.")
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
        let isSelected = selectedTaskIds.contains(task.localTaskId)
        return Button {
            if isSelected {
                selectedTaskIds.remove(task.localTaskId)
            } else {
                selectedTaskIds.insert(task.localTaskId)
            }
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
                    if hasLinkedEventOnSelectedDate(task) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Text("Already on calendar — saving moves this event")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
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

                if selectedTasks.count > 1 {
                    calendarGroupingPreview
                }

                Button {
                    showingCalendarSheet = true
                } label: {
                    HStack {
                        Image(systemName: "calendar.day.timeline.left")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(CalendarTimeFormatter.formatTimeRange(start: proposedStartTime, end: proposedEndTime))
                                .font(.subheadline)
                                .foregroundColor(dynamicTextColor)
                            Text("Tap to place on the timeline • Drag to move, bottom edge to change duration")
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

                if selectedTasksHaveCalendarLinks {
                    Button {
                        showRemoveFromCalendarConfirm = true
                    } label: {
                        HStack {
                            if isRemovingFromCalendar {
                                ProgressView()
                                    .tint(dynamicPrimaryColor)
                            } else {
                                Image(systemName: "calendar.badge.minus")
                            }
                            Text("Remove from Google Calendar")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isRemovingFromCalendar)
                }
            }
            .padding()
            .background(dynamicSecondaryBackgroundColor.opacity(0.6))
            .cornerRadius(12)
        }
    }

    /// When several tasks share one calendar block, show them as a numbered list instead of a single dense line.
    private var calendarGroupingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Together on your calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(dynamicSecondaryTextColor)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(selectedTasks.enumerated()), id: \.element.localTaskId) { index, task in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(dynamicPrimaryColor)
                            .frame(minWidth: 20, alignment: .center)
                        Text(task.title)
                            .font(.subheadline)
                            .foregroundColor(dynamicTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 5)
                    if index < selectedTasks.count - 1 {
                        Divider()
                            .background(dynamicTextColor.opacity(0.12))
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(dynamicSecondaryBackgroundColor.opacity(0.55))
            )
        }
    }

    private func applyDefaultScheduleForSelection() {
        let cal = Calendar.current
        let sod = cal.startOfDay(for: selectedDate)
        proposedDuration = 60
        if cal.isDateInToday(selectedDate) {
            proposedStartTime = Self.nextFifteenMinuteStart(from: Date(), dayStart: sod, calendar: cal)
        } else {
            proposedStartTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: sod) ?? sod
        }
    }
    
    /// Rounds up to the next 15-minute boundary; clamps so a 60-minute block still fits the same calendar day.
    private static func nextFifteenMinuteStart(from reference: Date, dayStart: Date, calendar: Calendar) -> Date {
        let h = calendar.component(.hour, from: reference)
        let m = calendar.component(.minute, from: reference)
        var total = h * 60 + m
        let rem = total % 15
        if rem != 0 {
            total += 15 - rem
        }
        let lastValidStart = 23 * 60 + 0
        total = min(total, lastValidStart)
        let nh = total / 60
        let nm = total % 60
        return calendar.date(bySettingHour: nh, minute: nm, second: 0, of: dayStart) ?? dayStart
    }

    /// Returns `true` if times were taken from the linked Google event in the current fetch.
    @discardableResult
    private func applyProposedFromStoredEventIfPossible() -> Bool {
        guard let eid = sharedSelectedEventId,
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

    private func clearTaskScheduleState(_ task: TodoItem) {
        task.manualScheduleGoogleEventId = nil
        task.scheduledStartTime = nil
        task.scheduledEndTime = nil
    }

    private func removeFromGoogleCalendar() {
        let eventIds = Set(
            selectedTasks.compactMap { $0.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let idList = Array(eventIds)
        guard !idList.isEmpty else { return }
        isRemovingFromCalendar = true
        ManualCalendarEventDeletionService.deleteGoogleCalendarEventsAndUnlinkLocalTasks(
            eventIds: idList,
            modelContext: modelContext,
            firebaseManager: firebaseManager
        ) { err in
            DispatchQueue.main.async {
                self.isRemovingFromCalendar = false
                if let err = err {
                    self.alertMessage = err.localizedDescription
                    self.showAlert = true
                    return
                }
                self.schedulingViewModel.fetchCalendarEvents(for: self.selectedDate)
            }
        }
    }

    private func addToGoogleCalendar() {
        let tasksToSchedule = selectedTasks
        guard !tasksToSchedule.isEmpty else { return }
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

        let taskTitles = tasksToSchedule.map(\.title)
        let googleCalendarEventTitle: String
        if taskTitles.count == 1 {
            googleCalendarEventTitle = taskTitles[0]
        } else {
            googleCalendarEventTitle = "\(taskTitles[0]) and \(taskTitles.count - 1) more"
        }
        let combinedDetails = tasksToSchedule
            .map(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let descriptionBody: String
        let tasksList = taskTitles.map { "• \($0)" }.joined(separator: "\n")
        if combinedDetails.isEmpty {
            descriptionBody = "Tasks:\n\(tasksList)\(scheduledTaskMarker)"
        } else {
            descriptionBody = "Tasks:\n\(tasksList)\n\n\(combinedDetails)\(scheduledTaskMarker)"
        }

        let calendarManager = GoogleCalendarManager.shared

        func finishSuccess(eventId: String) {
            tasksToSchedule.forEach {
                $0.manualScheduleGoogleEventId = eventId
                $0.scheduledStartTime = start
                $0.scheduledEndTime = end
            }
            try? modelContext.save()
            tasksToSchedule.forEach(syncTodoItemToFirebase)
            ScreenTimeManager.shared.scheduleSnapshotRefresh(context: modelContext)

            firebaseManager.saveScheduledEvent(
                eventId: eventId,
                taskTitle: googleCalendarEventTitle,
                tasks: taskTitles,
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
                        taskTitle: googleCalendarEventTitle,
                        scheduledEndTime: end
                    )
                    NotificationManager.shared.schedulePreTaskNotification(
                        eventId: eventId,
                        taskTitle: googleCalendarEventTitle,
                        scheduledStartTime: start
                    )

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self.schedulingViewModel.fetchCalendarEvents(for: self.selectedDate)
                    }
                    self.selectedTaskIds.removeAll()
                }
            }
        }

        func handleCreate() {
            calendarManager.createCalendarEvent(
                title: googleCalendarEventTitle,
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
                title: googleCalendarEventTitle,
                start: start,
                end: end,
                description: descriptionBody
            ) { returnedId, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let ns = error as NSError
                        if ns.code == 404 || ns.code == 410 {
                            tasksToSchedule.forEach { $0.manualScheduleGoogleEventId = nil }
                            try? self.modelContext.save()
                            tasksToSchedule.forEach(self.syncTodoItemToFirebase)
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
                    if let existingId = sharedSelectedEventId {
                        handleUpdate(existingId: existingId)
                    } else {
                        // One combined block, but tasks may still reference separate old events; remove those
                        // from Google so duplicate blocks don’t remain after the merge.
                        let oldEventIds = Set(
                            tasksToSchedule.compactMap { $0.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        )
                        if oldEventIds.isEmpty {
                            handleCreate()
                        } else {
                            let idsToRetire = Array(oldEventIds)
                            calendarManager.deleteCalendarEventsSequentially(idsToRetire) { err in
                                DispatchQueue.main.async {
                                    if let err = err {
                                        self.isSaving = false
                                        self.alertMessage = err.localizedDescription
                                        self.showAlert = true
                                        return
                                    }
                                    for id in idsToRetire {
                                        NotificationManager.shared.cancelJournalPromptNotification(eventId: id)
                                        self.firebaseManager.deleteScheduledEvent(eventId: id) { _ in }
                                    }
                                    for t in tasksToSchedule {
                                        self.clearTaskScheduleState(t)
                                    }
                                    try? self.modelContext.save()
                                    for t in tasksToSchedule {
                                        self.syncTodoItemToFirebase(t)
                                    }
                                    handleCreate()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
