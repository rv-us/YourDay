import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct GroupChatDetailView: View {
    let group: GroupConversation

    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [ChatMessage] = []
    @State private var listener: ListenerRegistration?
    @State private var newMessage = ""

    @State private var members: [GroupMember] = []
    @State private var showMembersSheet = false
    @State private var showInbox = false

    // Task sharing two-step flow
    @State private var showMemberPickerForTask = false
    @State private var taskRecipients: [GroupMember] = []
    @State private var showTaskComposer = false

    // Progress sharing two-step flow
    @State private var showMemberPickerForProgress = false
    @State private var progressRecipients: [GroupMember] = []
    @State private var showProgressPicker = false

    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var myDisplayName: String {
        loginViewModel.userDisplayName ?? Auth.auth().currentUser?.displayName ?? "Me"
    }

    // Members excluding current user (for picker)
    private var otherMembers: [GroupMember] {
        members.filter { $0.id != currentUserId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(messages) { msg in
                            VStack(alignment: msg.senderId == currentUserId ? .trailing : .leading, spacing: 2) {
                                // Show sender name above non-self bubbles
                                if msg.senderId != currentUserId, let name = msg.senderDisplayName {
                                    Text(name)
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                        .padding(.leading, 4)
                                }
                                HStack(alignment: .bottom, spacing: 0) {
                                    if msg.senderId == currentUserId {
                                        Spacer(minLength: 60)
                                        Text(msg.content)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 10)
                                            .background(dynamicPrimaryColor)
                                            .cornerRadius(18)
                                            .foregroundColor(.white)
                                    } else {
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
                        }
                        Color.clear
                            .frame(height: 8)
                            .id("chatBottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("chatBottom", anchor: .bottom)
                    }
                }
            }

            // Input bar
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
                        showMemberPickerForTask = true
                    } label: {
                        Label("Share task", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showMemberPickerForProgress = true
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
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showMembersSheet = true
                    } label: {
                        Image(systemName: "person.3")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                    Button {
                        showInbox = true
                    } label: {
                        Image(systemName: "tray.full")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
        }
        .onAppear {
            listener = firebaseManager.listenToGroupChat(groupId: group.id ?? "") { updated in
                messages = updated
            }
            firebaseManager.fetchGroupMembers(groupId: group.id ?? "") { fetched in
                members = fetched
            }
        }
        .onDisappear {
            listener?.remove()
        }
        .sheet(isPresented: $showMembersSheet) {
            GroupMembersView(group: group)
                .environmentObject(firebaseManager)
        }
        .sheet(isPresented: $showInbox) {
            SharedTasksInboxView(context: .group(groupId: group.id ?? "", groupName: group.name))
                .environmentObject(firebaseManager)
                .environment(\.modelContext, modelContext)
        }
        // Step 1 (task): pick recipients
        .sheet(isPresented: $showMemberPickerForTask, onDismiss: {
            if !taskRecipients.isEmpty {
                showTaskComposer = true
            }
        }) {
            GroupMemberPickerView(members: otherMembers) { chosen in
                taskRecipients = chosen
            }
        }
        // Step 2 (task): compose task
        .sheet(isPresented: $showTaskComposer, onDismiss: {
            taskRecipients = []
        }) {
            let recipients = taskRecipients
            NewItemview(newItemPresented: $showTaskComposer, selectedOrigin: .today, onSaveOverride: { title, detail, dueDate, subtasks, _ in
                let sharedSubtasks = subtasks.enumerated().map { idx, st in SharedSubtask(id: "sub_\(idx)", title: st.title, isDone: false) }
                let recipientIds = recipients.compactMap { $0.id }
                firebaseManager.sendSharedTaskToGroup(
                    groupId: group.id ?? "",
                    groupName: group.name,
                    recipientIds: recipientIds,
                    title: title,
                    detail: detail,
                    dueDate: dueDate,
                    subtasks: sharedSubtasks,
                    senderDisplayName: myDisplayName
                ) { _, _ in }
            })
            .environment(\.modelContext, modelContext)
        }
        // Step 1 (progress): pick recipients
        .sheet(isPresented: $showMemberPickerForProgress, onDismiss: {
            if !progressRecipients.isEmpty {
                showProgressPicker = true
            }
        }) {
            GroupMemberPickerView(members: otherMembers) { chosen in
                progressRecipients = chosen
            }
        }
        // Step 2 (progress): pick which task to share
        .sheet(isPresented: $showProgressPicker, onDismiss: {
            progressRecipients = []
        }) {
            let recipients = progressRecipients
            ShareProgressPickerView(target: .group(
                groupId: group.id ?? "",
                recipientIds: recipients.compactMap { $0.id },
                senderDisplayName: myDisplayName
            ))
            .environmentObject(firebaseManager)
            .environment(\.modelContext, modelContext)
        }
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespaces).isEmpty,
              currentUserId != nil else { return }
        let content = newMessage
        newMessage = ""
        firebaseManager.sendGroupMessage(
            groupId: group.id ?? "",
            content: content,
            senderDisplayName: myDisplayName
        ) { _ in }
    }
}
