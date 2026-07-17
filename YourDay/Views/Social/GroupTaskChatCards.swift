//
//  GroupTaskChatCards.swift
//  YourDay
//
//  Special chat bubbles for group chats: a live progress card for group tasks
//  ("group_task" messages) and an embedded proof-post card with voting
//  ("proof_post" messages).
//

import SwiftUI
import FirebaseFirestore

// MARK: - Group Task Progress Card

/// Live progress card rendered in place of a "group_task" chat message.
/// The task comes from the chat view's single group-tasks listener, so the
/// card updates in real time as assignees complete the task.
struct GroupTaskProgressCard: View {
    let task: GroupTask?

    var body: some View {
        if let task = task {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.caption)
                        .foregroundColor(dynamicPrimaryColor)
                    Text("Group Task")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(dynamicPrimaryColor)
                    Spacer()
                    Text(task.dueDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }

                Text(task.title)
                    .font(.headline)
                    .foregroundColor(dynamicTextColor)

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundColor(dynamicSecondaryTextColor)
                }

                ProgressView(value: progressFraction)
                    .tint(dynamicPrimaryColor)

                Text("\(task.completedBy.count)/\(task.assigneeIds.count) completed")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(dynamicSecondaryTextColor)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.assigneeIds, id: \.self) { uid in
                        HStack(spacing: 6) {
                            Image(systemName: task.completedBy.contains(uid) ? "checkmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundColor(task.completedBy.contains(uid) ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                            Text(task.assigneeNames[uid] ?? "Member")
                                .font(.caption)
                                .foregroundColor(dynamicTextColor)
                        }
                    }
                }
            }
            .padding(14)
            .background(dynamicSecondaryBackgroundColor)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(dynamicPrimaryColor.opacity(0.4), lineWidth: 1)
            )
        } else {
            Text("Group task no longer available")
                .font(.caption)
                .foregroundColor(dynamicSecondaryTextColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(dynamicSecondaryBackgroundColor)
                .cornerRadius(18)
        }
    }

    private var progressFraction: Double {
        guard let task = task, !task.assigneeIds.isEmpty else { return 0 }
        return Double(task.completedBy.count) / Double(task.assigneeIds.count)
    }
}

// MARK: - Group Proof Message Card

/// Embedded proof-post photo card rendered in place of a "proof_post" chat
/// message, with the existing check/x voting mechanics.
struct GroupProofMessageCard: View {
    let postId: String

    @EnvironmentObject var firebaseManager: FirebaseManager

    @State private var post: TaskProofPost?
    @State private var postMissing = false
    @State private var votes: [TaskProofVote] = []
    @State private var votesListener: ListenerRegistration?

    var body: some View {
        Group {
            if let post = post {
                TaskProofPostCardView(
                    post: post,
                    votes: votes,
                    onVote: { voteType in
                        firebaseManager.setTaskProofVote(postId: postId, voteType: voteType) { error in
                            if let error = error {
                                print("GroupProofMessageCard: Failed to set vote: \(error.localizedDescription)")
                            }
                        }
                    },
                    onDelete: {
                        firebaseManager.deleteTaskProofPost(postId: postId) { error in
                            if let error = error {
                                print("GroupProofMessageCard: Failed to delete proof: \(error.localizedDescription)")
                            } else {
                                self.post = nil
                                self.postMissing = true
                            }
                        }
                    }
                )
            } else if postMissing {
                Text("Proof removed")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(dynamicSecondaryBackgroundColor)
                    .cornerRadius(18)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
        .onAppear {
            if post == nil && !postMissing {
                firebaseManager.fetchTaskProofPost(postId: postId) { fetched in
                    if let fetched = fetched {
                        post = fetched
                    } else {
                        postMissing = true
                    }
                }
            }
            if votesListener == nil {
                votesListener = firebaseManager.listenToTaskProofVotes(postId: postId) { updated in
                    votes = updated
                }
            }
        }
        .onDisappear {
            votesListener?.remove()
            votesListener = nil
        }
    }
}
