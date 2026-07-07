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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    groupNameSection
                    membersSection

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(dynamicDestructiveColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(dynamicBackgroundColor)
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicBackgroundColor, for: .navigationBar)
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
        .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
    }

    private var groupNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group Name")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            AppTextField(placeholder: "e.g. Study Crew", text: $groupName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Text("Choose a name everyone in the group will see.")
                .font(.footnote)
                .foregroundColor(dynamicSecondaryTextColor.opacity(0.65))
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Members")
                .font(.headline)
                .foregroundColor(dynamicTextColor)

            if !friends.isEmpty {
                Text("\(selectedFriendIds.count) selected")
                    .font(.footnote)
                    .foregroundColor(dynamicSecondaryTextColor.opacity(0.65))
            }

            if friends.isEmpty {
                Text("Add some friends first to create a group.")
                    .font(.subheadline)
                    .foregroundColor(dynamicSecondaryTextColor)
            } else {
                VStack(spacing: 0) {
                    ForEach(friends) { friend in
                        Button {
                            if selectedFriendIds.contains(friend.userId) {
                                selectedFriendIds.remove(friend.userId)
                            } else {
                                selectedFriendIds.insert(friend.userId)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedFriendIds.contains(friend.userId) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(dynamicPrimaryColor)
                                Text(friend.displayName)
                                    .foregroundColor(dynamicTextColor)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)

                        if friend.id != friends.last?.id {
                            Divider()
                                .overlay(dynamicSecondaryTextColor.opacity(0.2))
                        }
                    }
                }
            }
        }
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
