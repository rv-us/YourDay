//
//  CompactCalendarPreview.swift
//  YourDay
//
//  Compact calendar preview for proposal cards
//

import SwiftUI

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
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return events.filter { event in
            guard let eventStart = event.start.startDate else { return false }
            return eventStart >= startOfDay && eventStart < endOfDay
        }
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
                        Text(formatHour(hour))
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
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        if let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
            return formatter.string(from: date).lowercased()
        }
        return "\(hour)"
    }
}

struct EventBar: View {
    let start: Date
    let end: Date
    let color: Color
    let isProposed: Bool
    
    private let calendar = Calendar.current
    private let startHour = 6
    private let hourHeight: CGFloat = 8
    
    private var topOffset: CGFloat {
        let startOfDay = calendar.startOfDay(for: start)
        let timeInterval = start.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        let offsetFromStartHour = hoursFromStart - Double(startHour)
        return max(0, CGFloat(offsetFromStartHour) * hourHeight)
    }
    
    private var height: CGFloat {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600.0
        return max(2, CGFloat(hours) * hourHeight)
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


