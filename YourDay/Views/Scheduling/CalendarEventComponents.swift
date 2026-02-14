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
    
    private let calendar = Calendar.current
    
    private var topOffset: CGFloat {
        CalendarEventFilter.calculateTimeOffset(start: eventStart, date: selectedDate, hourHeight: hourHeight, headerOffset: 20)
    }
    
    private var height: CGFloat {
        CalendarEventFilter.calculateEventHeight(start: eventStart, end: eventEnd, hourHeight: hourHeight)
    }
    
    // Calculate width and x position for overlapping events
    private var eventWidth: CGFloat {
        // Divide available width by number of overlapping events
        return availableWidth / CGFloat(groupSize)
    }
    
    private var xOffset: CGFloat {
        // Position each event side by side
        return 80 + (CGFloat(groupIndex) * eventWidth)
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
                RoundedRectangle(cornerRadius: 6)
                    .fill(eventColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(timeRangeString)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
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
    
    private let calendar = Calendar.current
    
    init(event: GoogleCalendarEvent?, eventStart: Date, eventEnd: Date, selectedDate: Date, hourHeight: CGFloat, isDraggable: Bool, dragOffset: Binding<CGSize> = .constant(.zero), isDragging: Binding<Bool> = .constant(false), onDragEnd: ((CGSize) -> Void)? = nil) {
        self.event = event
        self.eventStart = eventStart
        self.eventEnd = eventEnd
        self.selectedDate = selectedDate
        self.hourHeight = hourHeight
        self.isDraggable = isDraggable
        self._dragOffset = dragOffset
        self._isDragging = isDragging
        self.onDragEnd = onDragEnd
    }
    
    private var topOffset: CGFloat {
        let baseOffset = CalendarEventFilter.calculateTimeOffset(start: eventStart, date: selectedDate, hourHeight: hourHeight, headerOffset: 20)
        let dragY: CGFloat = isDraggable ? dragOffset.height : 0
        return baseOffset + dragY
    }
    
    private var height: CGFloat {
        CalendarEventFilter.calculateEventHeight(start: eventStart, end: eventEnd, hourHeight: hourHeight)
    }
    
    /// Theme orange for Google Calendar events, theme green for YourDay scheduled/proposed sessions.
    private var blockColor: Color {
        if isDraggable { return dynamicPrimaryColor }
        if let event = event, event.description?.contains("[YourDay Scheduled Task]") == true { return dynamicPrimaryColor }
        return dynamicSecondaryColor
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(blockColor.opacity(isDraggable ? 1 : 0.9))
            .frame(width: UIScreen.main.bounds.width - 120, height: height)
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    if isDraggable {
                        Text("Proposed Session")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(timeRangeString)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    } else if let event = event {
                        Text(event.summary)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(timeRangeString)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .padding(8),
                alignment: .topLeading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isDraggable ? Color.white : Color.clear, lineWidth: 2)
            )
            .offset(x: 80, y: topOffset)
            .gesture(
                isDraggable ? DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        isDragging = false
                        onDragEnd?(value.translation)
                    } : nil
            )
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.3), value: isDragging)
    }
    
    private var timeRangeString: String {
        CalendarTimeFormatter.formatTimeRange(start: eventStart, end: eventEnd)
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
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @State private var sessionTitle: String = ""
    @State private var taskTitles: [String] = []
    @State private var matchedItems: [TodoItem] = []
    @State private var isLoading = true
    @State private var fallbackCheckedOff: Set<Int> = []
    
    private let calendar = Calendar.current
    private var timeRangeString: String {
        guard let start = event.start.startDate,
              let end = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: start) else { return "" }
        return CalendarTimeFormatter.formatTimeRange(start: start, end: end)
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
                                ScheduledTaskItemRow(item: item, modelContext: modelContext)
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
        item.isDone.toggle()
        item.completedAt = item.isDone ? Date() : nil
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
        
        saveContext()
    }
    
    private func saveContext() {
        try? modelContext.save()
    }
}


