//
//  SchedulingChatView.swift
//  YourDay
//
//  Chat tab view for smart scheduling
//

import SwiftUI

struct SchedulingChatView: View {
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @ObservedObject var backlogViewModel: BacklogViewModel
    @Binding var isAgentRunning: Bool
    @Binding var selectedTab: Int
    @Binding var newMessage: String
    
    let onAcceptTasks: ([String]) -> Void
    let onRequestModificationReason: (ModificationContext) -> Void
    let onSendMessage: () -> Void
    let onScrollToLastMessage: (ScrollViewProxy) -> Void
    let onScrollToStatus: (ScrollViewProxy) -> Void
    let onScrollToProposal: (ScrollViewProxy) -> Void
    
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
    
    var body: some View {
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
                onScrollToLastMessage(proxy)
            }
            .onChange(of: schedulingViewModel.statusMessage) { _, newValue in
                if newValue != nil {
                    onScrollToStatus(proxy)
                }
            }
            .onChange(of: schedulingViewModel.currentProposal != nil) { _, hasProposal in
                if hasProposal {
                    onScrollToProposal(proxy)
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
            memoryGenerationView
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
                    onAccept: onAcceptTasks,
                    onRequestModificationReason: onRequestModificationReason,
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
    private var memoryGenerationView: some View {
        if schedulingViewModel.isGeneratingMemory {
            HStack {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating memory...")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .italic()
                }
                .padding()
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(12)
                Spacer()
            }
            .id("memory_generation")
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                    onSendMessage()
                }
                .foregroundColor(dynamicPrimaryColor)
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty || schedulingViewModel.isLoading)
            }
            .padding()
            .background(dynamicBackgroundColor)
        }
    }
    
}
