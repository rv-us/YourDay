import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SharedTasksInboxView: View {
    let friend: FriendEntry
    @EnvironmentObject var firebaseManager: FirebaseManager
    @Environment(\.modelContext) private var modelContext
    @State private var tasks: [SharedTask] = []
    @State private var listener: ListenerRegistration?

    var body: some View {
        NavigationView {
            List {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(task.title)
                                .font(.headline)
                                .foregroundColor(dynamicTextColor)
                            if !task.isAccepted {
                                Text("Pending")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(6)
                            }
                            Spacer()
                        }
                        Text(task.detail)
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(task.dueDate, style: .date)
                            .font(.caption2)
                            .foregroundColor(.gray)

                        if !task.subtasks.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(task.subtasks) { st in
                                    HStack(spacing: 8) {
                                        Image(systemName: st.isDone ? "checkmark.square.fill" : "square")
                                            .foregroundColor(dynamicPrimaryColor)
                                        Text(st.title)
                                            .foregroundColor(dynamicTextColor)
                                        Spacer()
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }

                        HStack(spacing: 8) {
                            if !task.isAccepted, task.receiverId == Auth.auth().currentUser?.uid {
                                Button("Accept") { accept(task) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(dynamicPrimaryColor)

                                Button("Reject") {
                                    if let id = task.id { firebaseManager.deleteSharedTask(sharedTaskId: id) { _ in } }
                                }
                                .buttonStyle(.bordered)
                            }
                            // Nudge logic:
                            // - Regular shared task (isProgressShare = false): sender can nudge receiver after acceptance
                            // - Progress share (isProgressShare = true): receiver can nudge sender, sender cannot nudge
                            if task.isAccepted && !task.isCompleted {
                                // Regular shared task: sender nudges receiver
                                if !task.isProgressShare && task.senderId == Auth.auth().currentUser?.uid, let id = task.id {
                                    Button("Nudge") { firebaseManager.nudgeSharedTask(sharedTaskId: id, to: task.receiverId) { _ in } }
                                        .buttonStyle(.bordered)
                                }
                                // Progress share: receiver nudges sender
                                if task.isProgressShare && task.receiverId == Auth.auth().currentUser?.uid, let id = task.id {
                                    Button("Nudge") { firebaseManager.nudgeSharedTask(sharedTaskId: id, to: task.senderId) { _ in } }
                                        .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if let id = task.id {
                            Button(role: .destructive) {
                                firebaseManager.deleteSharedTask(sharedTaskId: id) { _ in }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle("Shared Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                listener = firebaseManager.listenToSharedTasks(with: friend.userId) { updated in
                    tasks = updated
                }
            }
            .onDisappear {
                listener?.remove()
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func accept(_ task: SharedTask) {
        firebaseManager.acceptSharedTask(task) { _ in
            // Ensure it exists in main list for receiver
            let localSubtasks: [Subtask] = task.subtasks.map { Subtask(id: UUID(), title: $0.title, isDone: $0.isDone) }
            let todo = TodoItem(
                title: task.title,
                detail: task.detail,
                dueDate: task.dueDate,
                isDone: false,
                subtasks: localSubtasks,
                position: 0,
                origin: .today,
                sharedTaskId: task.id,
                isSharedPending: false
            )
            modelContext.insert(todo)
            do { 
                try modelContext.save()
                
                // Sync accepted task to Firebase
                if let userId = FirebaseAuth.Auth.auth().currentUser?.uid {
                    let codableTask = TodoItemCodable(from: todo, userId: userId)
                    firebaseManager.saveTodoItem(codableTask) { error in
                        if let error = error {
                            print("SharedTasksInboxView: Failed to sync accepted task to Firebase: \(error.localizedDescription)")
                        } else {
                            print("SharedTasksInboxView: Successfully synced accepted task to Firebase")
                        }
                    }
                }
            } catch { 
                print("Failed to insert accepted task into main list: \(error)") 
            }
        }
    }
} 