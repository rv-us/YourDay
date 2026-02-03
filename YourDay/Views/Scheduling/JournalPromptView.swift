//
//  JournalPromptView.swift
//  YourDay
//
//  Modal view for journaling after a task ends
//

import SwiftUI

struct JournalPromptView: View {
    @ObservedObject var journalViewModel: JournalViewModel
    let pendingEvent: TaskEndMonitor.PendingJournalEvent
    
    @State private var whatDid: String = ""
    @State private var howWent: String = ""
    @State private var learned: String = ""
    @State private var distractions: String = ""
    @State private var completionStatus: CompletionStatus = .completed
    @State private var actualStartTime: Date?
    @State private var actualEndTime: Date?
    @State private var showTimeAdjustment = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case whatDid, howWent, learned, distractions
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "book.fill")
                            .font(.system(size: 40))
                            .foregroundColor(dynamicPrimaryColor)
                        
                        Text("How did it go?")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        
                        Text("Your task session just ended. Let's reflect!")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                        
                        // Queue status indicator
                        if journalViewModel.pendingCount > 1 {
                            Text("\(journalViewModel.pendingCount - 1) more reflection\(journalViewModel.pendingCount - 1 == 1 ? "" : "s") waiting")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Task Info Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Task:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(pendingEvent.taskTitle)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(dynamicTextColor)
                        }
                        
                        HStack {
                            Text("Scheduled:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text("\(timeFormatter.string(from: pendingEvent.scheduledStartTime)) - \(timeFormatter.string(from: pendingEvent.scheduledEndTime))")
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                        }
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Time Adjustment Toggle
                    Toggle("Adjust actual times", isOn: $showTimeAdjustment)
                        .padding(.horizontal)
                        .foregroundColor(dynamicTextColor)
                    
                    if showTimeAdjustment {
                        VStack(spacing: 12) {
                            DatePicker("Actual start time", selection: Binding(
                                get: { actualStartTime ?? pendingEvent.scheduledStartTime },
                                set: { actualStartTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .padding(.horizontal)
                            
                            DatePicker("Actual end time", selection: Binding(
                                get: { actualEndTime ?? pendingEvent.scheduledEndTime },
                                set: { actualEndTime = $0 }
                            ), displayedComponents: .hourAndMinute)
                            .padding(.horizontal)
                        }
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // What did you do? (Required)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you do?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                            + Text(" *")
                            .foregroundColor(.red)
                        
                        TextField("Describe what you accomplished...", text: $whatDid, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .lineLimit(3...6)
                            .focused($focusedField, equals: .whatDid)
                    }
                    .padding(.horizontal)
                    
                    // How did it go? (Optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How did it go?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                        
                        TextField("Satisfaction, challenges, feelings...", text: $howWent, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .lineLimit(2...4)
                            .focused($focusedField, equals: .howWent)
                    }
                    .padding(.horizontal)
                    
                    // What did you learn? (Optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What did you learn?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                        
                        TextField("Insights, discoveries, patterns...", text: $learned, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .lineLimit(2...4)
                            .focused($focusedField, equals: .learned)
                    }
                    .padding(.horizontal)
                    
                    // Distractions? (Optional)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Distractions or interruptions?")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                        
                        TextField("What interrupted your focus...", text: $distractions, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .lineLimit(2...4)
                            .focused($focusedField, equals: .distractions)
                    }
                    .padding(.horizontal)
                    
                    // Completion Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Completion Status")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                        
                        Picker("Status", selection: $completionStatus) {
                            Text("Completed").tag(CompletionStatus.completed)
                            Text("Partial").tag(CompletionStatus.partial)
                            Text("Not Started").tag(CompletionStatus.notStarted)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            // Dismiss immediately
                            journalViewModel.showingJournalPrompt = false
                            // Save entry (will format with LLM)
                            saveEntry()
                        }) {
                            HStack {
                                if journalViewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Text("Save Journal Entry")
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(whatDid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(whatDid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || journalViewModel.isLoading)
                        
                        Button(action: {
                            // Dismiss immediately
                            journalViewModel.showingJournalPrompt = false
                            // Skip the prompt
                            journalViewModel.skipJournalPrompt()
                        }) {
                            Text("Skip for now")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                        .disabled(journalViewModel.isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Dismiss immediately
                        journalViewModel.showingJournalPrompt = false
                        // Skip the prompt
                        journalViewModel.skipJournalPrompt()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }
    
    private func saveEntry() {
        journalViewModel.saveJournalEntry(
            eventId: pendingEvent.eventId,
            taskTitle: pendingEvent.taskTitle,
            scheduledStartTime: pendingEvent.scheduledStartTime,
            scheduledEndTime: pendingEvent.scheduledEndTime,
            actualStartTime: showTimeAdjustment ? actualStartTime : nil,
            actualEndTime: showTimeAdjustment ? actualEndTime : nil,
            whatDid: whatDid,
            howWent: howWent.isEmpty ? nil : howWent,
            learned: learned.isEmpty ? nil : learned,
            distractions: distractions.isEmpty ? nil : distractions,
            completionStatus: completionStatus
        )
    }
}

