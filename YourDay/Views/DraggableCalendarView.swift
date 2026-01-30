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
                            
                            Text(timeString(from: timeSlot))
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
                        let newTopOffset = originalTopOffset + newOffset.y
                        
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
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

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
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let timeInterval = eventStart.timeIntervalSince(startOfDay)
        let hoursFromStart = timeInterval / 3600.0
        return CGFloat(hoursFromStart) * hourHeight + 20 + (isDraggable ? dragOffset.y : 0)
    }
    
    private var height: CGFloat {
        let duration = eventEnd.timeIntervalSince(eventStart)
        let hours = duration / 3600.0
        return CGFloat(hours) * hourHeight
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: eventStart)) - \(formatter.string(from: eventEnd))"
    }
}

