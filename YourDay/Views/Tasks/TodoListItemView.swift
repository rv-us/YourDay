import SwiftUI
import SwiftData
import FirebaseAuth

struct TodoListItemView: View {
    @Bindable var item: TodoItem
    @State private var showingEditView = false
    @State private var proofErrorMessage: String?
    @Environment(\.modelContext) private var _modelContext
    @ObservedObject var todoViewModel: TodoViewModel
    @EnvironmentObject var firebaseManager: FirebaseManager
    var onRequestProofCapture: ((TaskProofCaptureContext) -> Void)? = nil

    // Color based on task origin
    private var originColor: Color {
        switch item.origin {
        case .today:
            return plantPeach
        case .master:
            return plantLightMintGreen
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Colored origin indicator strip
            RoundedRectangle(cornerRadius: 2)
                .fill(originColor)
                .frame(width: 4)
                .padding(.vertical, 4)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button(action: {
                        toggleCompletion()
                    }) {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(item.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                        .frame(width: 24, height: 24)
                        .padding(6)
                        .background(item.isDone ? dynamicPrimaryColor.opacity(0.2) : dynamicSecondaryBackgroundColor)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(item.isDone ? dynamicPrimaryColor : dynamicSecondaryTextColor, lineWidth: 1.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(.body)
                            .lineLimit(1)
                            .strikethrough(item.isDone, color: dynamicSecondaryTextColor)
                            .foregroundColor(item.isDone ? dynamicSecondaryTextColor : dynamicTextColor)
                        if item.isSharedPending {
                            Text("Pending")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(dynamicSecondaryTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(dynamicSecondaryBackgroundColor)
                                .cornerRadius(6)
                        }
                    }

                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.caption)
                            .lineLimit(2)
                            .strikethrough(item.isDone, color: dynamicSecondaryTextColor.opacity(0.7))
                            .foregroundColor(item.isDone ? dynamicSecondaryTextColor : dynamicSecondaryTextColor)
                    }
                }
                .onTapGesture {
                    showingEditView = true
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            if !$item.subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach($item.subtasks) { $subtask in
                        SubtaskCheckboxView(subtask: $subtask, onToggle: { _ in
                            if let sharedId = item.sharedTaskId {
                                let sharedSubtasks = item.subtasks.enumerated().map { idx, st in
                                    SharedSubtask(id: "sub_\(idx)", title: st.title, isDone: st.isDone)
                                }
                                firebaseManager.updateSharedSubtasks(sharedTaskId: sharedId, subtasks: sharedSubtasks) { error in
                                    if let error = error { print("Failed to sync shared subtasks: \(error.localizedDescription)") }
                                }
                            }
                            
                            // Sync subtask change to Firebase
                            if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                                let codableTask = TodoItemCodable(from: item, userId: userId)
                                firebaseManager.saveTodoItem(codableTask) { error in
                                    if let error = error {
                                        print("TodoListItemView: Failed to sync subtask change to Firebase: \(error.localizedDescription)")
                                    } else {
                                        print("TodoListItemView: Successfully synced subtask change to Firebase")
                                    }
                                }
                            }
                        })
                            .strikethrough(subtask.isDone, color: dynamicSecondaryTextColor.opacity(0.7))
                            .foregroundColor(subtask.isDone ? dynamicSecondaryTextColor.opacity(0.7) : dynamicTextColor)
                    }
                }
                .padding(.leading, 34)
            }
            }
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingEditView) {
            NewItemview(newItemPresented: $showingEditView, editingItem: item)
                .environment(\.modelContext, _modelContext)
        }
        .alert("Proof Update Failed", isPresented: Binding(
            get: { proofErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    proofErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                proofErrorMessage = nil
            }
        } message: {
            Text(proofErrorMessage ?? "Something went wrong while updating your proof post.")
        }
    }

    private func toggleCompletion() {
        let wasDone = item.isDone

        withAnimation {
            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
        }

        print("Main item '\(item.title)' toggled to \(item.isDone), completedAt: \(String(describing: item.completedAt))")

        if let sharedId = item.sharedTaskId {
            firebaseManager.updateSharedTaskProgress(sharedTaskId: sharedId, isCompleted: item.isDone) { error in
                if let error = error {
                    print("Failed to sync shared task progress: \(error.localizedDescription)")
                }
            }
        }
        
        // Sync task completion toggle to Firebase
        if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
            let codableTask = TodoItemCodable(from: item, userId: userId)
            firebaseManager.saveTodoItem(codableTask) { error in
                if let error = error {
                    print("TodoListItemView: Failed to sync task toggle to Firebase: \(error.localizedDescription)")
                } else {
                    print("TodoListItemView: Successfully synced task toggle to Firebase")
                }
            }
        }

        if !wasDone && item.isDone {
            onRequestProofCapture?(TaskProofCaptureContext(
                taskTitle: item.title,
                sourceType: item.sharedTaskId == nil ? .unscheduled : .shared,
                scheduledEventId: nil,
                localTaskId: item.localTaskId,
                sharedTaskId: item.sharedTaskId,
                completedAt: item.completedAt ?? Date()
            ))
        } else if wasDone && !item.isDone, let proofPostId = item.proofPostId {
            item.proofPostId = nil
            firebaseManager.deleteTaskProofPost(postId: proofPostId) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        proofErrorMessage = error.localizedDescription
                    }
                }
            }
        }

        saveModelContext()

        // Reschedule notifications to reflect current task state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            todoViewModel.rescheduleNotificationsIfNeeded(context: _modelContext)
        }
    }

    private func saveModelContext() {
        do {
            try _modelContext.save()
        } catch {
            print("Failed to save Todo item changes: \(error)")
        }
    }
}
