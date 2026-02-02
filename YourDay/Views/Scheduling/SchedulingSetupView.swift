//
//  SchedulingSetupView.swift
//  YourDay
//
//  Setup tab view for smart scheduling
//

import SwiftUI

struct SchedulingSetupView: View {
    @ObservedObject var backlogViewModel: BacklogViewModel
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @Binding var selectedDate: Date
    @Binding var showingDatePicker: Bool
    @Binding var showingAddBacklogSheet: Bool
    @Binding var isAgentRunning: Bool
    
    let onFetchCalendar: () -> Void
    let onRunAgent: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Backlog Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Backlog Items")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        
                        Spacer()
                        
                        Button(action: {
                            showingAddBacklogSheet = true
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(dynamicPrimaryColor)
                                .font(.title3)
                        }
                    }
                    
                    if backlogViewModel.isLoading {
                        ProgressView()
                            .padding()
                    } else if backlogViewModel.backlogItems.isEmpty {
                        Text("No backlog items. Add items or they'll appear from your current tasks.")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(backlogViewModel.backlogItems) { item in
                            BacklogItemRow(item: item, backlogViewModel: backlogViewModel)
                        }
                    }
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                
                // Day Context Section (expandable)
                DayContextSection(schedulingViewModel: schedulingViewModel)

                // MARK: - Agent Memory Section
                AgentMemorySection(schedulingViewModel: schedulingViewModel, selectedDate: selectedDate)
                
                // Date Selection Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Select Date")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    
                    Button(action: {
                        showingDatePicker = true
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                            Text(selectedDate, style: .date)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundColor(dynamicTextColor)
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                
                // Calendar Events Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Calendar Events for Selected Date")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        
                        Spacer()
                        
                        Button(action: {
                            onFetchCalendar()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(dynamicPrimaryColor)
                        }
                    }
                    
                    if schedulingViewModel.calendarEvents.isEmpty {
                        Text("No events for this date. Tap refresh to check calendar.")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    } else {
                        ForEach(schedulingViewModel.calendarEvents.prefix(10)) { event in
                            HStack {
                                if let startDate = event.start.startDate {
                                    Text(startDate, style: .time)
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .frame(width: 60, alignment: .leading)
                                }
                                Text(event.summary)
                                    .font(.caption)
                                    .foregroundColor(dynamicTextColor)
                                Spacer()
                            }
                        }
                    }
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onFetchCalendar()
                    }) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                            Text("Check Calendar for Selected Date")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(dynamicPrimaryColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button(action: {
                        onRunAgent()
                    }) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text(isAgentRunning ? "Agent Running..." : "Run Agent")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isAgentRunning ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                        .cornerRadius(12)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isAgentRunning || backlogViewModel.backlogItems.isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding()
        }
    }
}


