import SwiftUI
import FirebaseAuth

struct GroupMembersView: View {
    let group: GroupConversation
    @EnvironmentObject var firebaseManager: FirebaseManager
    @Environment(\.dismiss) private var dismiss

    @State private var members: [GroupMember] = []
    @State private var showAddMemberPicker = false
    @State private var friends: [FriendEntry] = []
    @State private var isLeaving = false
    @State private var errorMessage: String?

    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    private var isAdmin: Bool { group.adminId == currentUserId }
    private var friendsNotInGroup: [FriendEntry] {
        // Filter against the live members list, not group.memberIds — the
        // GroupConversation passed in is a snapshot and goes stale as soon as
        // someone is added or removed in this view.
        friends.filter { friend in !members.contains { $0.id == friend.userId } }
    }

    var body: some View {
        NavigationView {
            List {
                Section("Members") {
                    ForEach(members) { member in
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundColor(dynamicPrimaryColor)
                            Text(member.displayName)
                                .foregroundColor(dynamicTextColor)
                            if member.role == "admin" {
                                Text("Admin")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(dynamicSecondaryTextColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(6)
                            }
                            Spacer()
                            if isAdmin, member.id != currentUserId {
                                Button("Remove") {
                                    if let uid = member.id {
                                        firebaseManager.removeMemberFromGroup(groupId: group.id ?? "", userId: uid) { _ in
                                            members.removeAll { $0.id == uid }
                                        }
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(dynamicDestructiveColor)
                            }
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(dynamicDestructiveColor)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Button(role: .destructive) {
                        leaveGroup()
                    } label: {
                        HStack {
                            if isLeaving {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Leave Group")
                                .foregroundColor(dynamicDestructiveColor)
                        }
                    }
                    .disabled(isLeaving)
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddMemberPicker = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(dynamicPrimaryColor)
                    }
                }
            }
            .onAppear {
                loadMembers()
                firebaseManager.fetchAcceptedFriends { fetched in
                    friends = fetched
                }
            }
            .sheet(isPresented: $showAddMemberPicker) {
                AddGroupMemberPickerView(
                    friends: friendsNotInGroup,
                    groupId: group.id ?? ""
                ) { userId, displayName in
                    firebaseManager.addMemberToGroup(groupId: group.id ?? "", userId: userId, displayName: displayName) { error in
                        if error == nil {
                            let newMember = GroupMember(id: userId, displayName: displayName, joinedAt: Date(), role: "member")
                            members.append(newMember)
                        }
                    }
                }
                .environmentObject(firebaseManager)
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func loadMembers() {
        firebaseManager.fetchGroupMembers(groupId: group.id ?? "") { fetched in
            members = fetched
        }
    }

    private func leaveGroup() {
        isLeaving = true
        firebaseManager.leaveGroup(groupId: group.id ?? "") { error in
            isLeaving = false
            if let error {
                errorMessage = error.localizedDescription
            } else {
                dismiss()
            }
        }
    }
}

// Inline picker for adding a member from the friend list
private struct AddGroupMemberPickerView: View {
    let friends: [FriendEntry]
    let groupId: String
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if friends.isEmpty {
                    Text("All your friends are already in this group.")
                        .font(.subheadline)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(friends) { friend in
                        Button {
                            onAdd(friend.userId, friend.displayName)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundColor(dynamicPrimaryColor)
                                Text(friend.displayName)
                                    .foregroundColor(dynamicTextColor)
                            }
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }
}
