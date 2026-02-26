import SwiftUI
import FirebaseAuth

struct CreateGroupChatView: View {
    @EnvironmentObject var firebaseManager: FirebaseManager
    @EnvironmentObject var loginViewModel: LoginViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var groupName = ""
    @State private var friends: [FriendEntry] = []
    @State private var selectedFriendIds: Set<String> = []
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdGroup: GroupConversation?

    private var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty && !selectedFriendIds.isEmpty && !isCreating
    }

    var body: some View {
        NavigationView {
            List {
                Section("Group Name") {
                    TextField("e.g. Study Crew", text: $groupName)
                        .foregroundColor(dynamicTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                Section("Add Members") {
                    if friends.isEmpty {
                        Text("Add some friends first to create a group.")
                            .font(.subheadline)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(friends) { friend in
                            HStack {
                                Image(systemName: selectedFriendIds.contains(friend.userId) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(dynamicPrimaryColor)
                                Text(friend.displayName)
                                    .foregroundColor(dynamicTextColor)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedFriendIds.contains(friend.userId) {
                                    selectedFriendIds.remove(friend.userId)
                                } else {
                                    selectedFriendIds.insert(friend.userId)
                                }
                            }
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                        }
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
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor)
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(dynamicPrimaryColor)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        createGroup()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create")
                        }
                    }
                    .foregroundColor(canCreate ? dynamicPrimaryColor : dynamicSecondaryTextColor)
                    .disabled(!canCreate)
                }
            }
            .onAppear {
                firebaseManager.fetchAcceptedFriends { fetched in
                    friends = fetched
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private func createGroup() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        let trimmedName = groupName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !selectedFriendIds.isEmpty else { return }

        isCreating = true
        errorMessage = nil

        var memberIds = Array(selectedFriendIds)
        memberIds.append(currentUserId)

        var memberDisplayNames: [String: String] = [:]
        for friend in friends where selectedFriendIds.contains(friend.userId) {
            memberDisplayNames[friend.userId] = friend.displayName
        }
        // Add current user's display name
        let myDisplayName = loginViewModel.userDisplayName ?? Auth.auth().currentUser?.displayName ?? "Me"
        memberDisplayNames[currentUserId] = myDisplayName

        firebaseManager.createGroup(name: trimmedName, memberIds: memberIds, memberDisplayNames: memberDisplayNames) { error, groupId in
            isCreating = false
            if let error {
                errorMessage = error.localizedDescription
                return
            }
            dismiss()
        }
    }
}
