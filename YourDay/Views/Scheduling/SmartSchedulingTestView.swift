//
//  SmartSchedulingTestView.swift
//  YourDay
//
//  Test view for smart scheduling feature
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct ModificationContext: Identifiable {
    let id = UUID()
    let tasks: [String]
    let originalTime: String
    let modifiedTime: String
}

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
    @State private var planningDate: Date? = nil // Fixed date for current agent session
    @State private var pendingModifications: [ModificationContext] = [] // Store all modifications to process at end
    @State private var showingModificationReview = false
    @State private var currentModificationIndex = 0
    @State private var modificationReason = ""
    
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
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                } else {
                    // Chat Tab
                    chatTabView
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
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
                        // Only update planning date if agent is not running
                        // This ensures the planning date stays fixed during agent operations
                        if !isAgentRunning {
                            planningDate = nil
                        }
                    }
            }
            .sheet(isPresented: $showingModificationReview) {
                ModificationReviewSheet(
                    modifications: $pendingModifications,
                    currentIndex: $currentModificationIndex,
                    reason: $modificationReason,
                    schedulingViewModel: schedulingViewModel,
                    onComplete: {
                        showingModificationReview = false
                        pendingModifications.removeAll()
                        currentModificationIndex = 0
                        modificationReason = ""
                    }
                )
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
                    .buttonStyle(ScaleButtonStyle())

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
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(isAgentRunning || backlogViewModel.backlogItems.isEmpty)
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .padding()
        }
    }
    
    // MARK: - Chat Tab

    private var defaultProposal: ProposedSession {
        ProposedSession(tasks: [], workingSessionTime: "", startTime: nil, endTime: nil, reason: nil)
    }

    private var proposalBinding: Binding<ProposedSession> {
        Binding(
            get: {
                schedulingViewModel.currentProposal ?? defaultProposal
            },
            set: { newValue in
                schedulingViewModel.currentProposal = newValue
            }
        )
    }

    private var chatTabView: some View {
        VStack(spacing: 0) {
            if !isAgentRunning {
                agentNotRunningView
            } else {
                chatMessagesView
                chatInputView
            }
        }
    }

    private var agentNotRunningView: some View {
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
                withAnimation(.easeInOut(duration: 0.25)) {
                    selectedTab = 0
                }
            }
            .buttonStyle(ScaleButtonStyle())
            .foregroundColor(dynamicPrimaryColor)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                chatMessagesContent
            }
            .onChange(of: schedulingViewModel.messages.count) { _, _ in
                scrollToLastMessage(proxy: proxy)
            }
            .onChange(of: schedulingViewModel.statusMessage) { _, newValue in
                if newValue != nil {
                    scrollToStatus(proxy: proxy)
                }
            }
            .onChange(of: schedulingViewModel.currentProposal != nil) { _, hasProposal in
                if hasProposal {
                    scrollToProposal(proxy: proxy)
                }
            }
        }
    }

    private var chatMessagesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(schedulingViewModel.messages.enumerated()), id: \.offset) { index, message in
                chatMessageBubble(message: message, index: index)
            }

            statusMessageView
            proposalCardView
            declineReasonInputView
            loadingIndicatorView
        }
        .padding()
    }

    private func chatMessageBubble(message: SchedulingMessage, index: Int) -> some View {
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
        .id("message_\(index)")
        .transition(
            .asymmetric(
                insertion: message.role == .user
                    ? .move(edge: .trailing).combined(with: .opacity)
                    : .move(edge: .leading).combined(with: .opacity),
                removal: .opacity
            )
        )
    }

    @ViewBuilder
    private var statusMessageView: some View {
        if let statusMessage = schedulingViewModel.statusMessage {
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(statusMessage)
                        .italic()
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .foregroundColor(dynamicSecondaryTextColor)
                Spacer()
            }
            .id("status")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    @ViewBuilder
    private var proposalCardView: some View {
        if schedulingViewModel.currentProposal != nil {
            HStack {
                ProposalMessageCard(
                    proposal: proposalBinding,
                    schedulingViewModel: schedulingViewModel,
                    backlogViewModel: backlogViewModel,
                    onAccept: { taskTitles in
                        handleAcceptedTasks(taskTitles)
                    },
                    onRequestModificationReason: { context in
                        // Store modification for later review and continue immediately
                        pendingModifications.append(context)
                        handleAcceptedTasks(context.tasks)
                    },
                    isDisabled: schedulingViewModel.showingDeclineReasonInput
                )
                Spacer()
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var declineReasonInputView: some View {
        if schedulingViewModel.showingDeclineReasonInput {
            HStack {
                Spacer()
                declineReasonContent
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var declineReasonContent: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text("Why can't you do this session?")
                .font(.subheadline)
                .foregroundColor(dynamicTextColor)

            TextField("Explain why...", text: $schedulingViewModel.declineReason, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)

            declineReasonButtons
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }

    private var declineReasonButtons: some View {
        HStack {
            Button("Cancel") {
                schedulingViewModel.showingDeclineReasonInput = false
                schedulingViewModel.declineReason = ""
                schedulingViewModel.currentProposal = nil
            }
            .foregroundColor(dynamicSecondaryTextColor)

            Button("Submit") {
                submitDeclineReason()
            }
            .foregroundColor(dynamicPrimaryColor)
            .disabled(schedulingViewModel.declineReason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submitDeclineReason() {
        let reason = schedulingViewModel.declineReason
        schedulingViewModel.declineReason = ""

        schedulingViewModel.sendMessage(reason, backlogItems: backlogViewModel.backlogItems) { error in
            if let error = error {
                print("Error sending decline reason: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private var loadingIndicatorView: some View {
        if schedulingViewModel.isLoading {
            HStack(spacing: 8) {
                TypingIndicatorView()
                Text("Thinking...")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .italic()
                Spacer()
            }
            .padding()
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    @ViewBuilder
    private var chatInputView: some View {
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

    private func scrollToLastMessage(proxy: ScrollViewProxy) {
        let lastIndex = schedulingViewModel.messages.count - 1
        if lastIndex >= 0 {
            withAnimation {
                proxy.scrollTo("message_\(lastIndex)", anchor: .bottom)
            }
        }
    }

    private func scrollToStatus(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo("status", anchor: .bottom)
            }
        }
    }

    private func scrollToProposal(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo("proposal", anchor: .bottom)
            }
        }
    }
    
    private func runAgent() {
        guard !isAgentRunning else { return }
        
        isAgentRunning = true
        scheduledTasks.removeAll()
        
        // Store the selected date at agent start - this will remain fixed during agent operations
        planningDate = selectedDate
        
        // Reset chat to start fresh
        schedulingViewModel.resetChat()
        
        // Initialize the agent (without loading history for fresh start)
        if let userId = Auth.auth().currentUser?.uid {
            schedulingViewModel.initialize(userId: userId, loadHistory: false)
        }
        
        // Fetch latest data
        refreshData()
        
        // Switch to chat tab
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedTab = 1
        }
        
        // Propose first working session using the fixed planning date
        proposeNextSession()
    }

    private func handleAcceptedTasks(_ taskTitles: [String]) {
        if !taskTitles.isEmpty {
            for taskTitle in taskTitles {
                scheduledTasks.insert(taskTitle)
            }
        }
        schedulingViewModel.currentProposal = nil
        proposeNextSession()
    }
    
    private func proposeNextSession() {
        // Use the fixed planning date if agent is running, otherwise use selectedDate
        // This ensures the date stays consistent throughout the agent session
        let dateToUse = planningDate ?? selectedDate
        
        // Get unscheduled tasks
        let unscheduledTasks = backlogViewModel.backlogItems.filter { item in
            !scheduledTasks.contains(item.title)
        }
        
        guard !unscheduledTasks.isEmpty else {
            // All tasks scheduled or skipped
            isAgentRunning = false
            planningDate = nil // Clear planning date when agent stops
            let completionMessage = SchedulingMessage(
                userId: Auth.auth().currentUser?.uid ?? "",
                role: .assistant,
                content: "All tasks have been processed! Great work organizing your day."
            )
            schedulingViewModel.messages.append(completionMessage)
            schedulingViewModel.currentProposal = nil

            // Show modification review if there are pending modifications
            if !pendingModifications.isEmpty {
                currentModificationIndex = 0
                modificationReason = ""
                showingModificationReview = true
            }
            return
        }
        
        // Propose a working session for the planning date (fixed during agent run)
        // The proposeWorkingSession method will automatically refresh calendar before proposing
        schedulingViewModel.proposeWorkingSession(backlogItems: unscheduledTasks, for: dateToUse) { error in
            if let error = error {
                print("Error proposing session: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isAgentRunning = false
                    self.planningDate = nil // Clear planning date on error
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
    @State private var estimatedDuration: Int? = nil
    @State private var category = ""
    @State private var tagsText = ""

    private let categoryOptions = ["", "work", "personal", "health", "errands", "learning", "creative"]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description)
                }

                Section(header: Text("Scheduling Metadata")) {
                    Stepper("Priority: \(priority)", value: $priority, in: 0...10)

                    HStack {
                        Text("Est. Duration")
                        Spacer()
                        TextField("min", value: $estimatedDuration, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("min")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { cat in
                            Text(cat.isEmpty ? "None" : cat.capitalized).tag(cat)
                        }
                    }

                    TextField("Tags (comma separated)", text: $tagsText)
                        .font(.subheadline)
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
                        let tags = tagsText.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

                        backlogViewModel.addBacklogItem(
                            title: title,
                            description: description,
                            priority: priority,
                            estimatedDuration: estimatedDuration,
                            category: category.isEmpty ? nil : category,
                            tags: tags.isEmpty ? nil : tags
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

// MARK: - Agent Memory Section

struct AgentMemorySection: View {
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    let selectedDate: Date

    @State private var expandedSections: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Agent Memory")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(dynamicTextColor)

            Text("Everything the agent references when making scheduling decisions")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)

            // 1. Basic Preferences
            ExpandableSection(
                title: "Basic Preferences",
                icon: "gearshape.fill",
                isExpanded: expandedSections.contains("preferences"),
                onToggle: { toggleSection("preferences") }
            ) {
                basicPreferencesContent
            }

            // 2. Schedule Constraints
            ExpandableSection(
                title: "Schedule Constraints",
                icon: "exclamationmark.triangle.fill",
                isExpanded: expandedSections.contains("constraints"),
                onToggle: { toggleSection("constraints") }
            ) {
                scheduleConstraintsContent
            }

            // 3. Recurring Commitments
            ExpandableSection(
                title: "Recurring Commitments",
                icon: "repeat",
                isExpanded: expandedSections.contains("recurring"),
                onToggle: { toggleSection("recurring") }
            ) {
                recurringCommitmentsContent
            }

            // 4. Learned Patterns
            ExpandableSection(
                title: "Learned Patterns",
                icon: "brain.head.profile",
                isExpanded: expandedSections.contains("patterns"),
                onToggle: { toggleSection("patterns") }
            ) {
                learnedPatternsContent
            }

            // 5. Schedule Notes
            ExpandableSection(
                title: "Schedule Notes (Selected Date)",
                icon: "note.text",
                isExpanded: expandedSections.contains("notes"),
                onToggle: { toggleSection("notes") }
            ) {
                scheduleNotesContent
            }

            // 6. Acceptance Stats
            ExpandableSection(
                title: "Learning Statistics",
                icon: "chart.bar.fill",
                isExpanded: expandedSections.contains("stats"),
                onToggle: { toggleSection("stats") }
            ) {
                acceptanceStatsContent
            }

            // 7. Recent Interactions
            ExpandableSection(
                title: "Recent Interactions",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSections.contains("interactions"),
                onToggle: { toggleSection("interactions") }
            ) {
                recentInteractionsContent
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .onAppear {
            schedulingViewModel.fetchScheduleNotes(for: selectedDate)
        }
        .onChange(of: selectedDate) { _, newDate in
            schedulingViewModel.fetchScheduleNotes(for: newDate)
        }
    }

    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    // MARK: - Basic Preferences Content

    @ViewBuilder
    private var basicPreferencesContent: some View {
        if let pref = schedulingViewModel.schedulePreference {
            VStack(alignment: .leading, spacing: 8) {
                DataRow(label: "Wake Time", value: pref.preferredWakeTime ?? "Not set")
                DataRow(label: "Lunch Time", value: pref.lunchTime ?? "Not set")

                if let workTimes = pref.preferredWorkTimes, !workTimes.isEmpty {
                    DataRow(label: "Preferred Work Times", value: workTimes.joined(separator: ", "))
                }

                if let blockedTimes = pref.blockedTimes, !blockedTimes.isEmpty {
                    DataRow(label: "Blocked Times", value: blockedTimes.joined(separator: ", "))
                }
            }
        } else {
            Text("No preferences saved yet")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    // MARK: - Schedule Constraints Content

    @ViewBuilder
    private var scheduleConstraintsContent: some View {
        if let pref = schedulingViewModel.schedulePreference, !pref.scheduleConstraints.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pref.scheduleConstraints.indices, id: \.self) { index in
                    let constraint = pref.scheduleConstraints[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text("• \(constraint.reason)")
                            .font(.caption)
                            .foregroundColor(dynamicTextColor)

                        HStack(spacing: 8) {
                            if let timeRange = constraint.timeRange {
                                Label(timeRange, systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                            if let context = constraint.context {
                                Text(context)
                                    .font(.caption2)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .italic()
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            Text("No constraints learned yet. The agent learns when you decline proposals.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    // MARK: - Recurring Commitments Content

    @ViewBuilder
    private var recurringCommitmentsContent: some View {
        if let pref = schedulingViewModel.schedulePreference, !pref.recurringCommitments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(pref.recurringCommitments.indices, id: \.self) { index in
                    let commitment = pref.recurringCommitments[index]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(commitment.eventName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(dynamicTextColor)

                            Text("\(commitment.daysOfWeek.joined(separator: ", ")) at \(commitment.time)")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }

                        Spacer()

                        Text(commitment.frequency)
                            .font(.caption2)
                            .foregroundColor(dynamicPrimaryColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(dynamicPrimaryColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            Text("No recurring commitments saved. Mention regular activities in chat.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    // MARK: - Learned Patterns Content

    @ViewBuilder
    private var learnedPatternsContent: some View {
        if let pref = schedulingViewModel.schedulePreference,
           let patterns = pref.learnedPatterns, !patterns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(patterns.keys.sorted()), id: \.self) { key in
                    if let value = patterns[key] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatPatternKey(key))
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Text(value)
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } else {
            Text("No patterns learned yet. These are extracted from your decline reasons.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    private func formatPatternKey(_ key: String) -> String {
        if key.starts(with: "decline_reason_") {
            return "Decline Reason"
        }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Schedule Notes Content

    @ViewBuilder
    private var scheduleNotesContent: some View {
        if !schedulingViewModel.scheduleNotes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(schedulingViewModel.scheduleNotes) { note in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.note)
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)

                            if let timeRange = note.timeRange {
                                Label(timeRange, systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                        }

                        Spacer()

                        if note.isBlocking {
                            Text("BLOCKING")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } else {
            Text("No notes for this date. Mention appointments in chat to save them.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    // MARK: - Acceptance Stats Content

    @ViewBuilder
    private var acceptanceStatsContent: some View {
        if let pref = schedulingViewModel.schedulePreference,
           let stats = pref.acceptanceStats {
            VStack(alignment: .leading, spacing: 12) {
                // Summary Row
                HStack(spacing: 16) {
                    StatBadge(label: "Accepted", value: stats.totalAccepted, color: .green)
                    StatBadge(label: "Declined", value: stats.totalDeclined, color: .red)
                    StatBadge(label: "Modified", value: stats.totalModified, color: .orange)
                    StatBadge(label: "Skipped", value: stats.totalSkipped, color: .gray)
                }

                if let avgDuration = stats.averageAcceptedDuration {
                    DataRow(label: "Avg Session Duration", value: "\(avgDuration) min")
                }

                // Preferred Hours
                if !stats.preferredHours.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preferred Hours:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)

                        let sortedHours = stats.preferredHours.sorted { $0.value > $1.value }
                        HStack(spacing: 8) {
                            ForEach(sortedHours.prefix(5), id: \.key) { hour, count in
                                Text(formatHour(hour))
                                    .font(.caption2)
                                    .foregroundColor(dynamicTextColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(dynamicPrimaryColor.opacity(Double(count) / Double(sortedHours.first?.value ?? 1) * 0.3 + 0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }

                // Preferred Durations
                if !stats.preferredDurations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preferred Durations:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)

                        let sortedDurations = stats.preferredDurations.sorted { $0.value > $1.value }
                        HStack(spacing: 8) {
                            ForEach(sortedDurations.prefix(5), id: \.key) { duration, count in
                                Text("\(duration)m")
                                    .font(.caption2)
                                    .foregroundColor(dynamicTextColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(dynamicPrimaryColor.opacity(Double(count) / Double(sortedDurations.first?.value ?? 1) * 0.3 + 0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
        } else {
            Text("No statistics yet. Accept or decline proposals to build learning data.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return formatter.string(from: date)
    }

    // MARK: - Recent Interactions Content

    @ViewBuilder
    private var recentInteractionsContent: some View {
        if !schedulingViewModel.recentInteractions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(schedulingViewModel.recentInteractions.prefix(10)) { interaction in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            actionBadge(interaction.action)

                            Text(interaction.proposedTasks.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                                .lineLimit(1)

                            Spacer()

                            Text(interaction.dayOfWeek.prefix(3).capitalized)
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }

                        HStack(spacing: 8) {
                            Text(interaction.proposedTime)
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)

                            Text("\(interaction.proposedDuration) min")
                                .font(.caption2)
                                .foregroundColor(dynamicSecondaryTextColor)

                            if let modifiedTime = interaction.modifiedTime {
                                Text("→ \(modifiedTime)")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }

                            if let modifiedDuration = interaction.modifiedDuration {
                                Text("→ \(modifiedDuration) min")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }

                        if let reason = interaction.declineReason {
                            Text("Reason: \(reason)")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .italic()
                        }

                        Text(interaction.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundColor(dynamicSecondaryTextColor.opacity(0.7))
                    }
                    .padding(.vertical, 4)

                    if interaction.id != schedulingViewModel.recentInteractions.prefix(10).last?.id {
                        Divider()
                    }
                }
            }
        } else {
            Text("No interactions yet. The agent tracks every proposal you accept, decline, or modify.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .italic()
        }
    }

    @ViewBuilder
    private func actionBadge(_ action: ProposalAction) -> some View {
        let (text, color): (String, Color) = {
            switch action {
            case .accepted: return ("✓", .green)
            case .acceptedWithChanges: return ("~", .orange)
            case .declined: return ("✗", .red)
            case .skipped: return ("→", .gray)
            }
        }()

        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(color)
            .frame(width: 20, height: 20)
            .background(color.opacity(0.2))
            .cornerRadius(4)
    }
}

// MARK: - Helper Views

struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(dynamicPrimaryColor)
                        .frame(width: 24)

                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(dynamicTextColor)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(PlainButtonStyle())

            if isExpanded {
                content()
                    .padding(.leading, 32)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

struct DataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(dynamicTextColor)
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(dynamicSecondaryTextColor)
        }
    }
}

// MARK: - Animated Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dynamicSecondaryTextColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationPhase == index ? 1.2 : 0.8)
                    .opacity(animationPhase == index ? 1.0 : 0.4)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    animationPhase = (animationPhase + 1) % 3
                }
            }
        }
    }
}

// MARK: - Modification Review Sheet

struct ModificationReviewSheet: View {
    @Binding var modifications: [ModificationContext]
    @Binding var currentIndex: Int
    @Binding var reason: String
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    let onComplete: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    private var currentModification: ModificationContext? {
        guard currentIndex < modifications.count else { return nil }
        return modifications[currentIndex]
    }

    private var progress: String {
        "\(currentIndex + 1) of \(modifications.count)"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("Help the agent learn!")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        Text("You modified \(modifications.count) session\(modifications.count == 1 ? "" : "s"). Quick feedback helps improve future suggestions.")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 20)

                    if let mod = currentModification {
                        // Progress indicator
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)

                        // Modification Summary
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Tasks:")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                Spacer()
                                Text(mod.tasks.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(dynamicTextColor)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }

                            HStack {
                                Text("Original:")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                Spacer()
                                Text(mod.originalTime)
                                    .font(.caption)
                                    .foregroundColor(dynamicTextColor)
                                    .strikethrough()
                            }

                            HStack {
                                Text("Modified to:")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                Spacer()
                                Text(mod.modifiedTime)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // Quick Suggestions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick reasons:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    QuickReasonChip(text: "Had a conflict", onTap: { reason = "Had a conflict at that time"; isTextFieldFocused = false })
                                    QuickReasonChip(text: "Too early", onTap: { reason = "That time was too early for me"; isTextFieldFocused = false })
                                    QuickReasonChip(text: "Too late", onTap: { reason = "That time was too late for me"; isTextFieldFocused = false })
                                    QuickReasonChip(text: "Need more time", onTap: { reason = "I need more time for this task"; isTextFieldFocused = false })
                                    QuickReasonChip(text: "Need less time", onTap: { reason = "I don't need that much time"; isTextFieldFocused = false })
                                }
                                .padding(.horizontal)
                            }
                        }

                        // Reason Input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Or type your own:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)

                            TextField("e.g., I have a meeting at that time...", text: $reason, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(12)
                                .lineLimit(2...4)
                                .focused($isTextFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    isTextFieldFocused = false
                                }
                        }
                        .padding(.horizontal)
                    }

                    // Action Buttons
                    VStack(spacing: 12) {
                        Button(action: {
                            saveCurrentAndAdvance()
                        }) {
                            HStack {
                                Text(reason.isEmpty ? "Skip" : "Save")
                                if currentIndex < modifications.count - 1 {
                                    Image(systemName: "arrow.right")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(reason.isEmpty ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                            .cornerRadius(12)
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button(action: {
                            skipAllRemaining()
                        }) {
                            Text("Skip all remaining")
                                .font(.subheadline)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
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
                        skipAllRemaining()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            isTextFieldFocused = false
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func saveCurrentAndAdvance() {
        isTextFieldFocused = false

        if let mod = currentModification {
            schedulingViewModel.saveModificationReason(
                reason: reason,
                originalTime: mod.originalTime,
                modifiedTime: mod.modifiedTime,
                tasks: mod.tasks
            )
        }

        reason = ""

        if currentIndex < modifications.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentIndex += 1
            }
        } else {
            onComplete()
        }
    }

    private func skipAllRemaining() {
        isTextFieldFocused = false

        // Save all remaining modifications with empty reason
        for i in currentIndex..<modifications.count {
            let mod = modifications[i]
            schedulingViewModel.saveModificationReason(
                reason: i == currentIndex ? reason : "",
                originalTime: mod.originalTime,
                modifiedTime: mod.modifiedTime,
                tasks: mod.tasks
            )
        }

        onComplete()
    }
}
