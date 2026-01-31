import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SharedTaskDetailView: View {
    let task: SharedTask
    let friend: FriendEntry
    @EnvironmentObject var firebaseManager: FirebaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var liveTask: SharedTask?
    @State private var listener: ListenerRegistration?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(liveTask?.title ?? task.title)
                .font(.title2).bold()
                .foregroundColor(dynamicTextColor)
            Text(liveTask?.detail ?? task.detail)
                .font(.body)
                .foregroundColor(dynamicSecondaryTextColor)
            Text((liveTask?.dueDate ?? task.dueDate), style: .date)
                .font(.caption)
                .foregroundColor(.gray)

            let subtasks = liveTask?.subtasks ?? task.subtasks
            if let taskId = (liveTask?.id ?? task.id) {
                List {
                    ForEach(subtasks) { st in
                        HStack {
                            Button(action: {
                                toggleSubtask(taskId: taskId, subtask: st)
                            }) {
                                Image(systemName: st.isDone ? "checkmark.square.fill" : "square")
                                    .foregroundColor(dynamicPrimaryColor)
                            }
                            .buttonStyle(PlainButtonStyle())
                            Text(st.title)
                                .foregroundColor(dynamicTextColor)
                            Spacer()
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }
                .listStyle(PlainListStyle())
                .background(dynamicBackgroundColor)
            }

            HStack(spacing: 12) {
                if let currentId = Auth.auth().currentUser?.uid {
                    if (liveTask?.isAccepted ?? task.isAccepted) == false && (task.receiverId == currentId), let t = (liveTask ?? task) as SharedTask? {
                        Button("Accept") { accept(t) }
                            .buttonStyle(.borderedProminent)
                            .tint(dynamicPrimaryColor)
                        Button("Reject") {
                            if let tid = t.id { firebaseManager.deleteSharedTask(sharedTaskId: tid) { _ in dismiss() } }
                        }
                        .buttonStyle(.bordered)
                    }
                    if (liveTask?.isAccepted ?? task.isAccepted) && !(liveTask?.isCompleted ?? task.isCompleted) && task.senderId == currentId {
                        if let tid = (liveTask?.id ?? task.id) {
                            Button("Nudge") { firebaseManager.nudgeSharedTask(sharedTaskId: tid, to: task.receiverId) { _ in } }
                                .buttonStyle(.bordered)
                        }
                    }
                    if (liveTask?.isCompleted ?? task.isCompleted), let tid = (liveTask?.id ?? task.id) {
                        Button(role: .destructive) { firebaseManager.deleteSharedTask(sharedTaskId: tid) { _ in dismiss() } } label: { Text("Delete") }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
        .navigationTitle("Task Details")
        .onAppear {
            if let id = task.id {
                listener = firebaseManager.listenToSharedTask(taskId: id) { updated in
                    self.liveTask = updated
                }
            } else {
                self.liveTask = task
            }
        }
        .onDisappear { listener?.remove() }
    }

    private func toggleSubtask(taskId: String, subtask: SharedSubtask) {
        guard var current = liveTask else { return }
        if let idx = current.subtasks.firstIndex(where: { $0.id == subtask.id }) {
            current.subtasks[idx].isDone.toggle()
            liveTask = current
            firebaseManager.updateSharedSubtasks(sharedTaskId: taskId, subtasks: current.subtasks) { _ in }
        }
    }

    private func accept(_ t: SharedTask) {
        firebaseManager.acceptSharedTask(t) { _ in }
    }
} 