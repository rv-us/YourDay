//
//  CalendarEventComponents.swift
//  YourDay
//
//  Calendar event display components
//

import SwiftUI

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
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(dynamicPrimaryColor)
            
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
        .frame(width: eventWidth, height: height, alignment: .topLeading)
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
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isDraggable ? dynamicPrimaryColor : dynamicPrimaryColor.opacity(0.6))
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
        VStack(spacing: 2) {
            // Time labels on left
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(stride(from: startHour, through: endHour, by: 2)), id: \.self) { hour in
                        Text(CalendarTimeFormatter.formatHour(hour, date: selectedDate))
                            .font(.system(size: 6))
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(height: hourHeight * 2)
                    }
                }
                .frame(width: 20)
                
                // Calendar timeline
                ZStack(alignment: .topLeading) {
                    // Background grid
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
                    
                    // Existing events
                    ForEach(dayEvents) { event in
                        if let eventStart = event.start.startDate,
                           let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) {
                            EventBar(
                                start: eventStart,
                                end: eventEnd,
                                color: dynamicPrimaryColor.opacity(0.6),
                                isProposed: false
                            )
                        }
                    }
                    
                    // Proposed event
                    EventBar(
                        start: proposedStartTime,
                        end: proposedEndTime,
                        color: dynamicPrimaryColor,
                        isProposed: true
                    )
                }
                .frame(width: 40)
            }
        }
        .frame(height: CGFloat(endHour - startHour + 1) * hourHeight + 20)
        .padding(4)
        .background(dynamicBackgroundColor)
        .cornerRadius(6)
        .onTapGesture {
            onTap()
        }
    }
}

