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
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .bottom, spacing: 6) {
                                if msg.senderId == Auth.auth().currentUser?.uid {
                                    Spacer(minLength: 60)
                                    Text(msg.content)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(dynamicPrimaryColor)
                                        .cornerRadius(18)
                                        .foregroundColor(.white)
                                } else {
                                    ProfilePhotoView(photoURL: friend.profilePhotoURL, size: 28)
                                    Text(msg.content)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(dynamicSecondaryBackgroundColor)
                                        .cornerRadius(18)
                                        .foregroundColor(dynamicTextColor)
                                    Spacer(minLength: 60)
                                }
                            }
                        }
                        Color.clear
                            .frame(height: 8)
                            .id("chatBottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { oldValue, newValue in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
            }

            // Messages-style input bar: clear background, rounded field, attachment, send
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message", text: $newMessage)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(dynamicBackgroundColor)
                    .foregroundColor(dynamicTextColor)
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(dynamicSecondaryTextColor.opacity(0.4), lineWidth: 1)
                    )

                Menu {
                    Button {
                        presentShareComposer = true
                    } label: {
                        Label("Share task", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showShareProgressPicker = true
                    } label: {
                        Label("Share progress", systemImage: "arrowshape.turn.up.right")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(dynamicPrimaryColor)
                }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(newMessage.trimmingCharacters(in: .whitespaces).isEmpty ? dynamicSecondaryTextColor.opacity(0.5) : dynamicPrimaryColor)
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(dynamicSecondaryBackgroundColor)
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
            loginViewModel.currentChatFriendId = friend.userId
            ChatPresenceStore.shared.activeChatFriendId = friend.userId
            // Suppress push banners for the conversation currently on screen.
            NotificationManager.shared.activeChatFriendId = friend.userId
            IncomingChatBannerManager.shared.dismiss()
            listener = firebaseManager.listenToChat(with: friend.userId) { updated in
                Task { @MainActor in
                    self.messages = updated
                    markConversationRead(messages: updated)
                }
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
                if date != nil {
//                    print("✅ [DEBUG] ChatDetailView got last login date: \(date)")
                }
            }
        }

        .onDisappear {
            markConversationRead(messages: messages)
            loginViewModel.currentChatFriendId = nil
            if ChatPresenceStore.shared.activeChatFriendId == friend.userId {
                ChatPresenceStore.shared.activeChatFriendId = nil
            }
            if NotificationManager.shared.activeChatFriendId == friend.userId {
                NotificationManager.shared.activeChatFriendId = nil
            }
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
            SharedTasksInboxView(context: .dm(friend: friend))
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showShareProgressPicker) {
            ShareProgressPickerView(target: .dm(friendId: friend.userId))
                .environmentObject(firebaseManager)
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func markConversationRead(messages: [ChatMessage]) {
        ChatUnreadStore.shared.markDMRead(friendId: friend.userId, upToMessage: messages.last)
    }

    private func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty,
              let currentId = Auth.auth().currentUser?.uid else { return }
        // Clear immediately (like the group chat) — the Firestore completion
        // only fires after server ack, which never arrives while offline even
        // though the message is queued and shown by the listener.
        let content = newMessage
        newMessage = ""
        let message = ChatMessage(
            senderId: currentId,
            receiverId: friend.userId,
            content: content,
            timestamp: Date()
        )
        firebaseManager.sendChatMessage(message) { _ in }
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
            do { 
                try modelContext.save()
                
                // Sync accepted task to Firebase
                if let userId = Auth.auth().currentUser?.uid {
                    let codableTask = TodoItemCodable(from: todo, userId: userId)
                    firebaseManager.saveTodoItem(codableTask) { error in
                        if let error = error {
                            print("ChatDetailView: Failed to sync accepted task to Firebase: \(error.localizedDescription)")
                        } else {
                            print("ChatDetailView: Successfully synced accepted task to Firebase")
                        }
                    }
                }
            } catch { 
                print("Failed to save shared task to local list: \(error)") 
            }
        }
    }
}

