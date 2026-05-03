//
//  CalendarEventComponents.swift
//  YourDay
//
//  Calendar event display components
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseAuth

// MARK: - Event Bar (for compact preview)

struct EventBar: View {
    let start: Date
    let end: Date
    let color: Color
    let isProposed: Bool
    
    private let calendar = Calendar.current
    private let startHour = 6
    private let hourHeight: CGFloat = 8
    
    private var topOffset: CGFloat {
        CalendarEventFilter.calculateOffsetFromStartHour(start: start, date: start, startHour: startHour, hourHeight: hourHeight)
    }
    
    private var height: CGFloat {
        CalendarEventFilter.calculateEventHeight(start: start, end: end, hourHeight: hourHeight)
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: isProposed ? 36 : 32, height: height)
            .offset(x: isProposed ? 2 : 4, y: topOffset)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isProposed ? Color.white : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Event Block View (for timeline)

struct EventBlockView: View {
    let event: GoogleCalendarEvent
    let eventStart: Date
    let eventEnd: Date
    let selectedDate: Date
    let hourHeight: CGFloat
    let availableWidth: CGFloat
    let groupSize: Int  // Number of overlapping events
    let groupIndex: Int // Index within the overlapping group
    var eventGap: CGFloat = 4
    
    private let calendar = Calendar.current
    
    private var topOffset: CGFloat {
        CalendarEventFilter.calculateTimeOffset(start: eventStart, date: selectedDate, hourHeight: hourHeight, headerOffset: 20)
    }
    
    private var height: CGFloat {
        CalendarEventFilter.calculateEventHeight(start: eventStart, end: eventEnd, hourHeight: hourHeight)
    }
    
    // Width and x position so overlapping events sit side by side with gaps
    private var eventWidth: CGFloat {
        let totalGaps = CGFloat(max(0, groupSize - 1)) * eventGap
        return (availableWidth - totalGaps) / CGFloat(groupSize)
    }
    
    private var xOffset: CGFloat {
        return 80 + CGFloat(groupIndex) * (eventWidth + eventGap)
    }
    
    /// Scale content (fonts, padding) with timeline zoom so events shrink/expand with the grid.
    private var contentScale: CGFloat {
        let baseline: CGFloat = 50
        return min(1.2, max(0.6, hourHeight / baseline))
    }
    
    private var timeRangeString: String {
        CalendarTimeFormatter.formatTimeRange(start: eventStart, end: eventEnd)
    }
    
    /// Theme orange for Google Calendar events, theme green for YourDay scheduled tasks.
    private var eventColor: Color {
        (event.description?.contains("[YourDay Scheduled Task]") == true) ? dynamicPrimaryColor : dynamicSecondaryColor
    }
    
    /// URL to open for this event: htmlLink when present, else main Google Calendar as fallback.
    private var eventURL: URL? {
        if let link = event.htmlLink, let url = URL(string: link) { return url }
        return URL(string: "https://calendar.google.com/calendar/u/0/r")
    }
    
    private var isScheduledTask: Bool {
        event.description?.contains("[YourDay Scheduled Task]") == true
    }
    
    var onScheduledTaskTap: ((GoogleCalendarEvent) -> Void)?
    
    var body: some View {
        Button {
            if isScheduledTask {
                onScheduledTaskTap?(event)
            } else if let url = eventURL {
                UIApplication.shared.open(url)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6 * contentScale)
                    .fill(eventColor)
                
                VStack(alignment: .leading, spacing: 2 * contentScale) {
                    Text(event.summary)
                        .font(.system(size: 13 * contentScale, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(timeRangeString)
                        .font(.system(size: 11 * contentScale))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6 * contentScale)
                .padding(.vertical, 4 * contentScale)
            }
            .frame(width: eventWidth, height: height)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .position(x: xOffset + eventWidth / 2, y: topOffset + height / 2)
    }
}

// MARK: - Draggable Event Block

struct DraggableEventBlock: View {
    let event: GoogleCalendarEvent?
    let eventStart: Date
    let eventEnd: Date
    let selectedDate: Date
    let hourHeight: CGFloat
    let isDraggable: Bool
    @Binding var dragOffset: CGSize
    @Binding var isDragging: Bool
    var onDragEnd: ((CGSize) -> Void)?
    /// When non-nil and draggable, replaces the default "Time block" label.
    var draggableSessionTitle: String?
    /// When scheduling several tasks in one block, show each title below the main label (not one long clumped string).
    var draggableTaskSubtitleLines: [String]?
    /// When non-nil, shows a bottom resize handle that edits duration in minutes (snapped to 15, clamped).
    var durationMinutesBinding: Binding<Int>?
    
    @State private var isResizingDuration = false
    @State private var durationAtResizeStart: Int = 0
    /// Continuous minutes during resize (not snapped); avoids layout flashing until gesture ends.
    @State private var resizePreviewMinutes: CGFloat?
    
    private let calendar = Calendar.current
    
    init(
        event: GoogleCalendarEvent?,
        eventStart: Date,
        eventEnd: Date,
        selectedDate: Date,
        hourHeight: CGFloat,
        isDraggable: Bool,
        dragOffset: Binding<CGSize> = .constant(.zero),
        isDragging: Binding<Bool> = .constant(false),
        onDragEnd: ((CGSize) -> Void)? = nil,
        draggableSessionTitle: String? = nil,
        draggableTaskSubtitleLines: [String]? = nil,
        durationMinutesBinding: Binding<Int>? = nil
    ) {
        self.event = event
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.selectedDate = selectedDate
        self.hourHeight = hourHeight
        self.isDraggable = isDraggable
        self._dragOffset = dragOffset
        self._isDragging = isDragging
        self.onDragEnd = onDragEnd
        self.draggableSessionTitle = draggableSessionTitle
        self.draggableTaskSubtitleLines = draggableTaskSubtitleLines
        self.durationMinutesBinding = durationMinutesBinding
    }
    
    private var topOffset: CGFloat {
        let baseOffset = CalendarEventFilter.calculateTimeOffset(start: eventStart, date: selectedDate, hourHeight: hourHeight, headerOffset: 20)
        let dragY: CGFloat = isDraggable ? dragOffset.height : 0
        return baseOffset + dragY
    }
    
    /// Duration in minutes (fractional while resizing for smooth feedback).
    private var effectiveDurationMinutes: CGFloat {
        if let preview = resizePreviewMinutes {
            return preview
        }
        return CGFloat(eventEnd.timeIntervalSince(eventStart) / 60.0)
    }
    
    private var displayEndDate: Date {
        eventStart.addingTimeInterval(TimeInterval(effectiveDurationMinutes * 60))
    }
    
    private var height: CGFloat {
        let raw = CGFloat(effectiveDurationMinutes / 60.0) * hourHeight
        // Keep short events visible and tappable without breaking grid math too badly.
        return max(22, raw)
    }
    
    /// Typography / padding scale from block height (short events shrink to fit).
    private var blockContentScale: CGFloat {
        let hourPx = max(hourHeight, 1)
        let reference = hourPx * 1.0 // one hour row == full scale
        return min(1.15, max(0.42, height / reference))
    }
    
    private var isCompactBlock: Bool {
        effectiveDurationMinutes < 60 || height < hourHeight * 0.92
    }
    
    private var isMicroBlock: Bool {
        effectiveDurationMinutes < 35 || height < hourHeight * 0.55
    }
    
    /// Theme orange for Google Calendar events, theme green for YourDay scheduled/proposed sessions.
    private var blockColor: Color {
        if isDraggable { return dynamicPrimaryColor }
        if let event = event, event.description?.contains("[YourDay Scheduled Task]") == true { return dynamicPrimaryColor }
        return dynamicSecondaryColor
    }
    
    private var draggableTitleText: String {
        if let draggableSessionTitle, !draggableSessionTitle.isEmpty {
            return draggableSessionTitle
        }
        return "Time block"
    }

    private var taskSubtitleToShow: [String] {
        let raw = draggableTaskSubtitleLines ?? []
        return Array(raw.prefix(3))
    }

    private var taskSubtitleMoreCount: Int {
        let raw = draggableTaskSubtitleLines?.count ?? 0
        return max(0, raw - 3)
    }
    
    @ViewBuilder
    private var draggableContent: some View {
        let scale = blockContentScale
        let hPad = max(4, 8 * scale)
        let vPad = max(3, 6 * scale)
        let titleSize = max(9, (isMicroBlock ? 10 : (isCompactBlock ? 12 : 17)) * scale)
        let timeSize = max(8, (isMicroBlock ? 9 : (isCompactBlock ? 10 : 12)) * scale)
        let lineSpacing = max(1, 3 * scale)
        
        if isDraggable {
            if isMicroBlock {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    Text(draggableTitleText)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(compactTimeRangeString)
                        .font(.system(size: timeSize, weight: .medium))
                        .foregroundColor(.white.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: lineSpacing) {
                    Text(draggableTitleText)
                        .font(.system(size: titleSize, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(isCompactBlock ? 1 : 2)
                        .minimumScaleFactor(0.65)
                    if !taskSubtitleToShow.isEmpty {
                        VStack(alignment: .leading, spacing: max(1, 2 * scale)) {
                            ForEach(Array(taskSubtitleToShow.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: max(7, 9 * scale), weight: .regular))
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                            }
                            if taskSubtitleMoreCount > 0 {
                                Text("+\(taskSubtitleMoreCount) more")
                                    .font(.system(size: max(7, 8 * scale), weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    Text(isCompactBlock ? compactTimeRangeString : displayTimeRangeString)
                        .font(.system(size: timeSize, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else if let event = event {
            VStack(alignment: .leading, spacing: lineSpacing) {
                Text(event.summary)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(isCompactBlock ? 1 : 2)
                    .minimumScaleFactor(0.65)
                Text(isCompactBlock ? compactTimeRangeString : displayTimeRangeString)
                    .font(.system(size: timeSize, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyView()
        }
    }
    
    /// Shorter time strings for small blocks (saves vertical space).
    private var compactTimeRangeString: String {
        CalendarTimeFormatter.formatTimeRangeCompact(start: eventStart, end: displayEndDate)
    }
    
    private var displayTimeRangeString: String {
        CalendarTimeFormatter.formatTimeRange(start: eventStart, end: displayEndDate)
    }
    
    var body: some View {
        let corner: CGFloat = max(4, 8 * min(1, blockContentScale))
        RoundedRectangle(cornerRadius: corner)
            .fill(blockColor.opacity(isDraggable ? 1 : 0.9))
            .frame(width: UIScreen.main.bounds.width - 120, height: height)
            .overlay(draggableContent, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if isDraggable, durationMinutesBinding != nil {
                    let gripH: CGFloat = min(18, max(12, height * 0.28))
                    VStack(spacing: 2) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: max(8, 11 * blockContentScale)))
                            .foregroundColor(.white.opacity(0.95))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: gripH)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard let binding = durationMinutesBinding else { return }
                                if !isResizingDuration {
                                    isResizingDuration = true
                                    durationAtResizeStart = binding.wrappedValue
                                    resizePreviewMinutes = CGFloat(durationAtResizeStart)
                                }
                                let delta = value.translation.height / max(hourHeight, 1) * 60
                                let raw = CGFloat(durationAtResizeStart) + delta
                                resizePreviewMinutes = min(480, max(15, raw))
                            }
                            .onEnded { value in
                                guard let binding = durationMinutesBinding else {
                                    resizePreviewMinutes = nil
                                    isResizingDuration = false
                                    return
                                }
                                let baseMinutes = isResizingDuration ? durationAtResizeStart : binding.wrappedValue
                                let delta = value.translation.height / max(hourHeight, 1) * 60
                                let raw = CGFloat(baseMinutes) + delta
                                let clamped = min(480, max(15, raw))
                                let snapped = (Int(round(clamped / 15)) * 15)
                                let final = min(480, max(15, snapped))
                                binding.wrappedValue = final
                                resizePreviewMinutes = nil
                                isResizingDuration = false
                            }
                    )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: corner)
                    .stroke(isDraggable ? Color.white : Color.clear, lineWidth: max(1, 2 * min(1, blockContentScale)))
            )
            .offset(x: 80, y: topOffset)
            .transaction { tx in
                if resizePreviewMinutes != nil {
                    tx.animation = nil
                }
            }
            .gesture(
                isDraggable ? DragGesture()
                    .onChanged { value in
                        guard !isResizingDuration else { return }
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        guard !isResizingDuration else { return }
                        isDragging = false
                        onDragEnd?(value.translation)
                    } : nil
            )
            .scaleEffect(isDragging && !isResizingDuration ? 1.03 : 1.0)
    }
}

// MARK: - Compact Calendar Preview

struct CompactCalendarPreview: View {
    let events: [GoogleCalendarEvent]
    let selectedDate: Date
    let proposedStartTime: Date
    let proposedDuration: Int // in minutes
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    private let startHour = 6
    private let endHour = 22
    private let hourHeight: CGFloat = 8
    
    private var timeSlots: [Date] {
        var slots: [Date] = []
        for hour in startHour...endHour {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                slots.append(date)
            }
        }
        return slots
    }
    
    private var dayEvents: [GoogleCalendarEvent] {
        CalendarEventFilter.filterEventsForDay(events, date: selectedDate)
    }
    
    private var proposedEndTime: Date {
        calendar.date(byAdding: .minute, value: proposedDuration, to: proposedStartTime) ?? proposedStartTime
    }
    
    var body: some View {
        HStack(spacing: 4) {
            // Time labels on left - aligned with grid
            VStack(spacing: 0) {
                ForEach(Array(stride(from: startHour, through: endHour, by: 2)), id: \.self) { hour in
                    Text(CalendarTimeFormatter.formatHour(hour, date: selectedDate))
                        .font(.system(size: 6))
                        .foregroundColor(dynamicSecondaryTextColor)
                        .frame(height: hourHeight * 2, alignment: .top)
                        .padding(.top, 1) // Small top padding to align with grid line
                }
            }
            .frame(width: 20, alignment: .trailing)
            
            // Calendar timeline
            ZStack(alignment: .topLeading) {
                // Background grid - one rectangle per hour
                VStack(spacing: 0) {
                    ForEach(0..<(endHour - startHour + 1), id: \.self) { hourOffset in
                        Rectangle()
                            .fill(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .frame(height: hourHeight)
                            .overlay(
                                Rectangle()
                                    .fill(dynamicSecondaryBackgroundColor.opacity(0.5))
                                    .frame(height: 1),
                                alignment: .bottom
                            )
                    }
                }
                
                // Existing events: theme orange for calendar, theme green for scheduled tasks
                ForEach(dayEvents) { event in
                    if let eventStart = event.start.startDate,
                       let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) {
                        let isScheduledTask = event.description?.contains("[YourDay Scheduled Task]") == true
                        EventBar(
                            start: eventStart,
                            end: eventEnd,
                            color: (isScheduledTask ? dynamicPrimaryColor : dynamicSecondaryColor).opacity(0.9),
                            isProposed: false
                        )
                    }
                }
                
                // Proposed event (scheduled task) = theme green
                EventBar(
                    start: proposedStartTime,
                    end: proposedEndTime,
                    color: dynamicPrimaryColor,
                    isProposed: true
                )
            }
            .frame(width: 40)
        }
        .frame(height: CGFloat(endHour - startHour + 1) * hourHeight)
        .padding(4)
        .background(dynamicBackgroundColor)
        .cornerRadius(6)
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Scheduled Task Popup Sheet

struct ScheduledTaskPopupSheet: View {
    let event: GoogleCalendarEvent
    let onDismiss: () -> Void
    /// Called after a successful “remove from Google Calendar” (so the parent can refetch / dismiss).
    var onEventDeleted: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @State private var sessionTitle: String = ""
    @State private var taskTitles: [String] = []
    @State private var matchedItems: [TodoItem] = []
    @State private var isLoading = true
    @State private var fallbackCheckedOff: Set<Int> = []
    @State private var pendingTaskProofCapture: TaskProofCaptureContext?
    @State private var isDeletingFromCalendar = false
    @State private var showDeleteFromCalendarConfirm = false
    @State private var deleteFailureMessage: String?
    
    private let calendar = Calendar.current
    private var timeRangeString: String {
        guard let start = event.start.startDate,
              let end = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: start) else { return "" }
        return CalendarTimeFormatter.formatTimeRange(start: start, end: end)
    }

    private var isYourDayScheduledBlock: Bool {
        event.description?.contains("[YourDay Scheduled Task]") == true
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !matchedItems.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(timeRangeString)
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            if !sessionTitle.isEmpty {
                                Text(sessionTitle)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                            }
                            ForEach(matchedItems) { item in
                                ScheduledTaskItemRow(
                                    item: item,
                                    modelContext: modelContext,
                                    scheduledCalendarEventId: event.id,
                                    onRequestProofCapture: { pendingTaskProofCapture = $0 }
                                )
                                .environmentObject(firebaseManager)
                            }
                        }
                        .padding()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(timeRangeString)
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            if !sessionTitle.isEmpty {
                                Text(sessionTitle)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                            }
                            Text("Add these tasks to your list to check them off here.")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            ForEach(Array(taskTitles.enumerated()), id: \.offset) { index, task in
                                HStack(spacing: 12) {
                                    Image(systemName: fallbackCheckedOff.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(fallbackCheckedOff.contains(index) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                                        .font(.title3)
                                    Text(task)
                                        .font(.subheadline)
                                        .foregroundColor(dynamicTextColor)
                                        .strikethrough(fallbackCheckedOff.contains(index))
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if fallbackCheckedOff.contains(index) {
                                        fallbackCheckedOff.remove(index)
                                    } else {
                                        fallbackCheckedOff.insert(index)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isYourDayScheduledBlock {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(role: .destructive) {
                            showDeleteFromCalendarConfirm = true
                        } label: {
                            if isDeletingFromCalendar {
                                ProgressView()
                            } else {
                                Image(systemName: "trash")
                            }
                        }
                        .disabled(isDeletingFromCalendar)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .onAppear {
            loadScheduledEvent()
        }
        .alert("Remove from Google Calendar?", isPresented: $showDeleteFromCalendarConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { deleteEventFromGoogleCalendar() }
        } message: {
            Text("The event is removed from Google Calendar and your tasks are unlinked, same as in manual scheduling.")
        }
        .alert("Couldn’t remove", isPresented: Binding(
            get: { deleteFailureMessage != nil },
            set: { if !$0 { deleteFailureMessage = nil } }
        )) {
            Button("OK", role: .cancel) { deleteFailureMessage = nil }
        } message: {
            Text(deleteFailureMessage ?? "")
        }
        .sheet(item: $pendingTaskProofCapture, onDismiss: { pendingTaskProofCapture = nil }) { proofContext in
            TaskProofCaptureView(
                context: proofContext,
                onSkip: { pendingTaskProofCapture = nil },
                onPosted: { postId in
                    applyProofPostId(postId, localTaskId: proofContext.localTaskId)
                    pendingTaskProofCapture = nil
                }
            )
            .environmentObject(firebaseManager)
        }
    }
    
    private func applyProofPostId(_ postId: String, localTaskId: String?) {
        guard let localTaskId else { return }
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { $0.localTaskId == localTaskId }
        )
        guard let todo = try? modelContext.fetch(descriptor).first else { return }
        todo.proofPostId = postId
        try? modelContext.save()
    }
    
    private func deleteEventFromGoogleCalendar() {
        isDeletingFromCalendar = true
        let eventId = event.id
        ManualCalendarEventDeletionService.deleteGoogleCalendarEventsAndUnlinkLocalTasks(
            eventIds: [eventId],
            modelContext: modelContext,
            firebaseManager: firebaseManager
        ) { err in
            DispatchQueue.main.async {
                isDeletingFromCalendar = false
                if let err = err {
                    deleteFailureMessage = err.localizedDescription
                    return
                }
                onEventDeleted?()
                onDismiss()
            }
        }
    }

    private func loadScheduledEvent() {
        firebaseManager.fetchScheduledEvent(eventId: event.id) { data, _ in
            DispatchQueue.main.async {
                if let data = data,
                   let title = data["taskTitle"] as? String,
                   let list = data["tasks"] as? [String] {
                    sessionTitle = title
                    taskTitles = list
                } else {
                    sessionTitle = event.summary
                    taskTitles = tasksFromDescription(event.description)
                }
                matchedItems = fetchTodoItemsMatchingTitles(taskTitles)
                isLoading = false
            }
        }
    }
    
    private func fetchTodoItemsMatchingTitles(_ titles: [String]) -> [TodoItem] {
        guard !titles.isEmpty else { return [] }
        let set = Set(titles)
        let descriptor = FetchDescriptor<TodoItem>(sortBy: [SortDescriptor(\.position)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all.filter { set.contains($0.title) }
    }
    
    private func tasksFromDescription(_ description: String?) -> [String] {
        guard let desc = description else { return [event.summary] }
        guard let range = desc.range(of: "Tasks:\n• ") else { return [event.summary] }
        let after = String(desc[range.upperBound...])
        let beforeMarker = after.components(separatedBy: "\n\n[YourDay Scheduled Task]").first ?? after
        let lines = beforeMarker.components(separatedBy: "\n• ")
        return lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// MARK: - Scheduled Task Item Row (actual TodoItem with checkoffs)

struct ScheduledTaskItemRow: View {
    @Bindable var item: TodoItem
    var modelContext: ModelContext
    /// Google Calendar event id when opened from the calendar (for proof `sourceType` / `scheduledEventId`).
    var scheduledCalendarEventId: String?
    var onRequestProofCapture: ((TaskProofCaptureContext) -> Void)?
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                toggleMainTask()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                        .font(.title3)
                    Text(item.title)
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                        .strikethrough(item.isDone)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            if !item.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($item.subtasks) { $subtask in
                        SubtaskCheckboxView(subtask: $subtask, onToggle: { _ in
                            if let sharedId = item.sharedTaskId {
                                let sharedSubtasks = item.subtasks.enumerated().map { idx, st in
                                    SharedSubtask(id: "sub_\(idx)", title: st.title, isDone: st.isDone)
                                }
                                firebaseManager.updateSharedSubtasks(sharedTaskId: sharedId, subtasks: sharedSubtasks) { _ in }
                            }
                            
                            // Sync subtask change to Firebase
                            if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                                let codableTask = TodoItemCodable(from: item, userId: userId)
                                firebaseManager.saveTodoItem(codableTask) { error in
                                    if let error = error {
                                        print("CalendarEventComponents: Failed to sync subtask change to Firebase: \(error.localizedDescription)")
                                    } else {
                                        print("CalendarEventComponents: Successfully synced subtask change to Firebase")
                                    }
                                }
                            }
                            
                            saveContext()
                        })
                        .strikethrough(subtask.isDone, color: dynamicSecondaryTextColor.opacity(0.7))
                        .foregroundColor(subtask.isDone ? dynamicSecondaryTextColor.opacity(0.7) : dynamicTextColor)
                        .font(.caption)
                    }
                }
                .padding(.leading, 28)
            }
        }
    }
    
    private func toggleMainTask() {
        let wasDone = item.isDone
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil

        if item.trelloCardId != nil {
            Task { await TrelloTaskSyncService.pushCompletion(for: item) }
        }
        
        if let sharedId = item.sharedTaskId {
            firebaseManager.updateSharedTaskProgress(sharedTaskId: sharedId, isCompleted: item.isDone) { _ in }
        }
        
        // Sync task completion toggle to Firebase
        if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
            let codableTask = TodoItemCodable(from: item, userId: userId)
            firebaseManager.saveTodoItem(codableTask) { error in
                if let error = error {
                    print("CalendarEventComponents: Failed to sync task toggle to Firebase: \(error.localizedDescription)")
                } else {
                    print("CalendarEventComponents: Successfully synced task toggle to Firebase")
                }
            }
        }
        
        if !wasDone && item.isDone {
            if !ScheduledSessionCompletionCoordinator.isCompletingScheduledBlockEarly(item) {
                let sourceType: TaskProofSourceType
                if item.sharedTaskId != nil {
                    sourceType = .shared
                } else if scheduledCalendarEventId != nil {
                    sourceType = .scheduled
                } else {
                    sourceType = .unscheduled
                }
                onRequestProofCapture?(
                    TaskProofCaptureContext(
                        taskTitle: item.title,
                        sourceType: sourceType,
                        scheduledEventId: scheduledCalendarEventId,
                        localTaskId: item.localTaskId,
                        sharedTaskId: item.sharedTaskId,
                        completedAt: item.completedAt ?? Date()
                    )
                )
            }
            ScheduledSessionCompletionCoordinator.handleEarlyCompletion(
                for: item,
                modelContext: modelContext
            )
        } else if wasDone && !item.isDone, let proofPostId = item.proofPostId {
            item.proofPostId = nil
            if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                let codableTask = TodoItemCodable(from: item, userId: userId)
                firebaseManager.saveTodoItem(codableTask) { error in
                    if let error = error {
                        print("CalendarEventComponents: Failed to sync cleared proofPostId to Firebase: \(error.localizedDescription)")
                    }
                }
            }
            firebaseManager.deleteTaskProofPost(postId: proofPostId) { error in
                if let error = error {
                    print("CalendarEventComponents: Failed to delete proof post: \(error.localizedDescription)")
                }
            }
        }
        
        saveContext()
    }
    
    private func saveContext() {
        try? modelContext.save()
    }
}


