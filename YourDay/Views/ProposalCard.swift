//
//  ProposalCard.swift
//  YourDay
//
//  Card view for displaying proposed working sessions
//

import SwiftUI

struct ProposalCard: View {
    let proposal: ProposedSession
    @ObservedObject var schedulingViewModel: SchedulingAssistantViewModel
    @ObservedObject var backlogViewModel: BacklogViewModel
    let onAccept: ([String]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Proposed Working Session")
                .font(.headline)
                .foregroundColor(dynamicTextColor)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.tasks.count == 1 ? "Task:" : "Tasks:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    
                    if proposal.tasks.count == 1 {
                        Text(proposal.tasks.first ?? "")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dynamicTextColor)
                    } else {
                        ForEach(proposal.tasks, id: \.self) { task in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(dynamicPrimaryColor)
                                Text(task)
                                    .font(.subheadline)
                                    .foregroundColor(dynamicTextColor)
                            }
                        }
                    }
                }
                
                HStack {
                    Text("Time:")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                    Text(proposal.workingSessionTime)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(dynamicTextColor)
                }
                
                if let reason = proposal.reason {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reason:")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                }
            }
            
            Divider()
            
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                Button(action: {
                    if let proposal = schedulingViewModel.currentProposal {
                        schedulingViewModel.acceptProposal(backlogItems: backlogViewModel.backlogItems) { scheduledTasks in
                            if !scheduledTasks.isEmpty {
                                onAccept(scheduledTasks)
                            }
                        }
                    }
                }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Accept")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(dynamicPrimaryColor)
                        .cornerRadius(10)
                    }
                    
                    Button(action: {
                        schedulingViewModel.declineProposal()
                    }) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Decline")
                        }
                        .font(.headline)
                        .foregroundColor(dynamicTextColor)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(dynamicSecondaryBackgroundColor)
                        .cornerRadius(10)
                    }
                }
                
                Button(action: {
                    // Skip these tasks without reason
                    let tasksToSkip = proposal.tasks
                    schedulingViewModel.skipTask(tasks: tasksToSkip) {
                        onAccept(tasksToSkip) // Mark these tasks as processed
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Skip Task")
                    }
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(dynamicBackgroundColor)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(dynamicSecondaryBackgroundColor)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}
