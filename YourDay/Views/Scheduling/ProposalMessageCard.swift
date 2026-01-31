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

    @State private var selectedStartTime: Date
    @State private var adjustedDuration: Int
    @State private var showingCalendarView = false

    init(proposal: Binding<ProposedSession>, schedulingViewModel: SchedulingAssistantViewModel, backlogViewModel: BacklogViewModel, onAccept: @escaping ([String]) -> Void) {
        self._proposal = proposal
        self.schedulingViewModel = schedulingViewModel
        self.backlogViewModel = backlogViewModel
        self.onAccept = onAccept

        // Initialize state from proposal
        let initialStart = proposal.wrappedValue.effectiveStartTime ?? proposal.wrappedValue.startTime ?? Date()
        let initialDuration = proposal.wrappedValue.effectiveDuration ?? 60
        _selectedStartTime = State(initialValue: initialStart)
        _adjustedDuration = State(initialValue: initialDuration)
    }

    private var hasModifications: Bool {
        guard let originalStart = proposal.startTime else { return false }
        let originalDuration = proposal.effectiveDuration ?? 60

        let calendar = Calendar.current
        let startChanged = !calendar.isDate(selectedStartTime, equalTo: originalStart, toGranularity: .minute)
        let durationChanged = adjustedDuration != originalDuration

        return startChanged || durationChanged
    }

    private var effectiveEndTime: Date {
        Calendar.current.date(byAdding: .minute, value: adjustedDuration, to: selectedStartTime) ?? selectedStartTime
    }

    private var timeRangeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: selectedStartTime)) - \(formatter.string(from: effectiveEndTime))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Working Session")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            Divider()

            // Tasks Section
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.tasks.count == 1 ? "Task:" : "Tasks:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)

                    if proposal.tasks.count == 1 {
                        taskRow(title: proposal.tasks.first ?? "", detail: proposal.taskDetails?.first)
                    } else {
                        ForEach(Array(proposal.tasks.enumerated()), id: \.offset) { index, task in
                            let detail = proposal.taskDetails?.first(where: { $0.title == task })
                            taskRow(title: task, detail: detail)
                        }
                    }
                }

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

                        Text("\(adjustedDuration) min")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
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
                        // Update proposal with modifications before accepting
                        if hasModifications {
                            proposal.adjustedStartTime = selectedStartTime
                            proposal.adjustedDuration = adjustedDuration
                        }
                        schedulingViewModel.currentProposal = proposal

                        schedulingViewModel.acceptProposal(backlogItems: backlogViewModel.backlogItems) { scheduledTasks in
                            if !scheduledTasks.isEmpty {
                                onAccept(scheduledTasks)
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
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .frame(maxWidth: 320)
        .id("proposal")
        .sheet(isPresented: $showingCalendarView) {
            DraggableCalendarView(
                proposedStartTime: $selectedStartTime,
                proposedDuration: $adjustedDuration,
                events: schedulingViewModel.calendarEvents,
                selectedDate: Calendar.current.startOfDay(for: selectedStartTime)
            )
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
