//
//  JournalView.swift
//  YourDay
//
//  List view of all journal entries
//

import SwiftUI

struct JournalView: View {
    @ObservedObject var journalViewModel: JournalViewModel
    @State private var selectedDate: Date? = nil
    @State private var filterStatus: CompletionStatus? = nil
    @State private var searchText = ""
    @State private var showingDatePicker = false
    
    private var filteredEntries: [JournalEntry] {
        var entries = journalViewModel.journalEntries
        
        // Filter by search text
        if !searchText.isEmpty {
            entries = entries.filter { entry in
                entry.taskTitle.localizedCaseInsensitiveContains(searchText) ||
                entry.whatDid.localizedCaseInsensitiveContains(searchText) ||
                (entry.howWent?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (entry.learned?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Filter by completion status
        if let status = filterStatus {
            entries = entries.filter { $0.completionStatus == status }
        }
        
        // Filter by date (matches the scheduled day the session was for).
        if let day = selectedDate {
            let calendar = Calendar.current
            entries = entries.filter { entry in
                calendar.isDate(entry.scheduledStartTime, inSameDayAs: day)
            }
        }
        
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
    
    private var dateFilterLabel: String {
        guard let day = selectedDate else { return "All dates" }
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                VStack(spacing: 12) {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(dynamicSecondaryTextColor)
                        AppTextField(placeholder: "Search journal entries...", text: $searchText)
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    
                    // Filter Picker (pill style like Todoview). "Not Started" is
                    // kept for legacy visibility even though new skip/reschedule
                    // flows no longer create notStarted entries.
                    HStack(spacing: 0) {
                        statusPillButton(title: "All", isSelected: filterStatus == nil) { filterStatus = nil }
                        statusPillButton(title: "Completed", isSelected: filterStatus == .completed) { filterStatus = .completed }
                        statusPillButton(title: "Partial", isSelected: filterStatus == .partial) { filterStatus = .partial }
                        statusPillButton(title: "Not Started", isSelected: filterStatus == .notStarted) { filterStatus = .notStarted }
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.black.opacity(0.06)))
                    .padding(.horizontal)
                    
                    // Date filter row
                    HStack(spacing: 8) {
                        Button(action: { showingDatePicker = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                Text(dateFilterLabel)
                                    .fontWeight(.semibold)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .foregroundColor(dynamicPrimaryColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(dynamicPrimaryColor.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        
                        if selectedDate != nil {
                            Button(action: { selectedDate = nil }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Clear")
                                }
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(dynamicBackgroundColor)
                
                // Journal Entries List
                if journalViewModel.isLoading && journalViewModel.journalEntries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredEntries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 50))
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(searchText.isEmpty ? "No journal entries yet" : "No entries found")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)
                        Text("Start scheduling tasks to begin journaling!")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredEntries) { entry in
                                NavigationLink(destination: JournalEntryDetailView(
                                    journalViewModel: journalViewModel,
                                    entry: entry
                                )) {
                                    JournalEntryRow(entry: entry)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(dynamicBackgroundColor)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Journal")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        journalViewModel.fetchJournalEntries()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
            .onAppear {
                // Always refetch on entry so the list reflects anything saved or
                // deleted elsewhere in this session; otherwise the locally-inserted
                // entry would be the only one visible.
                journalViewModel.fetchJournalEntries()
            }
            .sheet(isPresented: $showingDatePicker) {
                DateFilterPickerSheet(
                    initialDate: selectedDate ?? Date(),
                    onDone: { picked in
                        selectedDate = picked
                        showingDatePicker = false
                    },
                    onClear: {
                        selectedDate = nil
                        showingDatePicker = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }
    
    private func statusPillButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        }) {
            Text(title)
                .fontWeight(.semibold)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundColor(isSelected ? .white : .black.opacity(0.65))
                .background(isSelected ? dynamicPrimaryColor : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntry
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private var statusColor: Color {
        switch entry.completionStatus {
        case .completed:
            return .green
        case .partial:
            return .orange
        case .notStarted:
            return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.taskTitle)
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .lineLimit(1)
                    
                    Text(dateFormatter.string(from: entry.scheduledStartTime))
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                
                Spacer()
                
                // Status Badge
                Text(entry.completionStatus.rawValue.capitalized)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor)
                    .cornerRadius(8)
            }
            
            // Time Range
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                Text("\(timeFormatter.string(from: entry.scheduledStartTime)) - \(timeFormatter.string(from: entry.scheduledEndTime))")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
            
            // What Did Preview
            Text(entry.whatDid)
                .font(.subheadline)
                .foregroundColor(dynamicTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            // Additional Info Indicators
            HStack(spacing: 12) {
                if entry.howWent != nil {
                    Label("Reflection", systemImage: "heart.fill")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                if entry.learned != nil {
                    Label("Insights", systemImage: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                if entry.distractions != nil {
                    Label("Distractions", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Date Filter Picker Sheet

private struct DateFilterPickerSheet: View {
    let initialDate: Date
    let onDone: (Date) -> Void
    let onClear: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Date
    
    init(initialDate: Date, onDone: @escaping (Date) -> Void, onClear: @escaping () -> Void) {
        self.initialDate = initialDate
        self.onDone = onDone
        self.onClear = onClear
        _picked = State(initialValue: initialDate)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                DatePicker(
                    "Filter by date",
                    selection: $picked,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(dynamicPrimaryColor)
                .padding(.horizontal)
                
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(dynamicBackgroundColor)
            .navigationTitle("Filter by Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { onClear() }
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { onDone(picked) }
                        .foregroundColor(dynamicPrimaryColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

