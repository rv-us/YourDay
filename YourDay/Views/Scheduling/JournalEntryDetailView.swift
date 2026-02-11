//
//  JournalEntryDetailView.swift
//  YourDay
//
//  Detailed view and editor for a single journal entry
//

import SwiftUI

struct JournalEntryDetailView: View {
    @ObservedObject var journalViewModel: JournalViewModel
    let entry: JournalEntry
    
    @State private var isEditing = false
    @State private var whatDid: String = ""
    @State private var howWent: String = ""
    @State private var learned: String = ""
    @State private var distractions: String = ""
    @State private var completionStatus: CompletionStatus = .completed
    @State private var showingDeleteAlert = false
    
    @Environment(\.dismiss) private var dismiss
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter
    }
    
    private var statusColor: Color {
        let status = isEditing ? completionStatus : currentEntry.completionStatus
        switch status {
        case .completed:
            return .green
        case .partial:
            return .orange
        case .notStarted:
            return .red
        }
    }

    private var currentEntry: JournalEntry {
        if let entryId = entry.id,
           let updatedEntry = journalViewModel.journalEntries.first(where: { $0.id == entryId }) {
            return updatedEntry
        }
        if let eventId = entry.eventId,
           let updatedEntry = journalViewModel.journalEntries.first(where: { $0.eventId == eventId }) {
            return updatedEntry
        }
        return entry
    }
    
    init(journalViewModel: JournalViewModel, entry: JournalEntry) {
        self.journalViewModel = journalViewModel
        self.entry = entry
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Card
                VStack(alignment: .leading, spacing: 12) {
                    Text(currentEntry.taskTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                    
                    Text(dateFormatter.string(from: currentEntry.scheduledStartTime))
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text("\(timeFormatter.string(from: currentEntry.scheduledStartTime)) - \(timeFormatter.string(from: currentEntry.scheduledEndTime))")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    
                    if let actualStart = currentEntry.actualStartTime, let actualEnd = currentEntry.actualEndTime {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(dynamicSecondaryTextColor)
                            Text("Actual: \(timeFormatter.string(from: actualStart)) - \(timeFormatter.string(from: actualEnd))")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .padding(.horizontal)
                
                if isEditing {
                    // Edit Mode
                    VStack(alignment: .leading, spacing: 16) {
                        // What Did
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What did you do?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "Describe what you did...", text: $whatDid, axis: .vertical, lineLimit: 3...8)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                        }
                        
                        // How Went
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How did it go?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "Satisfaction, challenges...", text: $howWent, axis: .vertical, lineLimit: 2...6)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                        }
                        
                        // Learned
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What did you learn?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "Insights, discoveries...", text: $learned, axis: .vertical, lineLimit: 2...6)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                        }
                        
                        // Distractions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Distractions?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            AppTextField(placeholder: "What interrupted focus...", text: $distractions, axis: .vertical, lineLimit: 2...6)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                        }
                        
                        // Completion Status (pill style)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Completion Status")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            HStack(spacing: 0) {
                                detailCompletionPill(title: "Completed", status: .completed)
                                detailCompletionPill(title: "Partial", status: .partial)
                                detailCompletionPill(title: "Not Started", status: .notStarted)
                            }
                            .padding(4)
                            .background(Capsule().fill(Color.black.opacity(0.06)))
                        }
                        
                        // Save Button
                        Button(action: {
                            saveChanges()
                        }) {
                            Text("Save Changes")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(dynamicPrimaryColor)
                                .cornerRadius(12)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .disabled(whatDid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal)
                } else {
                    // View Mode
                    VStack(alignment: .leading, spacing: 20) {
                        // What Did
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What did you do?")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            Text(currentEntry.whatDid)
                                .font(.body)
                                .foregroundColor(dynamicTextColor)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(8)
                        }
                        
                        // How Went
                        if let howWent = currentEntry.howWent, !howWent.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "heart.fill")
                                        .foregroundColor(dynamicPrimaryColor)
                                    Text("How did it go?")
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)
                                }
                                Text(howWent)
                                    .font(.body)
                                    .foregroundColor(dynamicTextColor)
                                    .padding()
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Learned
                        if let learned = currentEntry.learned, !learned.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundColor(dynamicPrimaryColor)
                                    Text("What did you learn?")
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)
                                }
                                Text(learned)
                                    .font(.body)
                                    .foregroundColor(dynamicTextColor)
                                    .padding()
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Distractions
                        if let distractions = currentEntry.distractions, !distractions.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Distractions")
                                        .font(.headline)
                                        .foregroundColor(dynamicTextColor)
                                }
                                Text(distractions)
                                    .font(.body)
                                    .foregroundColor(dynamicTextColor)
                                    .padding()
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
                            }
                        }
                        
                        // Completion Status
                        HStack {
                            Text("Status:")
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            Text(currentEntry.completionStatus.rawValue.capitalized)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(statusColor)
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(dynamicBackgroundColor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Journal Entry")
                    .fontWeight(.bold)
                    .foregroundColor(dynamicTextColor)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if !isEditing {
                        Button(action: {
                            startEditing()
                        }) {
                            Image(systemName: "pencil")
                                .foregroundColor(dynamicPrimaryColor)
                        }
                        
                        Button(action: {
                            showingDeleteAlert = true
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    } else {
                        Button("Cancel") {
                            cancelEditing()
                        }
                        .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
            }
        }
        .alert("Delete Journal Entry?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .onAppear {
            loadEntryData()
        }
    }
    
    private func detailCompletionPill(title: String, status: CompletionStatus) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { completionStatus = status }
        } label: {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundColor(completionStatus == status ? .white : .black.opacity(0.65))
                .background(completionStatus == status ? dynamicPrimaryColor : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func loadEntryData() {
        let sourceEntry = currentEntry
        whatDid = sourceEntry.whatDid
        howWent = sourceEntry.howWent ?? ""
        learned = sourceEntry.learned ?? ""
        distractions = sourceEntry.distractions ?? ""
        completionStatus = sourceEntry.completionStatus
    }
    
    private func startEditing() {
        loadEntryData()
        isEditing = true
    }
    
    private func cancelEditing() {
        isEditing = false
        loadEntryData()
    }
    
    private func saveChanges() {
        let sourceEntry = currentEntry
        guard let entryId = sourceEntry.id else { return }
        
        // Create a new entry with updated fields
        let updatedEntry = JournalEntry(
            id: entryId,
            userId: sourceEntry.userId,
            eventId: sourceEntry.eventId,
            taskTitle: sourceEntry.taskTitle,
            scheduledStartTime: sourceEntry.scheduledStartTime,
            scheduledEndTime: sourceEntry.scheduledEndTime,
            actualStartTime: sourceEntry.actualStartTime,
            actualEndTime: sourceEntry.actualEndTime,
            whatDid: whatDid.trimmingCharacters(in: .whitespacesAndNewlines),
            howWent: howWent.isEmpty ? nil : howWent.trimmingCharacters(in: .whitespacesAndNewlines),
            learned: learned.isEmpty ? nil : learned.trimmingCharacters(in: .whitespacesAndNewlines),
            distractions: distractions.isEmpty ? nil : distractions.trimmingCharacters(in: .whitespacesAndNewlines),
            completionStatus: completionStatus,
            timestamp: sourceEntry.timestamp,
            dayOfWeek: sourceEntry.dayOfWeek
        )
        
        journalViewModel.updateJournalEntry(updatedEntry)
        isEditing = false
    }
    
    private func deleteEntry() {
        guard let entryId = currentEntry.id else { return }
        journalViewModel.deleteJournalEntry(entryId)
        dismiss()
    }
}
