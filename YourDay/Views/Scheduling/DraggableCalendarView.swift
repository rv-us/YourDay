//
//  DraggableCalendarView.swift
//  YourDay
//
//  Full calendar view with draggable proposed event
//

import SwiftUI

struct DraggableCalendarView: View {
    @Binding var proposedStartTime: Date
    @Binding var proposedDuration: Int
    let events: [GoogleCalendarEvent]
    let selectedDate: Date
    /// Shown on the draggable block instead of "Proposed Session" when set.
    var sessionTitle: String? = nil
    /// When true, the block has a bottom handle to change `proposedDuration` in 15-minute steps.
    var allowsDurationResize: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    
    private let calendar = Calendar.current
    private let startHour = 0
    private let endHour = 23
    private let hourHeight: CGFloat = 60
    
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
        let endTime = calendar.date(byAdding: .minute, value: proposedDuration, to: proposedStartTime)
        return endTime ?? proposedStartTime
    }
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Background grid with time labels
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
                    
                    // Existing events
                    ForEach(dayEvents) { event in
                        if let eventStart = event.start.startDate,
                           let eventEnd = event.end?.startDate ?? calendar.date(byAdding: .hour, value: 1, to: eventStart) {
                            DraggableEventBlock(
                                event: event,
                                eventStart: eventStart,
                                eventEnd: eventEnd,
                                selectedDate: selectedDate,
                                hourHeight: hourHeight,
                                isDraggable: false
                            )
                        }
                    }
                    
                    // Proposed event (draggable)
                    DraggableEventBlock(
                        event: nil,
                        eventStart: proposedStartTime,
                        eventEnd: proposedEndTime,
                        selectedDate: selectedDate,
                        hourHeight: hourHeight,
                        isDraggable: true,
                        dragOffset: $dragOffset,
                        isDragging: $isDragging,
                        onDragEnd: { newOffset in
                            // Calculate new time based on drag offset
                            let startOfDay = calendar.startOfDay(for: selectedDate)
                            
                            // Calculate the original position (matching calculateTimeOffset logic)
                            let originalTimeInterval = proposedStartTime.timeIntervalSince(startOfDay)
                            let originalHoursFromStart = originalTimeInterval / 3600.0
                            let originalTopOffset = CGFloat(originalHoursFromStart) * hourHeight + 20
                            
                            // Apply drag offset
                            let newTopOffset = originalTopOffset + newOffset.height
                            
                            // Convert back to time (subtract header offset)
                            let hoursFromStart = (newTopOffset - 20) / hourHeight
                            
                            // Ensure valid range (0-23 hours)
                            let clampedHours = max(0.0, min(23.0, hoursFromStart))
                            
                            // Convert to total minutes and snap to nearest 15 minutes
                            let totalMinutes = Int(clampedHours * 60)
                            let hours = totalMinutes / 60
                            let minutes = totalMinutes % 60
                            let roundedMinutes = (minutes / 15) * 15
                            
                            if let snappedTime = calendar.date(bySettingHour: hours, minute: roundedMinutes, second: 0, of: selectedDate) {
                                proposedStartTime = snappedTime
                            }
                            dragOffset = .zero
                        },
                        draggableSessionTitle: sessionTitle,
                        durationMinutesBinding: allowsDurationResize ? $proposedDuration : nil
                    )
                }
                .padding(.horizontal)
                .frame(minHeight: CGFloat(timeSlots.count) * hourHeight)
            }
            .background(dynamicBackgroundColor)
            .navigationTitle("Adjust Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if allowsDurationResize {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Text("\(proposedDuration) min")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
    }
}

