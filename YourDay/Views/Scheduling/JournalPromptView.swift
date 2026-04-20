//
//  JournalPromptView.swift
//  YourDay
//
//  Modal view for journaling after a task ends
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct JournalPromptView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\TodoItem.position)]) private var allTodoItems: [TodoItem]

    @ObservedObject var journalViewModel: JournalViewModel
    let pendingEvent: TaskEndMonitor.PendingJournalEvent

    @State private var whatDid: String = ""
    @State private var whatRemains: String = ""
    @State private var howWent: String = ""
    @State private var learned: String = ""
    @State private var distractions: String = ""
    @State private var completionStatus: CompletionStatus
    @State private var actualStartTime: Date?
    @State private var actualEndTime: Date?
    @State private var showTimeAdjustment = false

    @State private var completedSubtaskKeys: Set<SubtaskSelectionKey> = []
    @State private var didInitializeSubtaskState = false

    @State private var remainingAction: RemainingAction = .skip
    @State private var rescheduleTime: Date = Date()

    @FocusState private var focusedField: Field?

    private let calendarManager = GoogleCalendarManager.shared
    private let firebaseManager = FirebaseManager.shared

    private enum RemainingAction: String, CaseIterable {
        case skip
        case rescheduleLaterToday
    }

    private struct SubtaskSelectionKey: Hashable {
        let taskId: String
        let subtaskId: UUID
    }

    enum Field {
        case whatDid, whatRemains, howWent, learned, distractions
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

    private var resolvedActualStartTime: Date? {
        showTimeAdjustment ? (actualStartTime ?? pendingEvent.scheduledStartTime) : nil
    }

    private var resolvedActualEndTime: Date? {
        showTimeAdjustment ? (actualEndTime ?? pendingEvent.scheduledEndTime) : nil
    }

    private var isTimeValid: Bool {
        guard showTimeAdjustment else { return true }
        guard let start = resolvedActualStartTime, let end = resolvedActualEndTime else { return true }
        return end >= start
    }

    private var trimmedWhatDid: String {
        whatDid.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedWhatRemains: String {
        whatRemains.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSaveDisabled: Bool {
        if trimmedWhatDid.isEmpty || journalViewModel.isLoading || !isTimeValid {
            return true
        }
        if completionStatus == .partial && trimmedWhatRemains.isEmpty {
            return true
        }
        return false
    }

    private var scheduledTaskTitles: [String] {
        var titles = pendingEvent.tasks.isEmpty ? [pendingEvent.taskTitle] : pendingEvent.tasks
        if !titles.contains(pendingEvent.taskTitle) {
            titles.append(pendingEvent.taskTitle)
        }
        return titles
    }

    private var matchedTaskIndices: [Int] {
        let normalizedScheduledTitles = Set(scheduledTaskTitles.map(normalizedTitle))
        return allTodoItems.indices.filter { index in
            let itemTitle = normalizedTitle(allTodoItems[index].title)
            return normalizedScheduledTitles.contains(itemTitle)
        }
    }

    private var hasMatchedSubtasks: Bool {
        matchedTaskIndices.contains { !allTodoItems[$0].subtasks.isEmpty }
    }

    private var journalWhatDidText: String {
        if completionStatus == .partial {
            return """
            Completed:
            \(trimmedWhatDid)

            Remaining:
            \(trimmedWhatRemains)
            """
        }
        return trimmedWhatDid
    }

    init(
        journalViewModel: JournalViewModel,
        pendingEvent: TaskEndMonitor.PendingJournalEvent,
        initialCompletionStatus: CompletionStatus = .completed
    ) {
        self.journalViewModel = journalViewModel
        self.pendingEvent = pendingEvent
        _completionStatus = State(initialValue: initialCompletionStatus)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 40))
                            .foregroundColor(dynamicPrimaryColor)

                        Text("How did it go?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        Text("Your task session just ended. Let's reflect!")
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

                    Toggle("Adjust actual times", isOn: $showTimeAdjustment)
                        .padding(.horizontal)
                        .foregroundColor(dynamicTextColor)

                    if showTimeAdjustment {
                        VStack(spacing: 12) {
                            DatePicker("Actual start time", selection: Binding(
                                get: { actualStartTime ?? pendingEvent.scheduledStartTime },
                                set: { actualStartTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .padding(.horizontal)

                            DatePicker("Actual end time", selection: Binding(
                                get: { actualEndTime ?? pendingEvent.scheduledEndTime },
                                set: { actualEndTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .padding(.horizontal)

                            if !isTimeValid {
                                Text("Actual end time must be after the start time.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    if completionStatus == .partial {
                        requiredMultilineInput(
                            title: "What did you complete?",
                            placeholder: "Describe what you completed in this session...",
                            text: $whatDid,
                            field: .whatDid
                        )
                        requiredMultilineInput(
                            title: "What remains to be completed?",
                            placeholder: "Describe what is still left...",
                            text: $whatRemains,
                            field: .whatRemains
                        )
                        partialSubtaskChecklistSection
                        partialRemainingActionSection
                    } else {
                        requiredMultilineInput(
                            title: "What did you do?",
                            placeholder: "Describe what you accomplished...",
                            text: $whatDid,
                            field: .whatDid
                        )
                    }

                    optionalMultilineInput(
                        title: "How did it go?",
                        placeholder: "Satisfaction, challenges, feelings...",
                        text: $howWent,
                        field: .howWent
                    )
                    optionalMultilineInput(
                        title: "What did you learn?",
                        placeholder: "Insights, discoveries, patterns...",
                        text: $learned,
                        field: .learned
                    )
                    optionalMultilineInput(
                        title: "Distractions or interruptions?",
                        placeholder: "What interrupted your focus...",
                        text: $distractions,
                        field: .distractions
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completion Status")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)

                        HStack(spacing: 0) {
                            completionPill(title: "Completed", status: .completed)
                            completionPill(title: "Partial", status: .partial)
                            completionPill(title: "Not Started", status: .notStarted)
                        }
                        .padding(4)
                        .background(Capsule().fill(Color.black.opacity(0.06)))
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button(action: {
                            saveEntry()
                        }) {
                            HStack {
                                if journalViewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Save Journal Entry")
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isSaveDisabled ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(isSaveDisabled)

                        Button(action: {
                            journalViewModel.skipJournalPrompt()
                        }) {
                            Text("Skip")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        .disabled(journalViewModel.isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
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
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            if !didInitializeSubtaskState {
                didInitializeSubtaskState = true
                initializeSubtaskSelection()
            }
            if remainingAction == .skip {
                rescheduleTime = defaultRescheduleTime()
            }
        }
        .onChange(of: completionStatus) { _, newStatus in
            if newStatus == .partial && !didInitializeSubtaskState {
                didInitializeSubtaskState = true
                initializeSubtaskSelection()
            }
        }
        .alert("Couldn't Save Entry", isPresented: Binding(
            get: { journalViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    journalViewModel.clearError()
                }
            }
        )) {
            Button("OK", role: .cancel) {
                journalViewModel.clearError()
            }
        } message: {
            Text(journalViewModel.errorMessage ?? "Something went wrong.")
        }
    }

    private func requiredMultilineInput(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(dynamicTextColor)
                + Text(" *")
                .foregroundColor(.red)

            AppTextField(placeholder: placeholder, text: text, axis: .vertical, lineLimit: 3...6)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal)
    }

    private func optionalMultilineInput(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(dynamicTextColor)

            AppTextField(placeholder: placeholder, text: text, axis: .vertical, lineLimit: 2...4)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .focused($focusedField, equals: field)
        }
        .padding(.horizontal)
    }

    private var partialSubtaskChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check off completed subtasks")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(dynamicTextColor)

            if hasMatchedSubtasks {
                ForEach(matchedTaskIndices, id: \.self) { index in
                    let task = allTodoItems[index]
                    if !task.subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(dynamicSecondaryTextColor)

                            ForEach(task.subtasks) { subtask in
                                Button(action: {
                                    toggleSubtaskSelection(taskId: task.localTaskId, subtaskId: subtask.id)
                                }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: isSelected(taskId: task.localTaskId, subtaskId: subtask.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected(taskId: task.localTaskId, subtaskId: subtask.id) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                                        Text(subtask.title)
                                            .font(.subheadline)
                                            .foregroundColor(dynamicTextColor)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                Text("No matching subtasks found for this session. You can still describe completed vs remaining work.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var partialRemainingActionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remaining work")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(dynamicTextColor)

            VStack(spacing: 8) {
                remainingActionButton(
                    title: "Skip remaining for now",
                    subtitle: "No follow-up session will be created",
                    action: .skip
                )
                remainingActionButton(
                    title: "Reschedule for later today",
                    subtitle: "Create a new scheduled session for remaining work",
                    action: .rescheduleLaterToday
                )
            }

            if remainingAction == .rescheduleLaterToday {
                DatePicker(
                    "Reschedule time",
                    selection: $rescheduleTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)
                .tint(dynamicPrimaryColor)

                Text("This will schedule a new session on \(dateFormatter.string(from: Date())).")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func remainingActionButton(title: String, subtitle: String, action: RemainingAction) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                remainingAction = action
                if action == .rescheduleLaterToday {
                    rescheduleTime = defaultRescheduleTime()
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: remainingAction == action ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(remainingAction == action ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(dynamicTextColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                Spacer()
            }
            .padding(10)
            .background(dynamicBackgroundColor.opacity(0.6))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func completionPill(title: String, status: CompletionStatus) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { completionStatus = status }
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundColor(completionStatus == status ? .white : .black.opacity(0.65))
                .background(completionStatus == status ? dynamicPrimaryColor : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func saveEntry() {
        guard isTimeValid else {
            journalViewModel.errorMessage = "Actual end time must be after the start time."
            return
        }
        guard validatePartialRescheduleSelection() else {
            return
        }

        journalViewModel.saveJournalEntry(
            eventId: pendingEvent.eventId,
            taskTitle: pendingEvent.taskTitle,
            scheduledStartTime: pendingEvent.scheduledStartTime,
            scheduledEndTime: pendingEvent.scheduledEndTime,
            actualStartTime: resolvedActualStartTime,
            actualEndTime: resolvedActualEndTime,
            whatDid: journalWhatDidText,
            howWent: howWent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : howWent,
            learned: learned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : learned,
            distractions: distractions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : distractions,
            completionStatus: completionStatus,
            onSaveSuccess: {
                applyTaskProgressUpdates()
                if completionStatus == .partial && remainingAction == .rescheduleLaterToday {
                    scheduleRemainingWorkForLaterToday()
                }
            }
        )
    }

    private func validatePartialRescheduleSelection() -> Bool {
        guard completionStatus == .partial, remainingAction == .rescheduleLaterToday else {
            return true
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let selectedComponents = calendar.dateComponents([.hour, .minute], from: rescheduleTime)

        guard let startTime = calendar.date(
            bySettingHour: selectedComponents.hour ?? 0,
            minute: selectedComponents.minute ?? 0,
            second: 0,
            of: today
        ) else {
            journalViewModel.errorMessage = "Choose a valid time for rescheduling."
            return false
        }

        if startTime <= now {
            journalViewModel.errorMessage = "Choose a later time today for rescheduling remaining work."
            return false
        }

        let sessionDuration = max(
            15,
            Int(pendingEvent.scheduledEndTime.timeIntervalSince(pendingEvent.scheduledStartTime) / 60)
        )
        let endTime = calendar.date(byAdding: .minute, value: sessionDuration, to: startTime) ?? startTime.addingTimeInterval(3600)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: today) ?? endTime
        if endTime > endOfDay {
            journalViewModel.errorMessage = "The selected time would run past midnight. Choose an earlier time."
            return false
        }

        return true
    }

    private func applyTaskProgressUpdates() {
        guard !matchedTaskIndices.isEmpty else { return }

        switch completionStatus {
        case .completed:
            markMatchedTasksCompleted()
        case .partial:
            applyPartialSubtaskSelection()
        case .notStarted:
            return
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save task updates from journal check-in: \(error.localizedDescription)")
        }

        NotificationManager.shared.rescheduleIfNeeded(context: modelContext)
    }

    private func markMatchedTasksCompleted() {
        let completionTime = resolvedActualEndTime ?? Date()

        for index in matchedTaskIndices {
            let task = allTodoItems[index]
            task.isDone = true
            task.completedAt = completionTime

            for subtaskIndex in task.subtasks.indices {
                task.subtasks[subtaskIndex].isDone = true
                task.subtasks[subtaskIndex].completedAt = completionTime
            }

            syncTaskToFirebase(task)
        }
    }

    private func applyPartialSubtaskSelection() {
        let completionTime = resolvedActualEndTime ?? Date()

        for index in matchedTaskIndices {
            let task = allTodoItems[index]
            guard !task.subtasks.isEmpty else { continue }

            for subtaskIndex in task.subtasks.indices {
                let subtaskId = task.subtasks[subtaskIndex].id
                let key = SubtaskSelectionKey(taskId: task.localTaskId, subtaskId: subtaskId)
                let shouldBeDone = completedSubtaskKeys.contains(key)

                task.subtasks[subtaskIndex].isDone = shouldBeDone
                task.subtasks[subtaskIndex].completedAt = shouldBeDone ? completionTime : nil
            }

            let taskCompleted = task.subtasks.allSatisfy(\.isDone)
            task.isDone = taskCompleted
            task.completedAt = taskCompleted ? completionTime : nil

            syncTaskToFirebase(task)
        }
    }

    private func syncTaskToFirebase(_ task: TodoItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let codableTask = TodoItemCodable(from: task, userId: userId)
        firebaseManager.saveTodoItem(codableTask) { error in
            if let error = error {
                print("JournalPromptView: Failed to sync task '\(task.title)' to Firebase: \(error.localizedDescription)")
            }
        }

        if task.sharedTaskId != nil {
            firebaseManager.syncLocalTaskToSharedTask(localTask: task) { error in
                if let error = error {
                    print("JournalPromptView: Failed to sync shared task '\(task.title)': \(error.localizedDescription)")
                }
            }
        }
    }

    private func scheduleRemainingWorkForLaterToday() {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let selectedComponents = calendar.dateComponents([.hour, .minute], from: rescheduleTime)
        guard let startTime = calendar.date(
            bySettingHour: selectedComponents.hour ?? 0,
            minute: selectedComponents.minute ?? 0,
            second: 0,
            of: today
        ) else {
            return
        }

        if startTime <= now {
            journalViewModel.errorMessage = "Choose a later time today for rescheduling remaining work."
            return
        }

        let sessionDuration = max(
            15,
            Int(pendingEvent.scheduledEndTime.timeIntervalSince(pendingEvent.scheduledStartTime) / 60)
        )
        let endTime = calendar.date(byAdding: .minute, value: sessionDuration, to: startTime) ?? startTime.addingTimeInterval(3600)
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: today) ?? endTime
        if endTime > endOfDay {
            journalViewModel.errorMessage = "The selected time would run past midnight. Choose an earlier time."
            return
        }

        let remainingTasks = parsedRemainingTasks()
        let title = buildSessionTitle(for: remainingTasks)
        let originalRange = "\(timeFormatter.string(from: pendingEvent.scheduledStartTime)) - \(timeFormatter.string(from: pendingEvent.scheduledEndTime))"
        let rescheduleNote = "Rescheduled remaining work from \(dateFormatter.string(from: pendingEvent.scheduledStartTime)) at \(originalRange)."
        let tasksDescription = remainingTasks.joined(separator: "\n• ")
        let scheduledTaskMarker = "\n\n[YourDay Scheduled Task]"
        let fullDescription = "Remaining Tasks:\n• \(tasksDescription)\n\n\(rescheduleNote)\(scheduledTaskMarker)"

        calendarManager.createCalendarEvent(
            title: title,
            start: startTime,
            end: endTime,
            description: fullDescription
        ) { eventId, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("JournalPromptView: Failed to create remaining-work event: \(error.localizedDescription)")
                    return
                }

                guard let eventId = eventId else { return }
                self.firebaseManager.saveScheduledEvent(
                    eventId: eventId,
                    taskTitle: title,
                    tasks: remainingTasks,
                    startTime: startTime,
                    endTime: endTime
                ) { saveError in
                    if let saveError = saveError {
                        print("JournalPromptView: Failed to save remaining-work mapping: \(saveError.localizedDescription)")
                    } else {
                        NotificationManager.shared.scheduleJournalPromptNotification(
                            eventId: eventId,
                            taskTitle: title,
                            scheduledEndTime: endTime
                        )
                    }
                }
            }
        }
    }

    private func parsedRemainingTasks() -> [String] {
        var tasks: [String] = []

        let splitLines = trimmedWhatRemains
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { line in
                line
                    .replacingOccurrences(of: "•", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        tasks.append(contentsOf: splitLines)

        for index in matchedTaskIndices {
            let task = allTodoItems[index]
            for subtask in task.subtasks {
                let key = SubtaskSelectionKey(taskId: task.localTaskId, subtaskId: subtask.id)
                if !completedSubtaskKeys.contains(key), !subtask.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tasks.append(subtask.title.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        if tasks.isEmpty {
            tasks = ["\(pendingEvent.taskTitle) (remaining work)"]
        }

        var uniqueTasks: [String] = []
        var seen = Set<String>()
        for task in tasks {
            let normalized = normalizedTitle(task)
            if seen.insert(normalized).inserted {
                uniqueTasks.append(task)
            }
        }
        return uniqueTasks
    }

    private func buildSessionTitle(for tasks: [String]) -> String {
        switch tasks.count {
        case 0:
            return "Remaining Work Session"
        case 1:
            return "\(tasks[0]) (Remaining)"
        case 2...3:
            return "\(tasks.joined(separator: " & ")) (Remaining)"
        default:
            let maxTitleLength = 60
            let firstTwo = Array(tasks.prefix(2))
            var title = firstTwo.joined(separator: ", ")
            let remainingCount = tasks.count - 2
            let moreText = " & \(remainingCount) more"

            if title.count + moreText.count > maxTitleLength {
                title = firstTwo[0]
                let adjustedRemaining = tasks.count - 1
                return "\(title) & \(adjustedRemaining) more (Remaining)"
            }
            return "\(title)\(moreText) (Remaining)"
        }
    }

    private func defaultRescheduleTime() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: now)
        let minutesToNextQuarter = 15 - (minute % 15)
        let roundedUp = calendar.date(byAdding: .minute, value: minutesToNextQuarter, to: now) ?? now
        return calendar.date(byAdding: .minute, value: 30, to: roundedUp) ?? roundedUp
    }

    private func initializeSubtaskSelection() {
        completedSubtaskKeys.removeAll()

        for index in matchedTaskIndices {
            let task = allTodoItems[index]
            for subtask in task.subtasks where subtask.isDone {
                completedSubtaskKeys.insert(SubtaskSelectionKey(taskId: task.localTaskId, subtaskId: subtask.id))
            }
        }
    }

    private func toggleSubtaskSelection(taskId: String, subtaskId: UUID) {
        let key = SubtaskSelectionKey(taskId: taskId, subtaskId: subtaskId)
        if completedSubtaskKeys.contains(key) {
            completedSubtaskKeys.remove(key)
        } else {
            completedSubtaskKeys.insert(key)
        }
    }

    private func isSelected(taskId: String, subtaskId: UUID) -> Bool {
        completedSubtaskKeys.contains(SubtaskSelectionKey(taskId: taskId, subtaskId: subtaskId))
    }

    private func normalizedTitle(_ rawTitle: String) -> String {
        let collapsedWhitespace = rawTitle
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsedWhitespace.lowercased()
    }
}
