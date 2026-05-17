//
//  JournalCompletionFlowView.swift
//  YourDay
//
//  Completion-first prompt that routes to journaling or rescheduling
//

import SwiftUI
import SwiftData

struct JournalCompletionFlowView: View {
    @ObservedObject var journalViewModel: JournalViewModel
    let pendingEvent: TaskEndMonitor.PendingJournalEvent

    @Environment(\.modelContext) private var modelContext

    @State private var step: FlowStep = .completion

    // Extend step
    @State private var extensionMinutes = 30
    @State private var isExtending = false
    @State private var extendError: String?

    // Green step
    @State private var greenWhatDid = ""
    @State private var isSavingGreen = false

    // Yellow step
    @State private var completedTaskIndices: Set<Int> = []
    @State private var partialWhatDid = ""
    @State private var partialWhatLeft = ""
    @State private var isSavingPartial = false
    // Stored partial data for "Save & Reschedule" path
    @State private var pendingPartialWhatDid = ""
    @State private var pendingPartialWhatLeft = ""
    @State private var hasPendingPartialSave = false

    // Reschedule step
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
        case extend
        case greenDetail
        case yellowDetail
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

    private var extendedEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: extensionMinutes, to: pendingEvent.scheduledEndTime) ?? pendingEvent.scheduledEndTime
    }

    var body: some View {
        Group {
            switch step {
            case .completion:
                completionView
            case .extend:
                extendView
            case .greenDetail:
                greenDetailView
            case .yellowDetail:
                yellowDetailView
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
            }
        }
        .onChange(of: proposedStartTime) { _, newValue in
            if step == .reschedule {
                refreshCalendarIfNeeded(for: newValue)
            }
        }
    }

    // MARK: - Completion screen

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
                        // "Still working on it" — extend time
                        Button {
                            step = .extend
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.badge.plus")
                                    .font(.system(size: 20))
                                    .foregroundColor(dynamicPrimaryColor)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Still working on it")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(dynamicTextColor)
                                    Text("Add more time and get another check-in")
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
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)

                        Text("What happened?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                            .padding(.horizontal)

                        completionOptionButton(
                            title: "Finished it!",
                            subtitle: "All done",
                            icon: "checkmark.circle.fill",
                            tint: .green
                        ) {
                            step = .greenDetail
                        }
                        .padding(.horizontal)

                        completionOptionButton(
                            title: "Partially done",
                            subtitle: "I made some progress",
                            icon: "circle.lefthalf.filled",
                            tint: .orange
                        ) {
                            step = .yellowDetail
                        }
                        .padding(.horizontal)

                        completionOptionButton(
                            title: "Didn't get to it",
                            subtitle: "Reschedule or skip",
                            icon: "arrow.uturn.left.circle.fill",
                            tint: .red
                        ) {
                            step = .reschedule
                        }
                        .padding(.horizontal)
                    }

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

    // MARK: - Extend time screen

    private var extendView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection(
                        icon: "clock.badge.plus",
                        title: "Add more time",
                        subtitle: "Extend your session and we'll check in again when you're done."
                    )

                    taskInfoCard

                    VStack(alignment: .leading, spacing: 16) {
                        Text("How much more time do you need?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        // Quick-pick pills
                        HStack(spacing: 10) {
                            ForEach([15, 30, 60, 120], id: \.self) { mins in
                                Button {
                                    extensionMinutes = mins
                                } label: {
                                    Text(mins < 60 ? "+\(mins) min" : "+\(mins / 60) hr")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(extensionMinutes == mins ? .white : dynamicPrimaryColor)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule().fill(extensionMinutes == mins
                                                ? dynamicPrimaryColor
                                                : dynamicPrimaryColor.opacity(0.12))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        HStack {
                            Text("New end time:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Text(timeFormatter.string(from: extendedEndTime))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(dynamicTextColor)
                        }

                        if let err = extendError {
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Button(action: extendTask) {
                            HStack {
                                if isExtending {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "clock.badge.checkmark")
                                    Text("Extend Session")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(isExtending ? Color.gray : dynamicPrimaryColor)
                            .cornerRadius(10)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isExtending)
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { step = .completion }
                        .foregroundColor(dynamicPrimaryColor)
                        .disabled(isExtending)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { journalViewModel.skipJournalPrompt() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(isExtending)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Green (completed) detail screen

    private var greenDetailView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Great work!")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        Text("Anything worth noting about this session?")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                        if journalViewModel.pendingCount > 1 {
                            Text("\(journalViewModel.pendingCount - 1) more reflection\(journalViewModel.pendingCount - 1 == 1 ? "" : "s") waiting")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                    .padding(.top, 20)

                    taskInfoCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("What did you do? (optional)")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        AppTextField(placeholder: "Briefly describe what you worked on…", text: $greenWhatDid, axis: .vertical, lineLimit: 3...6)
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button(action: saveGreenEntry) {
                            HStack {
                                if isSavingGreen || journalViewModel.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "checkmark")
                                    Text("Done")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.green)
                            .cornerRadius(10)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isSavingGreen || journalViewModel.isLoading)
                        .padding(.horizontal)

                        Button(action: { journalViewModel.skipJournalPrompt() }) {
                            Text("Skip")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        .disabled(isSavingGreen || journalViewModel.isLoading)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { step = .completion }
                        .foregroundColor(dynamicPrimaryColor)
                        .disabled(isSavingGreen || journalViewModel.isLoading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { journalViewModel.skipJournalPrompt() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(isSavingGreen || journalViewModel.isLoading)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Yellow (partial) detail screen

    private var yellowDetailView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("What did you get done?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        Text("Check off what you completed and note what's left.")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                        if journalViewModel.pendingCount > 1 {
                            Text("\(journalViewModel.pendingCount - 1) more reflection\(journalViewModel.pendingCount - 1 == 1 ? "" : "s") waiting")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                    .padding(.top, 20)

                    taskInfoCard

                    // Subtask checklist (if multiple tasks on this event)
                    if taskTitles.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What did you complete?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            ForEach(Array(taskTitles.enumerated()), id: \.offset) { index, title in
                                Button {
                                    if completedTaskIndices.contains(index) {
                                        completedTaskIndices.remove(index)
                                    } else {
                                        completedTaskIndices.insert(index)
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: completedTaskIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(completedTaskIndices.contains(index) ? .green : dynamicSecondaryTextColor)
                                        Text(title)
                                            .font(.subheadline)
                                            .foregroundColor(dynamicTextColor)
                                            .multilineTextAlignment(.leading)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                                if index < taskTitles.count - 1 {
                                    Divider()
                                }
                            }
                        }
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Optional text fields
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What did you finish? (optional)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "Describe what you accomplished…", text: $partialWhatDid, axis: .vertical, lineLimit: 2...4)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What's still left? (optional)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "Describe what remains to be done…", text: $partialWhatLeft, axis: .vertical, lineLimit: 2...4)
                        }
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Action buttons
                    VStack(spacing: 10) {
                        Button(action: { saveAndReschedulePartial() }) {
                            HStack {
                                if isSavingPartial {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "calendar.badge.clock")
                                    Text("Save & Reschedule Remaining")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(dynamicPrimaryColor)
                            .cornerRadius(10)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isSavingPartial || journalViewModel.isLoading)
                        .padding(.horizontal)

                        Button(action: { savePartialEntry() }) {
                            Text(isSavingPartial || journalViewModel.isLoading ? "Saving…" : "Save & Done")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(dynamicPrimaryColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSavingPartial || journalViewModel.isLoading)
                        .padding(.horizontal)

                        Button(action: { journalViewModel.skipJournalPrompt() }) {
                            Text("Skip")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        .disabled(isSavingPartial || journalViewModel.isLoading)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { step = .completion }
                        .foregroundColor(dynamicPrimaryColor)
                        .disabled(isSavingPartial || journalViewModel.isLoading)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { journalViewModel.skipJournalPrompt() }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .disabled(isSavingPartial || journalViewModel.isLoading)
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - Reschedule screen

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
                        step = hasPendingPartialSave ? .yellowDetail : .completion
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
            set: { if !$0 { rescheduleError = nil } }
        )) {
            Button("OK", role: .cancel) { rescheduleError = nil }
        } message: {
            Text(rescheduleError ?? "Something went wrong while rescheduling.")
        }
    }

    // MARK: - Shared subviews

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

    // MARK: - Actions

    private func extendTask() {
        guard !isExtending else { return }
        isExtending = true
        extendError = nil

        let newEnd = extendedEndTime
        let originalEventId = pendingEvent.eventId
        let originalStart = pendingEvent.scheduledStartTime

        calendarManager.ensureCalendarWriteAccess { accessResult in
            DispatchQueue.main.async {
                switch accessResult {
                case .failure(let err):
                    self.isExtending = false
                    self.extendError = err.localizedDescription
                case .success:
                    self.calendarManager.updateCalendarEvent(
                        eventId: originalEventId,
                        title: self.pendingEvent.taskTitle,
                        start: originalStart,
                        end: newEnd
                    ) { _, error in
                        DispatchQueue.main.async {
                            self.isExtending = false
                            if let error = error {
                                self.extendError = error.localizedDescription
                                return
                            }
                            // Update linked TodoItems in SwiftData so TaskEndMonitor uses new end time
                            let descriptor = FetchDescriptor<TodoItem>()
                            if let allItems = try? self.modelContext.fetch(descriptor) {
                                let linked = allItems.filter {
                                    $0.manualScheduleGoogleEventId?.trimmingCharacters(in: .whitespacesAndNewlines) == originalEventId
                                }
                                linked.forEach { $0.scheduledEndTime = newEnd }
                                try? self.modelContext.save()
                            }
                            // Update Firestore so TaskEndMonitor re-prompts at the new end time
                            self.firebaseManager.updateScheduledEvent(eventId: originalEventId, endTime: newEnd) { err in
                                if let err = err {
                                    print("JournalCompletionFlowView: Failed to update scheduledEvent endTime: \(err.localizedDescription)")
                                }
                            }
                            NotificationManager.shared.cancelJournalPromptNotification(eventId: originalEventId)
                            NotificationManager.shared.cancelPreTaskNotification(eventId: originalEventId)
                            NotificationManager.shared.scheduleJournalPromptNotification(
                                eventId: originalEventId,
                                taskTitle: self.pendingEvent.taskTitle,
                                scheduledEndTime: newEnd
                            )
                            self.journalViewModel.dismissJournalPromptForExtension()
                        }
                    }
                }
            }
        }
    }

    private func saveGreenEntry() {
        isSavingGreen = true
        journalViewModel.saveJournalEntry(
            eventId: pendingEvent.eventId,
            taskTitle: pendingEvent.taskTitle,
            scheduledStartTime: pendingEvent.scheduledStartTime,
            scheduledEndTime: pendingEvent.scheduledEndTime,
            actualStartTime: nil,
            actualEndTime: nil,
            whatDid: greenWhatDid,
            howWent: nil,
            learned: nil,
            distractions: nil,
            completionStatus: .completed
        )
        isSavingGreen = false
    }

    private func buildPartialWhatDid() -> String {
        var parts: [String] = []
        if !completedTaskIndices.isEmpty && taskTitles.count > 1 {
            let completedNames = completedTaskIndices.sorted().map { taskTitles[$0] }
            parts.append("Completed: \(completedNames.joined(separator: ", "))")
        }
        let typed = partialWhatDid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            parts.append(typed)
        }
        return parts.joined(separator: ". ")
    }

    private func savePartialEntry() {
        journalViewModel.saveJournalEntry(
            eventId: pendingEvent.eventId,
            taskTitle: pendingEvent.taskTitle,
            scheduledStartTime: pendingEvent.scheduledStartTime,
            scheduledEndTime: pendingEvent.scheduledEndTime,
            actualStartTime: nil,
            actualEndTime: nil,
            whatDid: buildPartialWhatDid(),
            howWent: partialWhatLeft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : partialWhatLeft,
            learned: nil,
            distractions: nil,
            completionStatus: .partial
        )
    }

    private func saveAndReschedulePartial() {
        // Store partial data; journal entry will be saved in finishSuccess after reschedule
        pendingPartialWhatDid = buildPartialWhatDid()
        pendingPartialWhatLeft = partialWhatLeft.trimmingCharacters(in: .whitespacesAndNewlines)
        hasPendingPartialSave = true
        step = .reschedule
    }

    // MARK: - Reschedule logic

    private func scheduleRescheduledSession() {
        guard !isScheduling else { return }
        isScheduling = true
        rescheduleError = nil

        let start = proposedStartTime
        let end = proposedEndTime
        let tasks = taskTitles
        let title = buildSessionTitle(for: tasks)
        let originalRange = "\(timeFormatter.string(from: pendingEvent.scheduledStartTime)) - \(timeFormatter.string(from: pendingEvent.scheduledEndTime))"
        let rescheduleNote = "Rescheduled from \(dateFormatter.string(from: pendingEvent.scheduledStartTime)) at \(originalRange)."
        let tasksDescription = tasks.joined(separator: "\n• ")
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let fullDescription = "Tasks:\n• \(tasksDescription)\n\n\(rescheduleNote)\(scheduledTaskMarker)"

        let originalEventId = pendingEvent.eventId

        func finishSuccess(eventId: String) {
            firebaseManager.saveScheduledEvent(
                eventId: eventId,
                taskTitle: title,
                tasks: tasks,
                startTime: start,
                endTime: end
            ) { saveError in
                DispatchQueue.main.async {
                    self.isScheduling = false

                    if let saveError = saveError {
                        print("Error saving rescheduled event mapping: \(saveError.localizedDescription)")
                    }

                    if eventId != originalEventId && !originalEventId.isEmpty {
                        NotificationManager.shared.cancelJournalPromptNotification(eventId: originalEventId)
                        NotificationManager.shared.cancelPreTaskNotification(eventId: originalEventId)
                    }

                    NotificationManager.shared.scheduleJournalPromptNotification(
                        eventId: eventId,
                        taskTitle: title,
                        scheduledEndTime: end
                    )
                    NotificationManager.shared.schedulePreTaskNotification(
                        eventId: eventId,
                        taskTitle: title,
                        scheduledStartTime: start
                    )

                    // If we came from "Save & Reschedule" in the partial flow, save the journal entry
                    if self.hasPendingPartialSave {
                        self.journalViewModel.saveJournalEntry(
                            eventId: originalEventId,
                            taskTitle: self.pendingEvent.taskTitle,
                            scheduledStartTime: self.pendingEvent.scheduledStartTime,
                            scheduledEndTime: self.pendingEvent.scheduledEndTime,
                            actualStartTime: nil,
                            actualEndTime: nil,
                            whatDid: self.pendingPartialWhatDid,
                            howWent: self.pendingPartialWhatLeft.isEmpty ? nil : self.pendingPartialWhatLeft,
                            learned: nil,
                            distractions: nil,
                            completionStatus: .partial
                        )
                    }

                    self.journalViewModel.skipJournalPrompt()
                }
            }
        }

        func handleCreate() {
            calendarManager.createCalendarEvent(
                title: title,
                start: start,
                end: end,
                description: fullDescription
            ) { eventId, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.isScheduling = false
                        self.rescheduleError = error.localizedDescription
                        return
                    }
                    guard let eventId = eventId, !eventId.isEmpty else {
                        self.isScheduling = false
                        self.rescheduleError = "Could not confirm the calendar event."
                        return
                    }
                    finishSuccess(eventId: eventId)
                }
            }
        }

        func handleUpdate(existingId: String) {
            calendarManager.updateCalendarEvent(
                eventId: existingId,
                title: title,
                start: start,
                end: end,
                description: fullDescription
            ) { returnedId, error in
                DispatchQueue.main.async {
                    if let error = error {
                        let ns = error as NSError
                        if ns.code == 404 || ns.code == 410 {
                            handleCreate()
                            return
                        }
                        self.isScheduling = false
                        self.rescheduleError = error.localizedDescription
                        return
                    }
                    guard let eventId = returnedId, !eventId.isEmpty else {
                        self.isScheduling = false
                        self.rescheduleError = "Could not confirm the calendar event."
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
                    self.isScheduling = false
                    self.rescheduleError = err.localizedDescription
                case .success:
                    if !originalEventId.isEmpty {
                        handleUpdate(existingId: originalEventId)
                    } else {
                        handleCreate()
                    }
                }
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
        extensionMinutes = 30
        isExtending = false
        extendError = nil
        greenWhatDid = ""
        isSavingGreen = false
        completedTaskIndices = []
        partialWhatDid = ""
        partialWhatLeft = ""
        isSavingPartial = false
        pendingPartialWhatDid = ""
        pendingPartialWhatLeft = ""
        hasPendingPartialSave = false
        proposedStartTime = pendingEvent.scheduledStartTime
        proposedDuration = max(15, Int(pendingEvent.scheduledEndTime.timeIntervalSince(pendingEvent.scheduledStartTime) / 60))
        showingCalendarPicker = false
        isScheduling = false
        rescheduleError = nil
        lastFetchedDate = nil
        schedulingViewModel.statusMessage = nil
    }
}
