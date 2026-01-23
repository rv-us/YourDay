//
//  SmartSchedulingTestView.swift
//  YourDay
//
//  Test view for smart scheduling feature
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct SmartSchedulingTestView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var firebaseManager: FirebaseManager
    
    @StateObject private var backlogViewModel = BacklogViewModel()
    @StateObject private var schedulingViewModel = SchedulingAssistantViewModel()
    
    @Query(sort: \TodoItem.position) private var todoItems: [TodoItem]
    
    @State private var newBacklogTitle = ""
    @State private var newBacklogDescription = ""
    @State private var showingAddBacklogSheet = false
    @State private var newMessage = ""
    @State private var isAgentRunning = false
    @State private var selectedTab = 0 // 0: Setup, 1: Chat
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var scheduledTasks: Set<String> = [] // Track scheduled task titles
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Selector
                Picker("View", selection: $selectedTab) {
                    Text("Setup").tag(0)
                    Text("Chat").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                if selectedTab == 0 {
                    // Setup/Configuration Tab
                    setupTabView
                } else {
                    // Chat Tab
                    chatTabView
                }
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("Smart Scheduling")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        refreshData()
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
            }
            .sheet(isPresented: $showingAddBacklogSheet) {
                AddBacklogItemSheet(backlogViewModel: backlogViewModel)
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePicker("Select Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .onChange(of: selectedDate) { _, _ in
                        showingDatePicker = false
                        fetchCalendarForDate()
                    }
            }
            .onAppear {
                refreshData()
            }
        }
    }
    
    private func fetchCalendarForDate() {
        schedulingViewModel.fetchCalendarEvents(for: selectedDate)
    }
    
    // MARK: - Setup Tab
    
    private var setupTabView: some View {
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
                
                // Schedule Preferences Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedule Preferences")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    
                    if let preference = schedulingViewModel.schedulePreference {
                        VStack(alignment: .leading, spacing: 8) {
                            if let wakeTime = preference.preferredWakeTime {
                                HStack {
                                    Text("Wake Time:")
                                    Spacer()
                                    Text(wakeTime)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                            
                            if let lunchTime = preference.lunchTime {
                                HStack {
                                    Text("Lunch Time:")
                                    Spacer()
                                    Text(lunchTime)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                            
                            if !preference.recurringCommitments.isEmpty {
                                Text("Recurring Commitments:")
                                    .font(.subheadline)
                                    .padding(.top, 4)
                                
                                ForEach(preference.recurringCommitments.indices, id: \.self) { index in
                                    let commitment = preference.recurringCommitments[index]
                                    Text("• \(commitment.eventName): \(commitment.daysOfWeek.joined(separator: ", ")) at \(commitment.time)")
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                        }
                    } else {
                        Text("No preferences set yet. The agent will learn from your responses.")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                
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
                            fetchCalendarForDate()
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
                        fetchCalendarForDate()
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
                    
                    Button(action: {
                        runAgent()
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
                    .disabled(isAgentRunning || backlogViewModel.backlogItems.isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding()
        }
    }
    
    // MARK: - Chat Tab
    
    private var chatTabView: some View {
        VStack(spacing: 0) {
            if !isAgentRunning {
                VStack(spacing: 16) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(dynamicSecondaryTextColor)
                    
                    Text("Agent Not Running")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    
                    Text("Go to the Setup tab to configure your data and run the agent.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Go to Setup") {
                        selectedTab = 0
                    }
                    .foregroundColor(dynamicPrimaryColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(schedulingViewModel.messages) { message in
                                HStack {
                                    if message.role == .user {
                                        Spacer()
                                        Text(message.content)
                                            .padding()
                                            .background(dynamicPrimaryColor)
                                            .cornerRadius(12)
                                            .foregroundColor(.white)
                                    } else {
                                        Text(message.content)
                                            .padding()
                                            .background(dynamicSecondaryBackgroundColor)
                                            .cornerRadius(12)
                                            .foregroundColor(dynamicTextColor)
                                        Spacer()
                                    }
                                }
                            }
                            
                            // Show current proposal as a message if available
                            if let proposal = schedulingViewModel.currentProposal {
                                HStack {
                                    ProposalMessageCard(
                                        proposal: proposal,
                                        schedulingViewModel: schedulingViewModel,
                                        backlogViewModel: backlogViewModel,
                        onAccept: { taskTitles in
                            // Mark tasks as processed (scheduled or skipped)
                            if !taskTitles.isEmpty {
                                for taskTitle in taskTitles {
                                    scheduledTasks.insert(taskTitle)
                                }
                            }
                            // Clear proposal and propose next session
                            schedulingViewModel.currentProposal = nil
                            proposeNextSession()
                        }
                                    )
                                    Spacer()
                                }
                            }
                            
                            // Show decline reason input if needed
                            if schedulingViewModel.showingDeclineReasonInput {
                                HStack {
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 8) {
                                        Text("Why can't you do this session?")
                                            .font(.subheadline)
                                            .foregroundColor(dynamicTextColor)
                                        
                                        TextField("Explain why...", text: $schedulingViewModel.declineReason, axis: .vertical)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .lineLimit(3...6)
                                        
                                        HStack {
                                            Button("Cancel") {
                                                schedulingViewModel.showingDeclineReasonInput = false
                                                schedulingViewModel.declineReason = ""
                                                schedulingViewModel.currentProposal = nil
                                            }
                                            .foregroundColor(dynamicSecondaryTextColor)
                                            
                                            Button("Submit") {
                                                let reason = schedulingViewModel.declineReason
                                                schedulingViewModel.declineReason = ""
                                                
                                                schedulingViewModel.sendMessage(reason, backlogItems: backlogViewModel.backlogItems) { error in
                                                    if let error = error {
                                                        print("Error sending decline reason: \(error.localizedDescription)")
                                                    } else {
                                        // Propose another time for the same tasks (don't mark as scheduled)
                                        // Only propose again if proposal still exists (wasn't skipped)
                                        if let currentProposal = schedulingViewModel.currentProposal {
                                            let remainingTasks = backlogViewModel.backlogItems.filter { item in
                                                currentProposal.tasks.contains(item.title) || !scheduledTasks.contains(item.title)
                                            }
                                            schedulingViewModel.proposeWorkingSession(backlogItems: remainingTasks, for: selectedDate) { error in
                                                if let error = error {
                                                    print("Error proposing new session: \(error.localizedDescription)")
                                                }
                                            }
                                        } else {
                                            // Proposal was cleared (likely skipped), move to next task
                                            proposeNextSession()
                                        }
                                                    }
                                                }
                                            }
                                            .foregroundColor(dynamicPrimaryColor)
                                            .disabled(schedulingViewModel.declineReason.trimmingCharacters(in: .whitespaces).isEmpty)
                                        }
                                    }
                                    .padding()
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(12)
                                }
                            }
                            
                            if schedulingViewModel.isLoading {
                                HStack {
                                    ProgressView()
                                        .padding()
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                    .onChange(of: schedulingViewModel.messages.count) { _ in
                        if let last = schedulingViewModel.messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: schedulingViewModel.currentProposal != nil) { hasProposal in
                        if hasProposal {
                            // Scroll to bottom when proposal appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                withAnimation {
                                    proxy.scrollTo("proposal", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                
                if !schedulingViewModel.showingDeclineReasonInput {
                    HStack {
                        TextField("Ask about scheduling...", text: $newMessage)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button("Send") {
                            sendMessage()
                        }
                        .foregroundColor(dynamicPrimaryColor)
                        .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty || schedulingViewModel.isLoading)
                    }
                    .padding()
                    .background(dynamicBackgroundColor)
                }
            }
        }
    }
    
    private func runAgent() {
        guard !isAgentRunning else { return }
        
        isAgentRunning = true
        scheduledTasks.removeAll()
        
        // Reset chat to start fresh
        schedulingViewModel.resetChat()
        
        // Initialize the agent (without loading history for fresh start)
        if let userId = Auth.auth().currentUser?.uid {
            schedulingViewModel.initialize(userId: userId, loadHistory: false)
        }
        
        // Fetch latest data
        refreshData()
        
        // Switch to chat tab
        selectedTab = 1
        
        // Propose first working session
        proposeNextSession()
    }
    
    private func proposeNextSession() {
        // Get unscheduled tasks
        let unscheduledTasks = backlogViewModel.backlogItems.filter { item in
            !scheduledTasks.contains(item.title)
        }
        
        guard !unscheduledTasks.isEmpty else {
            // All tasks scheduled or skipped
            isAgentRunning = false
            let completionMessage = SchedulingMessage(
                userId: Auth.auth().currentUser?.uid ?? "",
                role: .assistant,
                content: "All tasks have been processed! Great work organizing your day."
            )
            schedulingViewModel.messages.append(completionMessage)
            schedulingViewModel.currentProposal = nil
            return
        }
        
        // Propose a working session for the selected date
        // The proposeWorkingSession method will automatically refresh calendar before proposing
        schedulingViewModel.proposeWorkingSession(backlogItems: unscheduledTasks, for: selectedDate) { error in
            if let error = error {
                print("Error proposing session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isAgentRunning = false
                }
            }
        }
    }
    
    private func sendMessage() {
        guard isAgentRunning else { return }
        
        // Regular message
        guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let message = newMessage
        newMessage = ""
        
        schedulingViewModel.sendMessage(message, backlogItems: backlogViewModel.backlogItems) { error in
            if let error = error {
                print("Error sending message: \(error.localizedDescription)")
            }
        }
    }
    
    private func refreshData() {
        backlogViewModel.fetchBacklogItems(todoItems: todoItems)
        fetchCalendarForDate()
        schedulingViewModel.fetchSchedulePreference()
    }
}

struct BacklogItemRow: View {
    let item: UnifiedBacklogItem
    let backlogViewModel: BacklogViewModel
    
    var body: some View {
        HStack {
            // Icon to distinguish source
            Image(systemName: backlogViewModel.isFirebaseItem(item) ? "square.and.pencil" : "checkmark.circle")
                .foregroundColor(backlogViewModel.isFirebaseItem(item) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                
                Text(item.description)
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .lineLimit(2)
                
                if backlogViewModel.isFirebaseItem(item) {
                    Text("Backlog Item")
                        .font(.caption2)
                        .foregroundColor(dynamicPrimaryColor)
                } else {
                    Text("Current Task")
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }
            
            Spacer()
            
            if backlogViewModel.isFirebaseItem(item) {
                Button(action: {
                    backlogViewModel.deleteBacklogItem(item) { error in
                        if let error = error {
                            print("Error deleting backlog item: \(error.localizedDescription)")
                        }
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(dynamicDestructiveColor)
                }
            }
        }
        .padding()
        .background(dynamicBackgroundColor)
        .cornerRadius(8)
    }
}

struct AddBacklogItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backlogViewModel: BacklogViewModel
    
    @State private var title = ""
    @State private var description = ""
    @State private var priority = 0
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Backlog Item")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                    
                    Stepper("Priority: \(priority)", value: $priority, in: 0...10)
                }
            }
            .navigationTitle("Add Backlog Item")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        backlogViewModel.addBacklogItem(
                            title: title,
                            description: description,
                            priority: priority
                        ) { error in
                            if let error = error {
                                print("Error adding backlog item: \(error.localizedDescription)")
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
