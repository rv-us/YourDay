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
    var hourHeight: CGFloat = 50
    var onScheduledTaskTap: ((GoogleCalendarEvent) -> Void)? = nil
    
    private let calendar = Calendar.current
    private let startHour = 0
    private let endHour = 23
    private static let eventGap: CGFloat = 4
    
    private var timeSlots: [Date] {
        var slots: [Date] = []
        for hour in startHour...endHour {
            if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                slots.append(date)
            }
        }
        return slots
    }
    
    // Group events by overlapping time ranges (transitive: A–B and B–C → one group)
    private var eventGroups: [[GoogleCalendarEvent]] {
        let sorted = events.sorted(by: { ($0.start.startDate ?? Date()) < ($1.start.startDate ?? Date()) })
        var processed: Set<String> = []
        var groups: [[GoogleCalendarEvent]] = []
        
        for event in sorted {
            if processed.contains(event.id) { continue }
            
            guard let eventStart = event.start.startDate,
                  let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) else {
                continue
            }
            
            var group: [GoogleCalendarEvent] = [event]
            processed.insert(event.id)
            
            // Repeatedly add any event that overlaps any member of the group (transitive)
            var changed = true
            while changed {
                changed = false
                for otherEvent in events {
                    if processed.contains(otherEvent.id) { continue }
                    guard let otherStart = otherEvent.start.startDate,
                          let otherEnd = otherEvent.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: otherStart) else {
                        continue
                    }
                    let overlapsAny = group.contains { e in
                        guard let s = e.start.startDate,
                              let eEnd = e.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: s) else { return false }
                        return otherStart < eEnd && otherEnd > s
                    }
                    if overlapsAny {
                        group.append(otherEvent)
                        processed.insert(otherEvent.id)
                        changed = true
                    }
                }
            }
            
            if !group.isEmpty {
                groups.append(group.sorted(by: { ($0.start.startDate ?? Date()) < ($1.start.startDate ?? Date()) }))
            }
        }
        
        return groups
    }
    
    private var gridScale: CGFloat {
        min(1.2, max(0.6, hourHeight / 50))
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Grid background with lines - scale with hour height
            VStack(spacing: 0) {
                ForEach(timeSlots, id: \.self) { timeSlot in
                    ZStack(alignment: .topLeading) {
                        // Grid line at the top of each hour
                        Rectangle()
                            .fill(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .frame(height: max(1, gridScale))
                            .padding(.leading, 80)
                        
                        // Time label
                        Text(CalendarTimeFormatter.formatTime(timeSlot))
                            .font(.system(size: 12 * gridScale))
                            .foregroundColor(dynamicSecondaryTextColor)
                            .frame(width: 70, alignment: .trailing)
                            .padding(.trailing, 10 * gridScale)
                    }
                    .frame(height: hourHeight)
                }
            }
            .allowsHitTesting(false)
            
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
                            groupIndex: eventIndex,
                            eventGap: Self.eventGap,
                            onScheduledTaskTap: onScheduledTaskTap
                        )
                    }
                }
            }
            
            // Current time indicator - allow taps to pass through
            CurrentTimeIndicator(selectedDate: selectedDate, hourHeight: hourHeight)
                .allowsHitTesting(false)
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
    private static let baseline: CGFloat = 50
    
    private var scale: CGFloat {
        min(1.2, max(0.6, hourHeight / Self.baseline))
    }
    
    private var currentTimePosition: CGFloat? {
        let now = Date()
        guard calendar.isDate(now, inSameDayAs: selectedDate) else { return nil }
        
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let timeInterval = now.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        
        return CGFloat(hoursFromStart) * hourHeight + 15 * scale
    }
    
    var body: some View {
        if let position = currentTimePosition {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Circle()
                        .fill(dynamicPrimaryColor)
                        .frame(width: 8 * scale, height: 8 * scale)
                    
                    Rectangle()
                        .fill(dynamicPrimaryColor)
                        .frame(height: max(1, 2 * scale))
                }
                .offset(x: 70, y: position)
            }
        }
    }
}



