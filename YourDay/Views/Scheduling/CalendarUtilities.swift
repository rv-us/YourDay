//
//  CalendarUtilities.swift
//  YourDay
//
//  Utility functions for calendar event filtering and time formatting
//

import Foundation
import SwiftUI

// MARK: - Calendar Event Filter

struct CalendarEventFilter {
    /// Filters events to only include those that occur on the specified date
    static func filterEventsForDay(_ events: [GoogleCalendarEvent], date: Date) -> [GoogleCalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        return events.filter { event in
            guard let eventStart = event.start.startDate else { return false }
            
            // Check if event starts on this day or overlaps with this day
            let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart)!
            
            // Event overlaps if it starts before endOfDay and ends after startOfDay
            return eventStart < endOfDay && eventEnd > startOfDay
        }
    }
    
    /// Calculates the vertical offset for an event from the start hour
    static func calculateOffsetFromStartHour(start: Date, date: Date, startHour: Int, hourHeight: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Get the hour component of the start time
        let hour = calendar.component(.hour, from: start)
        let minute = calendar.component(.minute, from: start)
        
        // Calculate offset from start hour
        let hoursFromStart = Double(hour - startHour) + (Double(minute) / 60.0)
        return CGFloat(hoursFromStart) * hourHeight
    }
    
    /// Calculates the height of an event block based on its duration
    static func calculateEventHeight(start: Date, end: Date, hourHeight: CGFloat) -> CGFloat {
        let timeInterval = end.timeIntervalSince(start)
        let hours = timeInterval / 3600.0
        return CGFloat(hours) * hourHeight
    }
    
    /// Calculates the time offset for an event on a specific date with header offset
    static func calculateTimeOffset(start: Date, date: Date, hourHeight: CGFloat, headerOffset: CGFloat) -> CGFloat {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        let timeInterval = start.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        
        return CGFloat(hoursFromStart) * hourHeight + headerOffset
    }
}

// MARK: - Calendar Time Formatter

struct CalendarTimeFormatter {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    private static let hourFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter
    }()
    
    /// Formats a single time (e.g., "2:30 PM")
    static func formatTime(_ date: Date) -> String {
        return timeFormatter.string(from: date)
    }
    
    /// Formats a time range (e.g., "2:30 PM - 4:00 PM")
    static func formatTimeRange(start: Date, end: Date) -> String {
        let startString = formatTime(start)
        let endString = formatTime(end)
        return "\(startString) - \(endString)"
    }
    
    /// Formats an hour for a specific date (e.g., "2PM")
    static func formatHour(_ hour: Int, date: Date) -> String {
        let calendar = Calendar.current
        if let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) {
            return hourFormatter.string(from: hourDate)
        }
        return "\(hour)AM"
    }
}


