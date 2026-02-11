//
//  DayContextSection.swift
//  YourDay
//
//  Reusable component for per-day schedule configuration
//

import SwiftUI

struct DayContextSection: View {
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @State private var selectedDay: String = "monday"
    @State private var isExpanded: Bool = false

    private let daysOfWeek = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    private let dayAbbreviations = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("Day-Specific Settings")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }

            if isExpanded {
                // Day selector pills
                HStack(spacing: 8) {
                    ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { index, day in
                        DayPill(
                            abbreviation: dayAbbreviations[index],
                            day: day,
                            isSelected: selectedDay == day,
                            hasContext: schedulingViewModel.dayContexts[day] != nil
                        ) {
                            selectedDay = day
                        }
                    }
                }
                .padding(.vertical, 8)

                // Day context editor
                DayContextEditor(
                    day: selectedDay,
                    context: bindingForDay(selectedDay),
                    onSave: { context in
                        schedulingViewModel.saveDayContext(context)
                    }
                )
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }

    private func bindingForDay(_ day: String) -> Binding<DayContext> {
        Binding(
            get: {
                schedulingViewModel.dayContexts[day] ?? DayContext(dayOfWeek: day)
            },
            set: { newValue in
                schedulingViewModel.dayContexts[day] = newValue
            }
        )
    }
}

// MARK: - Day Pill

struct DayPill: View {
    let abbreviation: String
    let day: String
    let isSelected: Bool
    let hasContext: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isSelected ? dynamicPrimaryColor : (hasContext ? dynamicPrimaryColor.opacity(0.2) : dynamicBackgroundColor))
                    .frame(width: 36, height: 36)

                Text(abbreviation)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? .white : (hasContext ? dynamicPrimaryColor : dynamicTextColor))

                // Indicator dot for configured days
                if hasContext && !isSelected {
                    Circle()
                        .fill(dynamicPrimaryColor)
                        .frame(width: 6, height: 6)
                        .offset(x: 12, y: -12)
                }
            }
        }
    }
}

// MARK: - Day Context Editor

struct DayContextEditor: View {
    let day: String
    @Binding var context: DayContext
    let onSave: (DayContext) -> Void

    @State private var wakeTimeEnabled: Bool = false
    @State private var wakeTime: Date = Date()
    @State private var lunchTimeEnabled: Bool = false
    @State private var lunchTime: Date = Date()
    @State private var activityText: String = ""
    @State private var showingAddBlockedTime: Bool = false
    @State private var blockedStartTime: Date = Date()
    @State private var blockedEndTime: Date = Date()
    @State private var blockedLabel: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Day title
            Text(day.capitalized)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(dynamicTextColor)

            // Wake time override
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $wakeTimeEnabled) {
                    Text("Custom wake time")
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                }
                .tint(dynamicPrimaryColor)

                if wakeTimeEnabled {
                    DatePicker("Wake time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(dynamicPrimaryColor)
                }
            }
            .onChange(of: wakeTimeEnabled) { _, enabled in
                if enabled {
                    context.wakeTime = formatTime(wakeTime)
                } else {
                    context.wakeTime = nil
                }
            }
            .onChange(of: wakeTime) { _, newTime in
                if wakeTimeEnabled {
                    context.wakeTime = formatTime(newTime)
                }
            }

            Divider()

            // Lunch time override
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $lunchTimeEnabled) {
                    Text("Custom lunch time")
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                }
                .tint(dynamicPrimaryColor)

                if lunchTimeEnabled {
                    DatePicker("Lunch time", selection: $lunchTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(dynamicPrimaryColor)
                }
            }
            .onChange(of: lunchTimeEnabled) { _, enabled in
                if enabled {
                    context.lunchTime = formatTime(lunchTime)
                } else {
                    context.lunchTime = nil
                }
            }
            .onChange(of: lunchTime) { _, newTime in
                if lunchTimeEnabled {
                    context.lunchTime = formatTime(newTime)
                }
            }

            Divider()

            // General activities
            VStack(alignment: .leading, spacing: 8) {
                Text("General activities")
                    .font(.subheadline)
                    .foregroundColor(dynamicTextColor)

                HStack {
                    AppTextField(placeholder: "e.g., gym morning, errands afternoon", text: $activityText)
                        .font(.caption)

                    Button(action: addActivity) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    .disabled(activityText.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Activity chips
                if !context.generalActivities.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(context.generalActivities, id: \.self) { activity in
                            ActivityChip(text: activity) {
                                removeActivity(activity)
                            }
                        }
                    }
                }
            }

            Divider()

            // Blocked time blocks
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Blocked times")
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)

                    Spacer()

                    Button(action: { showingAddBlockedTime.toggle() }) {
                        Image(systemName: showingAddBlockedTime ? "minus.circle" : "plus.circle")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                }

                if showingAddBlockedTime {
                    VStack(spacing: 8) {
                        HStack {
                            DatePicker("From", selection: $blockedStartTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()

                            Text("to")
                                .foregroundColor(dynamicSecondaryTextColor)

                            DatePicker("To", selection: $blockedEndTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }

                        AppTextField(placeholder: "Label (optional)", text: $blockedLabel)
                            .font(.caption)

                        Button("Add Blocked Time") {
                            addBlockedTime()
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(dynamicPrimaryColor)
                        .cornerRadius(8)
                    }
                    .padding()
                    .background(dynamicBackgroundColor)
                    .cornerRadius(8)
                }

                // Blocked time list
                ForEach(context.blockedBlocks, id: \.startTime) { block in
                    HStack {
                        Image(systemName: "clock.badge.xmark")
                            .foregroundColor(.red)
                            .font(.caption)

                        Text("\(block.startTime) - \(block.endTime)")
                            .font(.caption)
                            .foregroundColor(dynamicTextColor)

                        if let label = block.label {
                            Text("(\(label))")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }

                        Spacer()

                        Button(action: { removeBlockedTime(block) }) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(dynamicSecondaryTextColor)
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Save button
            Button(action: {
                onSave(context)
            }) {
                Text("Save \(day.capitalized) Settings")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(dynamicPrimaryColor)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(dynamicBackgroundColor)
        .cornerRadius(10)
        .onAppear {
            loadContext()
        }
        .onChange(of: day) { _, _ in
            loadContext()
        }
    }

    private func loadContext() {
        wakeTimeEnabled = context.wakeTime != nil
        if let wakeTimeStr = context.wakeTime {
            wakeTime = parseTimeString(wakeTimeStr) ?? Date()
        }

        lunchTimeEnabled = context.lunchTime != nil
        if let lunchTimeStr = context.lunchTime {
            lunchTime = parseTimeString(lunchTimeStr) ?? Date()
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parseTimeString(_ timeStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeStr)
    }

    private func addActivity() {
        let activity = activityText.trimmingCharacters(in: .whitespaces)
        guard !activity.isEmpty else { return }
        context.generalActivities.append(activity)
        activityText = ""
    }

    private func removeActivity(_ activity: String) {
        context.generalActivities.removeAll { $0 == activity }
    }

    private func addBlockedTime() {
        let block = TimeBlock(
            startTime: formatTime(blockedStartTime),
            endTime: formatTime(blockedEndTime),
            label: blockedLabel.isEmpty ? nil : blockedLabel
        )
        context.blockedBlocks.append(block)
        showingAddBlockedTime = false
        blockedLabel = ""
    }

    private func removeBlockedTime(_ block: TimeBlock) {
        context.blockedBlocks.removeAll { $0 == block }
    }
}

// MARK: - Activity Chip

struct ActivityChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
                .foregroundColor(dynamicTextColor)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(16)
    }
}

// MARK: - Flow Layout (for wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
