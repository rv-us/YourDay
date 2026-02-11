//
//  JournalCompletionFlowView.swift
//  YourDay
//
//  Completion-first prompt that routes to journaling or rescheduling
//

import SwiftUI

struct JournalCompletionFlowView: View {
    @ObservedObject var journalViewModel: JournalViewModel
    let pendingEvent: TaskEndMonitor.PendingJournalEvent

    @State private var step: FlowStep = .completion
    @State private var selectedCompletionStatus: CompletionStatus = .completed
    @State private var proposedStartTime: Date
    @State private var proposedDuration: Int
    @State private var showingCalendarPicker = false
    @State private var isScheduling = false
    @State private var rescheduleError: String?
    @State private var lastFetchedDate: Date?

    @StateObject private var schedulingViewModel = SchedulingAssistantViewModel()
    private let calendarManager = GoogleCalendarManager.shared
    private let firebaseManager = FirebaseManager.shared

    private enum FlowStep {
        case completion
        case journal
        case reschedule
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var taskTitles: [String] {
        pendingEvent.tasks.isEmpty ? [pendingEvent.taskTitle] : pendingEvent.tasks
    }

    init(journalViewModel: JournalViewModel, pendingEvent: TaskEndMonitor.PendingJournalEvent) {
        self.journalViewModel = journalViewModel
        self.pendingEvent = pendingEvent
        let durationMinutes = max(15, Int(pendingEvent.scheduledEndTime.timeIntervalSince(pendingEvent.scheduledStartTime) / 60))
        _proposedStartTime = State(initialValue: pendingEvent.scheduledStartTime)
        _proposedDuration = State(initialValue: durationMinutes)
    }

    private var proposedEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: proposedDuration, to: proposedStartTime) ?? proposedStartTime
    }

    var body: some View {
        Group {
            switch step {
            case .completion:
                completionView
            case .journal:
                JournalPromptView(
                    journalViewModel: journalViewModel,
                    pendingEvent: pendingEvent,
                    initialCompletionStatus: selectedCompletionStatus
                )
            case .reschedule:
                rescheduleView
            }
        }
        .onChange(of: pendingEvent.eventId) { _, _ in
            resetFlow()
        }
        .onChange(of: step) { _, newStep in
            if newStep == .reschedule {
                refreshCalendarIfNeeded(for: proposedStartTime)
                // Don't auto-open calendar picker - let user tap "Adjust on calendar" button manually (Bug 2 fix)
            }
        }
        .onChange(of: proposedStartTime) { _, newValue in
            if step == .reschedule {
                refreshCalendarIfNeeded(for: newValue)
            }
        }
    }

    private var completionView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection(
                        icon: "checkmark.seal.fill",
                        title: "How did it go?",
                        subtitle: "Quick check-in before we continue."
                    )

                    taskInfoCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("What happened?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        completionOptionButton(
                            title: "Completed",
                            subtitle: "You finished the session",
                            icon: "checkmark.circle.fill",
                            tint: .green
                        ) {
                            selectedCompletionStatus = .completed
                            step = .journal
                        }

                        completionOptionButton(
                            title: "Partially completed",
                            subtitle: "You made some progress",
                            icon: "circle.lefthalf.filled",
                            tint: .orange
                        ) {
                            selectedCompletionStatus = .partial
                            step = .journal
                        }

                        completionOptionButton(
                            title: "Didn't get to it",
                            subtitle: "Reschedule or skip",
                            icon: "arrow.uturn.left.circle.fill",
                            tint: .red
                        ) {
                            selectedCompletionStatus = .notStarted
                            step = .reschedule
                        }
                    }
                    .padding(.horizontal)

                    Button(action: {
                        journalViewModel.skipJournalPrompt()
                    }) {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(journalViewModel.isLoading)
                    .padding(.top, 4)
                }
                .padding(.bottom, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        journalViewModel.skipJournalPrompt()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(journalViewModel.isLoading)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private var rescheduleView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection(
                        icon: "calendar.badge.clock",
                        title: "Pick a new time",
                        subtitle: "Drag the block to place your next session."
                    )

                    taskInfoCard

                    rescheduleDetailCard

                    if let statusMessage = schedulingViewModel.statusMessage {
                        statusCard(text: statusMessage)
                    }

                    rescheduleActionButtons
                }
                .padding(.bottom, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        step = .completion
                    }
                    .foregroundColor(dynamicPrimaryColor)
                    .disabled(isScheduling)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        journalViewModel.skipJournalPrompt()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(isScheduling)
                }
            }
        }
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $showingCalendarPicker) {
            DraggableCalendarView(
                proposedStartTime: $proposedStartTime,
                proposedDuration: $proposedDuration,
                events: schedulingViewModel.calendarEvents,
                selectedDate: Calendar.current.startOfDay(for: proposedStartTime)
            )
        }
        .alert("Reschedule Issue", isPresented: Binding(
            get: { rescheduleError != nil },
            set: { isPresented in
                if !isPresented {
                    rescheduleError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                rescheduleError = nil
            }
        } message: {
            Text(rescheduleError ?? "Something went wrong while rescheduling.")
        }
    }

    private var taskInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session:")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Spacer()
                Text(pendingEvent.taskTitle)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(dynamicTextColor)
            }

            HStack {
                Text("Scheduled:")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Spacer()
                Text("\(timeFormatter.string(from: pendingEvent.scheduledStartTime)) - \(timeFormatter.string(from: pendingEvent.scheduledEndTime))")
                    .font(.caption)
                    .foregroundColor(dynamicTextColor)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func headerSection(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(dynamicPrimaryColor)

            Text(title)
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(dynamicSecondaryTextColor)
                .multilineTextAlignment(.center)

            if journalViewModel.pendingCount > 1 {
                Text("\(journalViewModel.pendingCount - 1) more reflection\(journalViewModel.pendingCount - 1 == 1 ? "" : "s") waiting")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .padding(.top, 4)
            }
        }
        .padding(.top, 20)
    }

    private func completionOptionButton(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(dynamicTextColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            .padding()
            .background(dynamicSecondaryBackgroundColor)
            .cornerRadius(12)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    private var rescheduleDetailCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New time")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            HStack {
                Text("Date")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Spacer()
                DatePicker(
                    "",
                    selection: proposedDateBinding,
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(dynamicPrimaryColor)
            }

            HStack {
                Text("Time")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Spacer()
                Text(CalendarTimeFormatter.formatTimeRange(start: proposedStartTime, end: proposedEndTime))
                    .font(.caption)
                    .foregroundColor(dynamicTextColor)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                DurationStepper(duration: $proposedDuration, minDuration: 15, maxDuration: 180, step: 5)
                Text("\(proposedDuration) min")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }

            Button(action: {
                showingCalendarPicker = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                    Text("Adjust on calendar")
                }
                .font(.caption)
                .foregroundColor(dynamicPrimaryColor)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var rescheduleActionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                scheduleRescheduledSession()
            }) {
                HStack {
                    if isScheduling {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text("Schedule Session")
                        Image(systemName: "calendar.badge.checkmark")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isScheduling ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                .cornerRadius(12)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isScheduling)

            Button(action: {
                journalViewModel.skipJournalPrompt()
            }) {
                Text("Skip")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            .disabled(isScheduling)
        }
        .padding(.horizontal)
    }

    private func statusCard(text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            Text(text)
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
            Spacer()
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var proposedDateBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.startOfDay(for: proposedStartTime)
            },
            set: { newDate in
                let calendar = Calendar.current
                let timeComponents = calendar.dateComponents([.hour, .minute], from: proposedStartTime)
                if let updatedStart = calendar.date(
                    bySettingHour: timeComponents.hour ?? 9,
                    minute: timeComponents.minute ?? 0,
                    second: 0,
                    of: newDate
                ) {
                    proposedStartTime = updatedStart
                }
            }
        )
    }

    private func scheduleRescheduledSession() {
        guard !isScheduling else { return }
        isScheduling = true
        rescheduleError = nil

        let endTime = proposedEndTime
        let tasks = taskTitles
        let title = buildSessionTitle(for: tasks)
        let originalRange = "\(timeFormatter.string(from: pendingEvent.scheduledStartTime)) - \(timeFormatter.string(from: pendingEvent.scheduledEndTime))"
        let rescheduleNote = "Rescheduled from \(dateFormatter.string(from: pendingEvent.scheduledStartTime)) at \(originalRange)."
        let tasksDescription = tasks.joined(separator: "\n• ")
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let fullDescription = "Tasks:\n• \(tasksDescription)\n\n\(rescheduleNote)\(scheduledTaskMarker)"

        calendarManager.createCalendarEvent(
            title: title,
            start: proposedStartTime,
            end: endTime,
            description: fullDescription
        ) { eventId, error in
            DispatchQueue.main.async {
                self.isScheduling = false
                
                if let error = error {
                    self.rescheduleError = error.localizedDescription
                    return
                }

                if let eventId = eventId {
                    self.firebaseManager.saveScheduledEvent(
                        eventId: eventId,
                        taskTitle: title,
                        tasks: tasks,
                        startTime: proposedStartTime,
                        endTime: endTime
                    ) { saveError in
                        if let saveError = saveError {
                            print("Error saving rescheduled event mapping: \(saveError.localizedDescription)")
                        } else {
                            NotificationManager.shared.scheduleJournalPromptNotification(
                                eventId: eventId,
                                taskTitle: title,
                                scheduledEndTime: endTime
                            )
                        }
                    }
                }

                self.journalViewModel.skipJournalPrompt()
            }
        }
    }

    private func buildSessionTitle(for tasks: [String]) -> String {
        switch tasks.count {
        case 0:
            return "Working Session"
        case 1:
            return tasks[0]
        case 2...3:
            return tasks.joined(separator: " & ")
        default:
            let maxTitleLength = 60
            let firstTwo = Array(tasks.prefix(2))
            var title = firstTwo.joined(separator: ", ")
            let remaining = tasks.count - 2
            let moreText = " & \(remaining) more"

            if title.count + moreText.count > maxTitleLength {
                title = firstTwo[0]
                let newRemaining = tasks.count - 1
                return "\(title) & \(newRemaining) more"
            }
            return title + moreText
        }
    }

    private func refreshCalendarIfNeeded(for date: Date) {
        let dayStart = Calendar.current.startOfDay(for: date)
        if let lastFetchedDate = lastFetchedDate,
           Calendar.current.isDate(dayStart, inSameDayAs: lastFetchedDate) {
            return
        }
        lastFetchedDate = dayStart
        schedulingViewModel.fetchCalendarEvents(for: dayStart)
    }

    private func resetFlow() {
        step = .completion
        selectedCompletionStatus = .completed
        proposedStartTime = pendingEvent.scheduledStartTime
        proposedDuration = max(15, Int(pendingEvent.scheduledEndTime.timeIntervalSince(pendingEvent.scheduledStartTime) / 60))
        showingCalendarPicker = false
        isScheduling = false
        rescheduleError = nil
        lastFetchedDate = nil
        schedulingViewModel.statusMessage = nil
    }
}
