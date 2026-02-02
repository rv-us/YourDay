//
//  CalendarTimelineView.swift
//  YourDay
//
//  Timeline view component for displaying calendar events
//

import SwiftUI

struct TimelineView: View {
    let events: [GoogleCalendarEvent]
    let selectedDate: Date
    
    private let calendar = Calendar.current
    private let startHour = 0
    private let endHour = 23
    private let hourHeight: CGFloat = 50 // Reduced from 60 to make it more compact
    
    private var timeSlots: [Date] {
        var slots: [Date] = []
        for hour in startHour...endHour {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                slots.append(date)
            }
        }
        return slots
    }
    
    // Group events by overlapping time ranges
    private var eventGroups: [[GoogleCalendarEvent]] {
        var groups: [[GoogleCalendarEvent]] = []
        var processed: Set<String> = []
        
        for event in events.sorted(by: { ($0.start.startDate ?? Date()) < ($1.start.startDate ?? Date()) }) {
            if processed.contains(event.id) { continue }
            
            var group: [GoogleCalendarEvent] = [event]
            processed.insert(event.id)
            
            guard let eventStart = event.start.startDate,
                  let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) else {
                continue
            }
            
            // Find all events that overlap with this one
            for otherEvent in events {
                if processed.contains(otherEvent.id) { continue }
                
                guard let otherStart = otherEvent.start.startDate,
                      let otherEnd = otherEvent.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: otherStart) else {
                    continue
                }
                
                // Check if events overlap
                if (otherStart < eventEnd && otherEnd > eventStart) {
                    group.append(otherEvent)
                    processed.insert(otherEvent.id)
                }
            }
            
            if !group.isEmpty {
                groups.append(group)
            }
        }
        
        return groups
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid background with lines
            VStack(spacing: 0) {
                ForEach(timeSlots, id: \.self) { timeSlot in
                    ZStack(alignment: .topLeading) {
                        // Grid line at the top of each hour
                        Rectangle()
                            .fill(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .frame(height: 1)
                            .padding(.leading, 80)
                        
                        // Time label
                        Text(CalendarTimeFormatter.formatTime(timeSlot))
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(width: 70, alignment: .trailing)
                            .padding(.trailing, 10)
                    }
                    .frame(height: hourHeight)
                }
            }
            
            // Events overlay - handle overlapping events
            ForEach(Array(eventGroups.enumerated()), id: \.offset) { groupIndex, group in
                ForEach(Array(group.enumerated()), id: \.element.id) { eventIndex, event in
                    if let eventStart = event.start.startDate,
                       let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) {
                        EventBlockView(
                            event: event,
                            eventStart: eventStart,
                            eventEnd: eventEnd,
                            selectedDate: selectedDate,
                            hourHeight: hourHeight,
                            availableWidth: UIScreen.main.bounds.width - 96,
                            groupSize: group.count,
                            groupIndex: eventIndex
                        )
                    }
                }
            }
            
            // Current time indicator
            CurrentTimeIndicator(selectedDate: selectedDate, hourHeight: hourHeight)
        }
        .padding(.horizontal, 0)
        .frame(minHeight: CGFloat(timeSlots.count) * hourHeight)
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let selectedDate: Date
    let hourHeight: CGFloat
    
    private let calendar = Calendar.current
    
    private var currentTimePosition: CGFloat? {
        let now = Date()
        guard calendar.isDate(now, inSameDayAs: selectedDate) else { return nil }
        
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let timeInterval = now.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        
        // Keep the current-time indicator aligned with the event blocks' vertical offset,
        // but shift it slightly upward for visual alignment.
        return CGFloat(hoursFromStart) * hourHeight + 15
    }
    
    var body: some View {
        if let position = currentTimePosition {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(dynamicPrimaryColor)
                        .frame(width: 8, height: 8)
                    
                    Rectangle()
                        .fill(dynamicPrimaryColor)
                        .frame(height: 2)
                }
                .offset(x: 70, y: position)
            }
        }
    }
}


