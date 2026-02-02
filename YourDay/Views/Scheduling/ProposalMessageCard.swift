//
//  ProposalMessageCard.swift
//  YourDay
//
//  Proposal card displayed as a message in the chat
//

import SwiftUI

struct ProposalMessageCard: View {
    @Binding var proposal: ProposedSession
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @ObservedObject var backlogViewModel: BacklogViewModel
    let onAccept: ([String]) -> Void
    let onRequestModificationReason: (ModificationContext) -> Void
    let isDisabled: Bool
    let maxWidth: CGFloat

    @State private var selectedStartTime: Date
    @State private var adjustedDuration: Int
    @State private var showingCalendarView = false
    @State private var showingAddTaskSheet = false
    @State private var addedTaskTitles: Set<String> = [] // Track tasks added by user
    @State private var showingModificationReasonPopup = false
    @State private var modificationReason = ""
    @State private var pendingAcceptTasks: [String] = [] // Tasks to mark as accepted after reason submitted
    @State private var pendingOriginalTime = "" // Captured original time for popup
    @State private var pendingModifiedTime = "" // Captured modified time for popup
    @State private var originalTasks: [String]
    @State private var appeared = false

    init(
        proposal: Binding<ProposedSession>,
        schedulingViewModel: SchedulingAssistantViewModel,
        backlogViewModel: BacklogViewModel,
        onAccept: @escaping ([String]) -> Void,
        onRequestModificationReason: @escaping (ModificationContext) -> Void,
        isDisabled: Bool = false,
        maxWidth: CGFloat = 320
    ) {
        self._proposal = proposal
        self.schedulingViewModel = schedulingViewModel
        self.backlogViewModel = backlogViewModel
        self.onAccept = onAccept
        self.onRequestModificationReason = onRequestModificationReason
        self.isDisabled = isDisabled
        self.maxWidth = maxWidth

        // Initialize state from proposal
        let initialStart = proposal.wrappedValue.effectiveStartTime ?? proposal.wrappedValue.startTime ?? Date()
        // Calculate duration from task estimates if available, otherwise use proposal duration
        let taskDurations = proposal.wrappedValue.taskDetails?.compactMap { $0.estimatedDuration } ?? []
        let calculatedDuration = taskDurations.isEmpty ? (proposal.wrappedValue.effectiveDuration ?? 60) : max(15, Int(Double(taskDurations.reduce(0, +)) * 1.1))
        let initialDuration = proposal.wrappedValue.effectiveDuration ?? calculatedDuration
        _selectedStartTime = State(initialValue: initialStart)
        _adjustedDuration = State(initialValue: initialDuration)
        _originalTasks = State(initialValue: proposal.wrappedValue.tasks)
    }

    // Backlog items that are not already in the proposal
    private var availableBacklogItems: [UnifiedBacklogItem] {
        backlogViewModel.backlogItems.filter { item in
            !proposal.tasks.contains(item.title)
        }
    }
    
    // Calculate total estimated duration from all tasks
    private var totalEstimatedDuration: Int {
        let durations = proposal.taskDetails?.compactMap { $0.estimatedDuration } ?? []
        let total = durations.reduce(0, +)
        // Add 10% buffer for transitions/breaks, minimum 15 minutes
        return max(15, Int(Double(total) * 1.1))
    }
    
    // Check if current duration matches task estimates
    private var durationMatchesEstimates: Bool {
        let estimated = totalEstimatedDuration
        // Allow 5 minute tolerance
        return abs(adjustedDuration - estimated) <= 5
    }

    private var hasModifications: Bool {
        let tasksChanged = Set(originalTasks) != Set(proposal.tasks)

        guard let originalStart = proposal.startTime else { return false }
        let originalDuration = proposal.effectiveDuration ?? 60

        let calendar = Calendar.current
        let startChanged = !calendar.isDate(selectedStartTime, equalTo: originalStart, toGranularity: .minute)
        let durationChanged = adjustedDuration != originalDuration

        return tasksChanged || startChanged || durationChanged
    }

    private var effectiveEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: adjustedDuration, to: selectedStartTime) ?? selectedStartTime
    }

    private var timeRangeString: String {
        CalendarTimeFormatter.formatTimeRange(start: selectedStartTime, end: effectiveEndTime)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Working Session")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            Divider()

            // Tasks Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(proposal.tasks.count == 1 ? "Task:" : "Tasks (\(proposal.tasks.count)):")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)

                    Spacer()

                    // Add Task Button
                    if !availableBacklogItems.isEmpty {
                        Button(action: {
                            showingAddTaskSheet = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add")
                            }
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(proposal.tasks.enumerated()), id: \.offset) { index, task in
                        let detail = proposal.taskDetails?.first(where: { $0.title == task })
                        let isAdded = addedTaskTitles.contains(task)
                        taskRowEditable(title: task, detail: detail, isAdded: isAdded, canRemove: proposal.tasks.count > 1) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                removeTask(at: index)
                            }
                        }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: proposal.tasks.count)

                // Grouping type indicator
                if let groupingType = proposal.groupingType {
                    HStack {
                        Image(systemName: groupingTypeIcon(groupingType))
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                        Text(groupingTypeLabel(groupingType))
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .padding(.top, 4)
                }
            }

            Divider()

            // Time Adjustment Section
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    // Start Time Picker
                    HStack {
                        Text("Start:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(width: 45, alignment: .leading)

                        Button(action: {
                            showingCalendarView = true
                        }) {
                            HStack {
                                DatePicker("", selection: $selectedStartTime, displayedComponents: .hourAndMinute)
                                    .labelsHidden()
                                    .scaleEffect(0.9)
                                    .tint(dynamicPrimaryColor)
                                
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(dynamicPrimaryColor)
                            }
                        }

                        if hasModifications {
                            Text("Modified")
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }

                    // Duration Stepper
                    HStack {
                        Text("Duration:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(width: 60, alignment: .leading)

                        DurationStepper(duration: $adjustedDuration, minDuration: 15, maxDuration: 180, step: 5)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(adjustedDuration) min")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(dynamicTextColor)
                            
                            if !durationMatchesEstimates {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.orange)
                                    Text("Est: \(totalEstimatedDuration) min")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        // Auto-sync button if duration doesn't match
                        if !durationMatchesEstimates {
                            Button(action: {
                                withAnimation {
                                    adjustedDuration = totalEstimatedDuration
                                }
                            }) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }

                    // Show effective time range
                    HStack {
                        Text("Session:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(timeRangeString)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(hasModifications ? .orange : dynamicTextColor)
                    }
                }
                
                // Calendar preview
                CompactCalendarPreview(
                    events: schedulingViewModel.calendarEvents,
                    selectedDate: Calendar.current.startOfDay(for: selectedStartTime),
                    proposedStartTime: selectedStartTime,
                    proposedDuration: adjustedDuration,
                    onTap: {
                        showingCalendarView = true
                    }
                )
            }

            if let reason = proposal.reason {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reason:")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }

            Divider()

            // Action Buttons
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: {
                        // Capture modification state BEFORE async operations
                        let wasModified = hasModifications
                        let originalTime = proposal.workingSessionTime
                        let modifiedTimeStr = timeRangeString

                        // Update proposal with modifications before accepting
                        if wasModified {
                            proposal.adjustedStartTime = selectedStartTime
                            proposal.adjustedDuration = adjustedDuration
                        }
                        schedulingViewModel.currentProposal = proposal

                        // Accept the proposal and create calendar event
                        schedulingViewModel.acceptProposal(backlogItems: backlogViewModel.backlogItems) { scheduledTasks in
                            if !scheduledTasks.isEmpty {
                                if wasModified {
                                    // Calculate task changes
                                    let originalTaskSet = Set(originalTasks)
                                    let finalTaskSet = Set(scheduledTasks)
                                    let addedTasks = Array(finalTaskSet.subtracting(originalTaskSet))
                                    let removedTasks = Array(originalTaskSet.subtracting(finalTaskSet))
                                    
                                    onRequestModificationReason(
                                        ModificationContext(
                                            tasks: scheduledTasks,
                                            originalTasks: originalTasks,
                                            addedTasks: addedTasks,
                                            removedTasks: removedTasks,
                                            originalTime: originalTime,
                                            modifiedTime: modifiedTimeStr,
                                            dayOfWeek: dayOfWeekString(from: schedulingViewModel.selectedDate),
                                            reason: nil
                                        )
                                    )
                                } else {
                                    onAccept(scheduledTasks)
                                }
                            }
                        }
                    }) {
                        HStack {
                            Image(systemName: hasModifications ? "checkmark.circle.badge.questionmark" : "checkmark.circle.fill")
                            Text(hasModifications ? "Accept Modified" : "Accept")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(hasModifications ? Color.orange : dynamicPrimaryColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button(action: {
                        schedulingViewModel.declineProposal()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Decline")
                        }
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }

                Button(action: {
                    // Skip these tasks - mark as processed and move to next
                    let tasksToSkip = proposal.tasks
                    schedulingViewModel.skipTask(tasks: tasksToSkip) {
                        onAccept(tasksToSkip) // Mark these tasks as processed
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Skip Task")
                    }
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(dynamicBackgroundColor)
                    .cornerRadius(6)
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.5 : 1)
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .frame(maxWidth: maxWidth)
        .opacity(isDisabled ? 0.7 : 1)
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                appeared = true
            }
        }
        .id("proposal")
        .sheet(isPresented: $showingCalendarView) {
            DraggableCalendarView(
                proposedStartTime: $selectedStartTime,
                proposedDuration: $adjustedDuration,
                events: schedulingViewModel.calendarEvents,
                selectedDate: Calendar.current.startOfDay(for: selectedStartTime)
            )
        }
        .sheet(isPresented: $showingAddTaskSheet) {
            AddTaskToProposalSheet(
                availableItems: availableBacklogItems,
                onAdd: { item in
                    addTask(item)
                    showingAddTaskSheet = false
                },
                onDismiss: {
                    showingAddTaskSheet = false
                }
            )
        }
    }

    private func dayOfWeekString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date).lowercased()
    }

    // MARK: - Task Management

    private func removeTask(at index: Int) {
        guard proposal.tasks.count > 1, index < proposal.tasks.count else { return }
        let removedTask = proposal.tasks[index]

        proposal.tasks.remove(at: index)
        proposal.taskDetails?.removeAll { $0.title == removedTask }
        addedTaskTitles.remove(removedTask)
        
        // Auto-adjust duration to match remaining task estimates
        withAnimation {
            adjustedDuration = totalEstimatedDuration
        }
    }

    private func addTask(_ item: UnifiedBacklogItem) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            proposal.tasks.append(item.title)
            addedTaskTitles.insert(item.title)

            // Add task details
            let detail = ProposedTaskDetail(
                title: item.title,
                estimatedDuration: item.estimatedDuration,
                priority: item.priority ?? 0
            )
            if proposal.taskDetails == nil {
                proposal.taskDetails = [detail]
            } else {
                proposal.taskDetails?.append(detail)
            }

            // Auto-adjust duration to match all task estimates
            adjustedDuration = totalEstimatedDuration
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func taskRow(title: String, detail: ProposedTaskDetail?) -> some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(dynamicPrimaryColor)
            Text(title)
                .font(.caption)
                .foregroundColor(dynamicTextColor)

            Spacer()

            if let detail = detail {
                if let duration = detail.estimatedDuration {
                    Text("\(duration) min")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(dynamicBackgroundColor)
                        .cornerRadius(3)
                }
            }
        }
    }

    @ViewBuilder
    private func taskRowEditable(title: String, detail: ProposedTaskDetail?, isAdded: Bool, canRemove: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(isAdded ? .green : dynamicPrimaryColor)
            Text(title)
                .font(.caption)
                .foregroundColor(dynamicTextColor)

            if isAdded {
                Text("Added")
                    .font(.caption2)
                    .foregroundColor(.green)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(3)
            }

            Spacer()

            if let detail = detail, let duration = detail.estimatedDuration {
                Text("\(duration) min")
                    .font(.caption2)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(dynamicBackgroundColor)
                    .cornerRadius(3)
            }

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 2)
    }

    private func groupingTypeIcon(_ type: TaskGroupingType) -> String {
        switch type {
        case .quickTaskBatch: return "rectangle.stack"
        case .relatedTasks: return "link"
        case .singleFocus: return "target"
        }
    }

    private func groupingTypeLabel(_ type: TaskGroupingType) -> String {
        switch type {
        case .quickTaskBatch: return "Quick tasks batched"
        case .relatedTasks: return "Related tasks"
        case .singleFocus: return "Focus task"
        }
    }
}


// MARK: - Modification Reason Sheet

struct ModificationReasonSheet: View {
    @Binding var reason: String
    let originalTime: String
    let modifiedTime: String
    let tasks: [String]
    let onSubmit: (String) -> Void
    let onSkip: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("Help the agent learn!")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        Text("Why did you modify this session?")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .padding(.top, 20)

                    // Modification Summary
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tasks:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(tasks.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Original:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(originalTime)
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                                .strikethrough()
                        }

                        HStack {
                            Text("Modified to:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(modifiedTime)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // Reason Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your reason (optional but helpful):")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)

                        TextField("e.g., I have a meeting at that time, I prefer mornings...", text: $reason, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .lineLimit(3...6)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isTextFieldFocused = false
                            }
                    }
                    .padding(.horizontal)

                    // Quick Suggestions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quick reasons:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                QuickReasonChip(text: "Had a conflict", onTap: { reason = "Had a conflict at that time"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Too early", onTap: { reason = "That time was too early for me"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Too late", onTap: { reason = "That time was too late for me"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Need more time", onTap: { reason = "I need more time for this task"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Need less time", onTap: { reason = "I don't need that much time"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Prefer different slot", onTap: { reason = "I prefer a different time slot"; isTextFieldFocused = false })
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            isTextFieldFocused = false
                            onSubmit(reason)
                        }) {
                            Text(reason.isEmpty ? "Skip for now" : "Save Feedback")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(reason.isEmpty ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                                .cornerRadius(12)
                        }
                        .buttonStyle(ScaleButtonStyle())

                        if !reason.isEmpty {
                            Button(action: {
                                isTextFieldFocused = false
                                onSkip()
                            }) {
                                Text("Skip")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }
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
                        isTextFieldFocused = false
                        onSkip()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isTextFieldFocused = false
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
