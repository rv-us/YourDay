//
//  ChatDetailView.swift
//  YourDay
//
//  Created by Rachit Verma on 8/2/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore



struct ChatDetailView: View {
    let friend: FriendEntry
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [ChatMessage] = []
    @State private var newMessage = ""
    @State private var listener: ListenerRegistration?

    @State private var sharedTasks: [SharedTask] = []
    @State private var sharedTaskListener: ListenerRegistration?
    @State private var showNewSharedTaskSheet = false
    @State private var newSharedTitle = ""
    @State private var newSharedDetail = ""
    @State private var newSharedDueDate = Date().addingTimeInterval(24*60*60)
    @State private var presentShareComposer = false
    @State private var pendingLocalShareItem: TodoItem?
    @State private var tempOutgoingSharedTasks: [SharedTask] = []
    
    private var mergedSharedTasks: [SharedTask] {
        var seenById: Set<String> = []
        var result: [SharedTask] = []
        
        for t in sharedTasks {
            if let id = t.id { seenById.insert(id) }
            result.append(t)
        }
        for t in tempOutgoingSharedTasks {
            if let id = t.id {
                if !seenById.contains(id) {
                    result.append(t)
                }
            } else {
                if !result.contains(where: { $0.title == t.title && $0.detail == t.detail && abs($0.dueDate.timeIntervalSince1970 - t.dueDate.timeIntervalSince1970) < 1 && $0.senderId == t.senderId && $0.receiverId == t.receiverId }) {
                    result.append(t)
                }
            }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }
    @State private var showInbox = false
    @State private var showShareProgressPicker = false

    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { msg in
                            HStack {
                                if msg.senderId == Auth.auth().currentUser?.uid {
                                    Spacer()
                                    Text(msg.content)
                                        .padding()
                                        .background(dynamicPrimaryColor)
                                        .cornerRadius(12)
                                        .foregroundColor(.white)
                                } else {
                                    Text(msg.content)
                                        .padding()
                                        .background(dynamicSecondaryBackgroundColor)
                                        .cornerRadius(12)
                                        .foregroundColor(dynamicTextColor)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            HStack {
                TextField("Message...", text: $newMessage)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Send") {
                    guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty,
                          let currentId = Auth.auth().currentUser?.uid else { return }

                    let message = ChatMessage(
                        senderId: currentId,
                        receiverId: friend.userId,
                        content: newMessage,
                        timestamp: Date()
                    )
                    firebaseManager.sendChatMessage(message) { _ in
                        newMessage = ""
                    }
                }
                .foregroundColor(dynamicPrimaryColor)

                Button {
                    presentShareComposer = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .foregroundColor(dynamicPrimaryColor)
                .padding(.leading, 4)

                Button {
                    showShareProgressPicker = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .foregroundColor(dynamicPrimaryColor)
                .padding(.leading, 4)
            }
            .padding()
            .background(dynamicBackgroundColor)
        }
        .navigationTitle(friend.displayName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showInbox = true
                } label: {
                    Image(systemName: "tray.full")
                        .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .onAppear {
            listener = firebaseManager.listenToChat(with: friend.userId) { updated in
                self.messages = updated
            }
            sharedTaskListener = firebaseManager.listenToSharedTasks(with: friend.userId) { updated in
                self.sharedTasks = updated
                // Prune any temporary items that now exist in Firestore
                let updatedIds = Set(updated.compactMap { $0.id })
                tempOutgoingSharedTasks.removeAll { temp in
                    if let id = temp.id { return updatedIds.contains(id) }
                    // fallback match by content
                    return updated.contains(where: { $0.title == temp.title && $0.detail == temp.detail && abs($0.dueDate.timeIntervalSince1970 - temp.dueDate.timeIntervalSince1970) < 1 && $0.senderId == temp.senderId && $0.receiverId == temp.receiverId })
                }
            }

            firebaseManager.fetchLastLoginDate(for: friend.userId) { date in
                if let date = date {
//                    print("✅ [DEBUG] ChatDetailView got last login date: \(date)")
                }
            }
        }

        .onDisappear {
            listener?.remove()
            sharedTaskListener?.remove()
        }
        .sheet(isPresented: $presentShareComposer, onDismiss: {
            if let item = pendingLocalShareItem, let sharedId = item.sharedTaskId {
                // Listen for acceptance updates for this shared task
                _ = firebaseManager.listenToSharedTask(taskId: sharedId) { updated in
                    guard let updated = updated else { return }
                    if updated.isAccepted {
                        // Optionally update local item state if needed
                        item.isSharedPending = false
                    }
                }
            }
        }) {
            NewItemview(newItemPresented: $presentShareComposer, selectedOrigin: .today, onSaveOverride: { title, detail, dueDate, subtasks, _ in
                // Send shared task only; do not insert locally
                let sharedSubtasks = subtasks.enumerated().map { idx, st in SharedSubtask(id: "sub_\(idx)", title: st.title, isDone: false) }
                firebaseManager.sendSharedTask(to: friend.userId, title: title, detail: detail, dueDate: dueDate, subtasks: sharedSubtasks) { error, sharedId in
                    if error == nil {
                        // Show a temporary pending chip until listener returns it
                        let temp = SharedTask(id: sharedId, senderId: Auth.auth().currentUser?.uid ?? "", receiverId: friend.userId, title: title, detail: detail, dueDate: dueDate, isAccepted: false, isCompleted: false, createdAt: Date(), completedAt: nil, subtasks: sharedSubtasks)
                        tempOutgoingSharedTasks.append(temp)
                        // Also inject a chat message indicating a task was sent
                        if let currentId = Auth.auth().currentUser?.uid {
                            let info = "Sent task: \(title)"
                            let msg = ChatMessage(senderId: currentId, receiverId: friend.userId, content: info, timestamp: Date())
                            firebaseManager.sendChatMessage(msg) { _ in }
                        }
                    }
                }
            })
                .environment(\.modelContext, modelContext)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("NewItemSavedNotification"))) { notification in
                    // Ignore local insert notifications when sharing-only
                }
                .onChange(of: presentShareComposer) { _, isPresented in
                    // no-op
                }
                .onAppear {
                    // no-op
                }
        }
        .sheet(isPresented: $showInbox) {
            SharedTasksInboxView(friend: friend)
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showShareProgressPicker) {
            ShareProgressPickerView(friendId: friend.userId)
                .environmentObject(firebaseManager)
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func accept(_ task: SharedTask) {
        firebaseManager.acceptSharedTask(task) { _ in
            // Create a local TodoItem linked to this shared task
            let todo = TodoItem(
                title: task.title,
                detail: task.detail,
                dueDate: task.dueDate,
                isDone: false,
                subtasks: [],
                position: 0,
                origin: .today,
                sharedTaskId: task.id
            )
            modelContext.insert(todo)
            do { try modelContext.save() } catch { print("Failed to save shared task to local list: \(error)") }
        }
    }
}

