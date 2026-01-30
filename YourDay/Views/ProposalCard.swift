//
//  ProposalCard.swift
//  YourDay
//
//  Card view for displaying proposed working sessions
//

import SwiftUI

struct ProposalCard: View {
    @Binding var proposal: ProposedSession
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @ObservedObject var backlogViewModel: BacklogViewModel
    let onAccept: ([String]) -> Void

    @State private var selectedStartTime: Date
    @State private var adjustedDuration: Int

    init(proposal: Binding<ProposedSession>, schedulingViewModel: SchedulingAssistantViewModel, backlogViewModel: BacklogViewModel, onAccept: @escaping ([String]) -> Void) {
        self._proposal = proposal
        self.schedulingViewModel = schedulingViewModel
        self.backlogViewModel = backlogViewModel
        self.onAccept = onAccept

        // Initialize state from proposal
        let initialStart = proposal.wrappedValue.effectiveStartTime ?? proposal.wrappedValue.startTime ?? Date()
        // Ensure duration is always positive and within bounds (15-180 min)
        let rawDuration = proposal.wrappedValue.effectiveDuration ?? 60
        let initialDuration = max(15, min(180, rawDuration > 0 ? rawDuration : 60))
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
            VStack(alignment: .leading, spacing: 12) {
                // Start Time Picker
                HStack {
                    Text("Start:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .frame(width: 50, alignment: .leading)

                    DatePicker("", selection: $selectedStartTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(dynamicPrimaryColor)

                    Spacer()

                    if hasModifications {
                        Text("Modified")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                // Duration Stepper
                HStack {
                    Text("Duration:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .frame(width: 70, alignment: .leading)

                    DurationStepper(duration: $adjustedDuration, minDuration: 15, maxDuration: 180, step: 5)

                    Spacer()

                    Text("\(adjustedDuration) min")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(dynamicTextColor)
                }

                // Show effective time range
                HStack {
                    Text("Session:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text(timeRangeString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(hasModifications ? .orange : dynamicTextColor)
                }

                if let reason = proposal.reason {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason:")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
            }

            Divider()

            // Action Buttons
            VStack(spacing: 12) {
                HStack(spacing: 16) {
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
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(hasModifications ? Color.orange : dynamicPrimaryColor)
                        .cornerRadius(10)
                    }

                    Button(action: {
                        schedulingViewModel.declineProposal()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Decline")
                        }
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(10)
                    }
                }

                Button(action: {
                    // Skip these tasks without reason
                    let tasksToSkip = proposal.tasks
                    schedulingViewModel.skipTask(tasks: tasksToSkip) {
                        onAccept(tasksToSkip) // Mark these tasks as processed
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Skip Task")
                    }
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(dynamicBackgroundColor)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func taskRow(title: String, detail: ProposedTaskDetail?) -> some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(dynamicPrimaryColor)
            Text(title)
                .font(.subheadline)
                .foregroundColor(dynamicTextColor)

            Spacer()

            if let detail = detail {
                if let duration = detail.estimatedDuration {
                    Text("\(duration) min")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(dynamicBackgroundColor)
                        .cornerRadius(4)
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
        case .quickTaskBatch: return "Quick tasks batched together"
        case .relatedTasks: return "Related tasks grouped"
        case .singleFocus: return "Single focus task"
        }
    }
}

// MARK: - Duration Stepper Component

struct DurationStepper: View {
    @Binding var duration: Int
    let minDuration: Int
    let maxDuration: Int
    let step: Int

    var body: some View {
        HStack(spacing: 0) {
            Button(action: {
                if duration > minDuration {
                    duration = max(minDuration, duration - step)
                }
            }) {
                Image(systemName: "minus")
                    .font(.headline)
                    .foregroundColor(duration <= minDuration ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .frame(width: 36, height: 36)
                    .background(dynamicBackgroundColor)
            }
            .disabled(duration <= minDuration)

            Divider()
                .frame(height: 24)

            Button(action: {
                if duration < maxDuration {
                    duration = min(maxDuration, duration + step)
                }
            }) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundColor(duration >= maxDuration ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .frame(width: 36, height: 36)
                    .background(dynamicBackgroundColor)
            }
            .disabled(duration >= maxDuration)
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dynamicSecondaryTextColor.opacity(0.3), lineWidth: 1)
        )
    }
}
