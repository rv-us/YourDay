//
//  SmartSchedulingView.swift
//  YourDay
//
//  Primary view for smart scheduling
//

import SwiftUI
import SwiftData
import FirebaseAuth

// MARK: - Feature toggles (agent scheduling)
/// Set to `true` to show the Agent / Manual segmented control and the AI scheduling UI again.
private enum SmartSchedulingFeatureFlags {
    static let showAgentSchedulingOption = false
}

private enum SmartSchedulingMode: String, CaseIterable, Identifiable {
    case agent = "Agent"
    case manual = "Manual"
    var id: String { rawValue }
}

struct SmartSchedulingView: View {
    let initialDate: Date?
    let autoStart: Bool
    var onSkip: (() -> Void)? = nil
    
    @StateObject private var backlogViewModel = BacklogViewModel()
    @StateObject private var schedulingViewModel = SchedulingAssistantViewModel()
    @ObservedObject private var journalViewModel = JournalViewModel.shared
    
    @Query(sort: \TodoItem.position) private var todoItems: [TodoItem]
    
    @State private var showingAddBacklogSheet = false
    @State private var isAgentRunning = false
    @State private var selectedDate = Date()
    @State private var showingDatePicker = false
    @State private var scheduledTasks: Set<String> = [] // Track scheduled task titles
    @State private var planningDate: Date? = nil // Fixed date for current agent session
    @State private var pendingModifications: [ModificationContext] = [] // Store all modifications to process at end
    @State private var showingModificationReview = false
    @State private var currentModificationIndex = 0
    @State private var modificationReason = ""
    @State private var pendingAcceptedTasksAfterModification: [String]? = nil
    @State private var declineReason = ""
    @State private var isBacklogExpanded = true
    @State private var isCalendarExpanded = false
    @State private var isMemoryExpanded = false
    @State private var isContextExpanded = false
    @State private var showingJournalView = false
    @State private var hasAutoStarted = false // Track if auto-start has been triggered
    @State private var showingNoTasksAlert = false
    @State private var schedulingMode: SmartSchedulingMode = .agent
    
    private var defaultProposal: ProposedSession {
        ProposedSession(tasks: [], workingSessionTime: "", startTime: nil, endTime: nil, reason: nil)
    }

    init(initialDate: Date? = nil, autoStart: Bool = false, onSkip: (() -> Void)? = nil) {
        self.initialDate = initialDate
        self.autoStart = autoStart
        self.onSkip = onSkip
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
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if SmartSchedulingFeatureFlags.showAgentSchedulingOption {
                        Picker("Mode", selection: $schedulingMode) {
                            ForEach(SmartSchedulingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if !SmartSchedulingFeatureFlags.showAgentSchedulingOption || schedulingMode == .manual {
                        Button(action: {
                            showingDatePicker = true
                        }) {
                            HStack {
                                Image(systemName: "calendar")
                                Text(selectedDate, style: .date)
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(dynamicTextColor)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        ManualSchedulingView(
                            selectedDate: $selectedDate,
                            todoItems: todoItems,
                            schedulingViewModel: schedulingViewModel
                        )
                    } else {
                        sessionHeader
                        sessionStatus
                        proposalSection
                        configurationSections
                    }
                }
                .padding()
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if onSkip != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Skip") {
                            onSkip?()
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Smart Scheduling")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            showingJournalView = true
                        }) {
                            Image(systemName: "book.fill")
                                .foregroundColor(dynamicPrimaryColor)
                        }
                        
                        Button("Refresh") {
                            refreshData()
                        }
                        .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
            .sheet(isPresented: $showingJournalView) {
                JournalView(journalViewModel: journalViewModel)
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
                    onSaveReason: { modification in
                        let trimmedReason = (modification.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedReason.isEmpty else { return }
                        schedulingViewModel.addSessionModificationReason(
                            reason: trimmedReason,
                            originalTime: modification.originalTime,
                            modifiedTime: modification.modifiedTime,
                            tasks: modification.tasks
                        )
                    },
                    onComplete: {
                        showingModificationReview = false
                        modificationReason = ""
                        if let tasksToAccept = pendingAcceptedTasksAfterModification {
                            pendingAcceptedTasksAfterModification = nil
                            handleAcceptedTasks(tasksToAccept)
                        }
                        if !isAgentRunning {
                            processModificationReasonsBatch()
                            currentModificationIndex = 0
                        }
                    }
                )
                .interactiveDismissDisabled(true)
            }
            .sheet(isPresented: $schedulingViewModel.showingDeclineReasonInput) {
                DeclineReasonSheet(
                    reason: $declineReason,
                    tasks: schedulingViewModel.currentProposal?.tasks ?? [],
                    proposedTime: schedulingViewModel.currentProposal?.workingSessionTime ?? "",
                    onSubmit: { reason in
                        schedulingViewModel.submitDeclineReason(reason, backlogItems: backlogViewModel.backlogItems)
                        declineReason = ""
                    },
                    onCancel: {
                        schedulingViewModel.cancelDeclineReason()
                        declineReason = ""
                    }
                )
                .interactiveDismissDisabled(true)
            }
            .alert("Reschedule?", isPresented: $schedulingViewModel.showingRescheduleConfirmation) {
                Button("Yes, reschedule") {
                    schedulingViewModel.confirmReschedule { error in
                        if let error = error {
                            print("Error rescheduling: \(error.localizedDescription)")
                        }
                    }
                }
                Button("No, skip for now", role: .cancel) {
                    // Mark declined tasks as processed and move to next proposal
                    let declinedTasks = schedulingViewModel.getDeclinedTasks()
                    if !declinedTasks.isEmpty {
                        for taskTitle in declinedTasks {
                            scheduledTasks.insert(taskTitle)
                        }
                    }
                    schedulingViewModel.cancelReschedule()
                    proposeNextSession()
                }
            } message: {
                Text("Would you like me to suggest a different time for these tasks?")
            }
            .alert("No Tasks to Schedule", isPresented: $showingNoTasksAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Add tasks to your backlog first. Expand the Backlog section below and tap + to add items, then try again.")
            }
            .onAppear {
                // Set initial date if provided
                if let initialDate = initialDate {
                    selectedDate = initialDate
                }
                schedulingViewModel.selectedDate = selectedDate
                
                refreshData()
                // Ensure schedule preferences (including memories) are loaded on view appear
                schedulingViewModel.fetchSchedulePreference()
                // Start monitoring for ended tasks
                TaskEndMonitor.shared.startMonitoring()
                
                // Auto-start scheduling if requested and not already started
                if SmartSchedulingFeatureFlags.showAgentSchedulingOption, schedulingMode == .agent, autoStart && !hasAutoStarted {
                    hasAutoStarted = true
                    // Delay to ensure view is fully rendered and backlog is loaded
                    // The backlog fetch happens in refreshData(), so we wait a bit longer
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        // Check if backlog has items before auto-starting
                        if !backlogViewModel.backlogItems.isEmpty && !isAgentRunning {
                            runAgent()
                        } else if !isAgentRunning {
                            // If backlog is still empty, try once more after a short delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                if !backlogViewModel.backlogItems.isEmpty && !isAgentRunning {
                                    runAgent()
                                }
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedDate) { _, newValue in
                schedulingViewModel.selectedDate = newValue
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("JournalEntrySaved"))) { _ in
                // Trigger AI analysis when journal entry is saved
                if !journalViewModel.journalEntries.isEmpty {
                    journalViewModel.triggerJournalAnalysis(schedulingViewModel: schedulingViewModel)
                }
            }
            .onChange(of: schedulingViewModel.showingDeclineReasonInput) { _, isShowing in
                if isShowing {
                    declineReason = ""
                }
            }
        }
    }
    
    private func fetchCalendarForDate() {
        schedulingViewModel.fetchCalendarEvents(for: selectedDate)
    }
    
    // MARK: - Primary UI Sections
    
    private var sessionHeader: some View {
        let displayedDate = planningDate ?? selectedDate
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Plan your session")
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                    Text(displayedDate, style: .date)
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                Spacer()
                Text(isAgentRunning ? "Running" : "Ready")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(isAgentRunning ? Color.green.opacity(0.2) : dynamicSecondaryBackgroundColor)
                    .foregroundColor(isAgentRunning ? .green : dynamicSecondaryTextColor)
                    .cornerRadius(12)
            }
            
            Button(action: {
                showingDatePicker = true
            }) {
                HStack {
                    Image(systemName: "calendar")
                    Text(displayedDate, style: .date)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(dynamicTextColor)
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(8)
            }
            .disabled(isAgentRunning)
            
            HStack(spacing: 12) {
                Button(action: {
                    fetchCalendarForDate()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Calendar")
                    }
                    .font(.subheadline)
                    .foregroundColor(dynamicPrimaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(10)
                }
                .buttonStyle(ScaleButtonStyle())
                
                Button(action: {
                    if backlogViewModel.backlogItems.isEmpty {
                        showingNoTasksAlert = true
                    } else {
                        runAgent()
                    }
                }) {
                    HStack {
                        Image(systemName: isAgentRunning ? "bolt.fill" : "play.circle.fill")
                        Text(isAgentRunning ? "Running..." : "Start Scheduling")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isAgentRunning ? dynamicSecondaryTextColor : dynamicPrimaryColor)
                    .cornerRadius(10)
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(isAgentRunning)
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }
    
    private var sessionStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            if SmartSchedulingFeatureFlags.showAgentSchedulingOption, schedulingMode == .agent, let fetchError = schedulingViewModel.calendarFetchError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundColor(.orange)
                    Text(fetchError)
                        .font(.caption)
                        .foregroundColor(dynamicTextColor)
                    Spacer(minLength: 0)
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
            }
            if let statusMessage = schedulingViewModel.statusMessage {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .italic()
                    Spacer()
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            if schedulingViewModel.isGeneratingMemory {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Updating memory...")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .italic()
                    Spacer()
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
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
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: schedulingViewModel.statusMessage)
        .animation(.easeInOut(duration: 0.2), value: schedulingViewModel.isLoading)
        .animation(.easeInOut(duration: 0.2), value: schedulingViewModel.isGeneratingMemory)
    }
    
    private var proposalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested Session")
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)
                Spacer()
            }
            
            if let _ = schedulingViewModel.currentProposal {
                ProposalMessageCard(
                    proposal: proposalBinding,
                    schedulingViewModel: schedulingViewModel,
                    backlogViewModel: backlogViewModel,
                    onAccept: { taskTitles in
                        handleAcceptedTasks(taskTitles)
                    },
                    onRequestModificationReason: { context in
                        pendingModifications.append(context)
                        currentModificationIndex = nextPendingModificationIndex() ?? (pendingModifications.count - 1)
                        modificationReason = pendingModifications[currentModificationIndex].reason ?? ""
                        showingModificationReview = true
                        pendingAcceptedTasksAfterModification = context.tasks
                    },
                    isDisabled: schedulingViewModel.showingDeclineReasonInput,
                    maxWidth: .infinity
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isAgentRunning {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Looking for the best time slot...")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text("We’ll suggest your next session as soon as it’s ready.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ready when you are.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text("Start scheduling to get your first suggested session.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: schedulingViewModel.currentProposal != nil)
    }
    
    private var configurationSections: some View {
        VStack(spacing: 12) {
            ExpandableSection(
                title: "Backlog",
                icon: "tray.full",
                isExpanded: isBacklogExpanded,
                onToggle: { isBacklogExpanded.toggle() }
            ) {
                backlogSectionContent
            }
            
            ExpandableSection(
                title: "Day Context",
                icon: "sun.max",
                isExpanded: isContextExpanded,
                onToggle: { isContextExpanded.toggle() }
            ) {
                DayContextSection(schedulingViewModel: schedulingViewModel)
            }
            
            ExpandableSection(
                title: "Learned Memories",
                icon: "brain.head.profile",
                isExpanded: isMemoryExpanded,
                onToggle: { isMemoryExpanded.toggle() }
            ) {
                AgentMemorySection(schedulingViewModel: schedulingViewModel, selectedDate: selectedDate)
            }
        }
    }
    
    private var backlogSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Backlog Items")
                    .font(.subheadline)
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
                    .padding(.vertical, 8)
            } else if backlogViewModel.backlogItems.isEmpty {
                Text("No backlog items yet. Add tasks to start scheduling.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .padding(.vertical, 4)
            } else {
                ForEach(backlogViewModel.backlogItems) { item in
                    BacklogItemRow(item: item, backlogViewModel: backlogViewModel)
                }
            }
        }
    }
    
    private var calendarSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calendar Events")
                    .font(.subheadline)
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
                Text("No events for this date.")
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
    }
    
    private func runAgent() {
        guard !isAgentRunning else { return }
        
        isAgentRunning = true
        scheduledTasks.removeAll()
        
        // Store the selected date at agent start - this will remain fixed during agent operations
        planningDate = selectedDate
        
        // Reset chat to start fresh (this also clears session context)
        schedulingViewModel.resetChat()
        
        // Initialize the agent (without loading history for fresh start)
        if let userId = Auth.auth().currentUser?.uid {
            schedulingViewModel.initialize(userId: userId, loadHistory: false)
        }
        
        // Fetch latest data (including backlog and calendar)
        backlogViewModel.fetchBacklogItems(todoItems: todoItems)
        fetchCalendarForDate()
        
        // CRITICAL: Load schedule preferences (including memories) before proposing
        // This ensures dayOfWeekMemories and scheduleConstraints are available to the agent
        schedulingViewModel.fetchSchedulePreference {
            // Once preferences are loaded, propose the first session
            // This ensures memories are available when the agent generates proposals
            self.proposeNextSession()
        }
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
            
            // Clear session context when session ends
            schedulingViewModel.clearSessionContext()
            
            let completionMessage = SchedulingMessage(
                userId: Auth.auth().currentUser?.uid ?? "",
                role: .assistant,
                content: "All tasks have been processed! Great work organizing your day."
            )
            schedulingViewModel.messages.append(completionMessage)
            schedulingViewModel.currentProposal = nil

            // Process modification reasons if there are pending modifications
            if !pendingModifications.isEmpty {
                if !showingModificationReview {
                    processModificationReasonsBatch()
                    currentModificationIndex = 0
                }
            } else {
                // If no pending modifications, analyze decline reasons immediately
                analyzeSessionPatterns()
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
                    // Clear session context on error
                    self.schedulingViewModel.clearSessionContext()
                }
            }
        }
    }
    
    private func refreshData() {
        backlogViewModel.fetchBacklogItems(todoItems: todoItems)
        fetchCalendarForDate()
        schedulingViewModel.fetchSchedulePreference()
    }
    
    private func nextPendingModificationIndex() -> Int? {
        pendingModifications.firstIndex { !$0.isReviewed }
    }


    private func processModificationReasonsBatch() {
        // Create inputs from pending modifications and clear immediately to avoid duplicates
        let inputs = pendingModifications.map { modification in
            ModificationReasonInput(
                dayOfWeek: modification.dayOfWeek,
                originalTime: modification.originalTime,
                modifiedTime: modification.modifiedTime,
                tasks: modification.tasks,
                originalTasks: modification.originalTasks,
                addedTasks: modification.addedTasks,
                removedTasks: modification.removedTasks,
                reason: modification.reason ?? ""
            )
        }
        
        // Clear pending modifications before processing to prevent duplicate calls
        pendingModifications.removeAll()
        
        // Process modification reasons
        schedulingViewModel.analyzeModificationReasonsBatch(inputs)
        
        // After processing modifications, also analyze decline reasons
        analyzeSessionPatterns()
    }
    
    private func analyzeSessionPatterns() {
        // Analyze decline reasons from the session
        schedulingViewModel.analyzeDeclineReasonsBatch()
        
        // Note: Modification reasons are now processed separately in processModificationReasonsBatch()
        // and cleared before this function is called, so no fallback is needed here
    }
}


// MARK: - Agent Memory Section

struct AgentMemorySection: View {
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    let selectedDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learned Memories")
                .font(.headline)
                .foregroundColor(dynamicTextColor)
            
            Text("Tap to expand and edit. Swipe left to delete.")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)

            if let preference = schedulingViewModel.schedulePreference {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 20) {
                        // Day-of-Week Memories
                        if let dayMemories = preference.dayOfWeekMemories, !dayMemories.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "calendar.badge.clock")
                                        .foregroundColor(dynamicPrimaryColor)
                                    Text("Day-Specific Patterns")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(dynamicTextColor)
                                }
                                
                                ForEach(Array(dayMemories.keys.sorted()), id: \.self) { day in
                                    if let memories = dayMemories[day], !memories.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(day.capitalized)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(dynamicPrimaryColor)
                                                .textCase(.uppercase)
                                            
                                            ForEach(memories, id: \.self) { memory in
                                                ExpandableMemoryCard(
                                                    memory: memory,
                                                    day: day,
                                                    schedulingViewModel: schedulingViewModel
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Schedule Constraints
                        if !preference.scheduleConstraints.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Schedule Constraints")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(dynamicTextColor)
                                }
                                
                                ForEach(Array(preference.scheduleConstraints.enumerated()), id: \.offset) { index, constraint in
                                    ExpandableConstraintCard(
                                        constraint: constraint,
                                        index: index,
                                        schedulingViewModel: schedulingViewModel
                                    )
                                }
                            }
                        }
                        
                        // Empty state
                        if (preference.dayOfWeekMemories?.isEmpty ?? true) && preference.scheduleConstraints.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 40))
                                    .foregroundColor(dynamicSecondaryTextColor)
                                Text("No memories yet")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicTextColor)
                                Text("The agent will learn your preferences as you use the scheduler")
                                    .font(.caption)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 600)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading memories...")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Expandable Memory Card

struct ExpandableMemoryCard: View {
    let memory: String
    let day: String
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    
    @State private var isExpanded = false
    @State private var editedText: String = ""
    @State private var offset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            if offset < 0 {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring()) {
                            schedulingViewModel.deleteDayOfWeekMemory(day: day, memory: memory)
                        }
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(dynamicDestructiveColor)
                            .cornerRadius(8)
                    }
                    .padding(.trailing, 16)
                }
            }
            
            // Card content
            VStack(alignment: .leading, spacing: 0) {
                // Collapsed view
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.top, 2)
                    
                    Text(memory)
                        .font(.subheadline)
                        .foregroundColor(dynamicTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        if isExpanded {
                            editedText = memory
                        }
                    }
                }
                
                // Expanded edit view
                if isExpanded {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Edit memory", text: $editedText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .lineLimit(3...10)
                            .frame(minHeight: 60)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                if !editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && editedText != memory {
                                    schedulingViewModel.editDayOfWeekMemory(day: day, oldMemory: memory, newMemory: editedText)
                                }
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Text("Save")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                                    .cornerRadius(8)
                            }
                            .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(dynamicBackgroundColor)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -80)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width < -50 {
                                offset = -80
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
        }
    }
}

// MARK: - Expandable Constraint Card

struct ExpandableConstraintCard: View {
    let constraint: ScheduleConstraint
    let index: Int
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    
    @State private var isExpanded = false
    @State private var editedReason: String = ""
    @State private var editedTimeRange: String = ""
    @State private var editedContext: String = ""
    @State private var offset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            if offset < 0 {
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation(.spring()) {
                            schedulingViewModel.deleteScheduleConstraint(at: index)
                        }
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.title3)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(dynamicDestructiveColor)
                            .cornerRadius(8)
                    }
                    .padding(.trailing, 16)
                }
            }
            
            // Card content
            VStack(alignment: .leading, spacing: 0) {
                // Collapsed view
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(constraint.reason)
                                .font(.subheadline)
                                .foregroundColor(dynamicTextColor)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if let timeRange = constraint.timeRange {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                    Text(timeRange)
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
                .padding()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                        if isExpanded {
                            editedReason = constraint.reason
                            editedTimeRange = constraint.timeRange ?? ""
                            editedContext = constraint.context ?? ""
                        }
                    }
                }
                
                // Expanded edit view
                if isExpanded {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reason")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            TextField("Reason", text: $editedReason, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                                .lineLimit(2...6)
                                .frame(minHeight: 50)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Time Range (optional)")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            TextField("e.g., 12:00-13:00", text: $editedTimeRange)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Context (optional)")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            TextField("Additional context", text: $editedContext, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                                .lineLimit(2...6)
                                .frame(minHeight: 50)
                        }
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Text("Cancel")
                                    .font(.subheadline)
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
                            }
                            
                            Button(action: {
                                if !editedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    let newConstraint = ScheduleConstraint(
                                        reason: editedReason,
                                        timeRange: editedTimeRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editedTimeRange,
                                        context: editedContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editedContext
                                    )
                                    schedulingViewModel.editScheduleConstraint(at: index, newConstraint: newConstraint)
                                }
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Text("Save")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(editedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                                    .cornerRadius(8)
                            }
                            .disabled(editedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(dynamicBackgroundColor)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -80)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width < -50 {
                                offset = -80
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
        }
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


// MARK: - Modification Review Sheet

struct ModificationReviewSheet: View {
    @Binding var modifications: [ModificationContext]
    @Binding var currentIndex: Int
    @Binding var reason: String
    let onSaveReason: (ModificationContext) -> Void
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
                            
                            // Show task changes if any
                            if !mod.addedTasks.isEmpty || !mod.removedTasks.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    if !mod.addedTasks.isEmpty {
                                        HStack {
                                            Text("Added:")
                                                .font(.caption2)
                                                .foregroundColor(dynamicSecondaryTextColor)
                                            Text(mod.addedTasks.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                    }
                                    if !mod.removedTasks.isEmpty {
                                        HStack {
                                            Text("Removed:")
                                                .font(.caption2)
                                                .foregroundColor(dynamicSecondaryTextColor)
                                            Text(mod.removedTasks.joined(separator: ", "))
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                                .strikethrough()
                                        }
                                    }
                                }
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

                            AppTextField(placeholder: "e.g., I have a meeting at that time...", text: $reason, axis: .vertical, lineLimit: 2...4)
                                .padding()
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(12)
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
        .onChange(of: currentIndex) { _, newIndex in
            if newIndex < modifications.count {
                reason = modifications[newIndex].reason ?? ""
            }
        }
    }

    private func saveCurrentAndAdvance() {
        isTextFieldFocused = false

        if currentModification != nil {
            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            modifications[currentIndex].reason = trimmedReason.isEmpty ? nil : trimmedReason
            if !trimmedReason.isEmpty {
                onSaveReason(modifications[currentIndex])
            }
        }

        reason = ""

        modifications[currentIndex].isReviewed = true

        if let nextIndex = modifications.firstIndex(where: { !$0.isReviewed }) {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentIndex = nextIndex
            }
        } else {
            onComplete()
        }
    }

    private func skipAllRemaining() {
        isTextFieldFocused = false

        // Save all remaining modifications with empty reason
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in currentIndex..<modifications.count {
            if i == currentIndex {
                modifications[i].reason = trimmedReason.isEmpty ? nil : trimmedReason
            } else {
                modifications[i].reason = nil
            }
            modifications[i].isReviewed = true
        }
        if !trimmedReason.isEmpty, currentIndex < modifications.count {
            onSaveReason(modifications[currentIndex])
        }

        onComplete()
    }
}

// MARK: - Decline Reason Sheet

struct DeclineReasonSheet: View {
    @Binding var reason: String
    let tasks: [String]
    let proposedTime: String
    let onSubmit: (String?) -> Void
    let onCancel: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)

                        Text("Help the agent learn!")
                            .font(.headline)
                            .foregroundColor(dynamicTextColor)

                        Text("Why didn’t this time work?")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tasks:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(tasks.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                                .lineLimit(2)
                                .multilineTextAlignment(.trailing)
                        }

                        HStack {
                            Text("Proposed time:")
                                .font(.caption)
                                .foregroundColor(dynamicSecondaryTextColor)
                            Spacer()
                            Text(proposedTime)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(dynamicTextColor)
                        }
                    }
                    .padding()
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(12)
                    .padding(.horizontal)

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
                                QuickReasonChip(text: "Not today", onTap: { reason = "Not today"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Need more time", onTap: { reason = "I need more time for this task"; isTextFieldFocused = false })
                                QuickReasonChip(text: "Need less time", onTap: { reason = "I don't need that much time"; isTextFieldFocused = false })
                            }
                            .padding(.horizontal)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or type your own:")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)

                        AppTextField(placeholder: "e.g., I have a meeting then...", text: $reason, axis: .vertical, lineLimit: 2...4)
                            .padding()
                            .background(dynamicSecondaryBackgroundColor)
                            .cornerRadius(12)
                            .focused($isTextFieldFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isTextFieldFocused = false
                            }
                    }
                    .padding(.horizontal)

                    VStack(spacing: 12) {
                        Button(action: {
                            isTextFieldFocused = false
                            let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                            onSubmit(trimmed.isEmpty ? nil : trimmed)
                        }) {
                            HStack {
                                Text(reason.isEmpty ? "Skip reason" : "Save & Continue")
                                Image(systemName: "arrow.right")
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
                            isTextFieldFocused = false
                            onCancel()
                        }) {
                            Text("Cancel")
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
                        isTextFieldFocused = false
                        onCancel()
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
}
