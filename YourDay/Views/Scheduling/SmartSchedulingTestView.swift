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
    @ObservedObject private var journalViewModel = JournalViewModel.shared
    
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
    @State private var pendingAcceptedTasksAfterModification: [String]? = nil
    @State private var showingRescheduleAlert = false
    @State private var showingJournalView = false
    
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
            .sheet(isPresented: $journalViewModel.showingJournalPrompt) {
                if let pendingEvent = journalViewModel.pendingJournalPrompt {
                    JournalPromptView(journalViewModel: journalViewModel, pendingEvent: pendingEvent)
                        .onDisappear {
                            // Trigger AI analysis when journal entry is saved
                            if !journalViewModel.journalEntries.isEmpty {
                                journalViewModel.triggerJournalAnalysis(schedulingViewModel: schedulingViewModel)
                            }
                        }
                }
            }
            .onAppear {
                refreshData()
                // Start monitoring for ended tasks
                TaskEndMonitor.shared.startMonitoring()
            }
        }
    }
    
    private func fetchCalendarForDate() {
        schedulingViewModel.fetchCalendarEvents(for: selectedDate)
    }
    
    // MARK: - Setup Tab
    
    private var setupTabView: some View {
        SchedulingSetupView(
            backlogViewModel: backlogViewModel,
            schedulingViewModel: schedulingViewModel,
            selectedDate: $selectedDate,
            showingDatePicker: $showingDatePicker,
            showingAddBacklogSheet: $showingAddBacklogSheet,
            isAgentRunning: $isAgentRunning,
            onFetchCalendar: {
                fetchCalendarForDate()
            },
            onRunAgent: {
                runAgent()
            }
        )
    }
    
    // MARK: - Chat Tab

    private var chatTabView: some View {
        SchedulingChatView(
            schedulingViewModel: schedulingViewModel,
            backlogViewModel: backlogViewModel,
            isAgentRunning: $isAgentRunning,
            selectedTab: $selectedTab,
            newMessage: $newMessage,
            onAcceptTasks: { taskTitles in
                handleAcceptedTasks(taskTitles)
            },
            onRequestModificationReason: { context in
                pendingModifications.append(context)
                currentModificationIndex = nextPendingModificationIndex() ?? (pendingModifications.count - 1)
                modificationReason = pendingModifications[currentModificationIndex].reason ?? ""
                showingModificationReview = true
                pendingAcceptedTasksAfterModification = context.tasks
            },
            onSendMessage: {
                sendMessage()
            },
            onScrollToLastMessage: { proxy in
                scrollToLastMessage(proxy: proxy)
            },
            onScrollToStatus: { proxy in
                scrollToStatus(proxy: proxy)
            },
            onScrollToProposal: { proxy in
                scrollToProposal(proxy: proxy)
            }
        )
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
        
        // Reset chat to start fresh (this also clears session context)
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
