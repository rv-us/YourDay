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
            ZStack(alignment: .topLeading) {
                // Background grid
                VStack(spacing: 0) {
                    ForEach(timeSlots, id: \.self) { timeSlot in
                        ZStack(alignment: .topLeading) {
                            Rectangle()
                                .fill(dynamicSecondaryBackgroundColor.opacity(0.3))
                                .frame(height: hourHeight)
                                .overlay(
                                    Rectangle()
                                        .fill(dynamicSecondaryBackgroundColor.opacity(0.5))
                                        .frame(height: 1),
                                    alignment: .bottom
                                )
                            
                            Text(CalendarTimeFormatter.formatTime(timeSlot))
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .frame(width: 70, alignment: .trailing)
                                .padding(.trailing, 10)
                        }
                    }
                }
                .padding(.leading, 80)
                
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
                        let originalTopOffset = proposedStartTime.timeIntervalSince(startOfDay) / 3600.0 * Double(hourHeight) + 20
                        let newTopOffset = originalTopOffset + Double(newOffset.height)
                        
                        // Convert back to time
                        let hoursFromStart = (newTopOffset - 20) / Double(hourHeight)
                        let totalMinutes = Int(hoursFromStart * 60)
                        
                        // Ensure minutes are within valid range (0-59)
                        let clampedMinutes = max(0, min(59, totalMinutes % 60))
                        let hours = max(0, min(23, totalMinutes / 60))
                        
                        // Snap to nearest 15 minutes
                        let roundedMinutes = (clampedMinutes / 15) * 15
                        
                        if let snappedTime = calendar.date(bySettingHour: hours, minute: roundedMinutes, second: 0, of: selectedDate) {
                            proposedStartTime = snappedTime
                        }
                        dragOffset = .zero
                    }
                )
            }
            .padding()
            .background(dynamicBackgroundColor)
            .navigationTitle("Adjust Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

