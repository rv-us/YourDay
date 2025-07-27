import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FriendsView: View {
    @State private var searchName: String = ""
    @State private var statusMessage: String?
    @State private var pendingRequests: [FriendRequest] = []
    @State private var acceptedFriends: [FriendEntry] = []
    @State private var friendRequestListener: ListenerRegistration?

    @EnvironmentObject var firebaseManager: FirebaseManager

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Add a Friend").foregroundColor(dynamicTextColor)) {
                        TextField("Enter username", text: $searchName)
                            .autocapitalization(.none)
                            .foregroundColor(dynamicTextColor)

                        Button(action: {
                            firebaseManager.sendFriendRequest(toDisplayName: searchName) { error in
                                if let error = error {
                                    statusMessage = error.localizedDescription
                                } else {
                                    statusMessage = "Friend request sent to \(searchName)"
                                    searchName = ""
                                }
                            }
                        }) {
                            Text("Send Friend Request")
                                .foregroundColor(dynamicPrimaryColor)
                        }
                    }

                    if let message = statusMessage {
                        Section {
                            Text(message)
                                .foregroundColor(dynamicSecondaryTextColor)
                        }
                    }

                    Section(header: Text("Pending Requests").foregroundColor(dynamicTextColor)) {
                        ForEach(pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.displayName)
                                    .foregroundColor(dynamicTextColor)

                                HStack {
                                    Button("Accept") {
                                        firebaseManager.acceptFriendRequest(fromUserId: request.fromUserId, displayName: request.displayName) { error in
                                            if let error = error {
                                                statusMessage = error.localizedDescription
                                            } else {
                                                fetchRequestsAndFriends()
                                                statusMessage = "Friend added"
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(dynamicPrimaryColor)

                                    Button("Decline") {
                                        firebaseManager.declineFriendRequest(fromUserId: request.fromUserId) { error in
                                            if let error = error {
                                                statusMessage = error.localizedDescription
                                            } else {
                                                fetchRequestsAndFriends()
                                                statusMessage = "Request declined"
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundColor(dynamicDestructiveColor)
                                }
                            }
                        }
                    }

                    Section(header: Text("Your Friends").foregroundColor(dynamicTextColor)) {
                        ForEach(acceptedFriends) { friend in
                            HStack {
                                Text(friend.displayName)
                                    .foregroundColor(dynamicTextColor)
                                Spacer()
                                Button("Remove") {
                                    firebaseManager.removeFriend(friendUserId: friend.userId) { error in
                                        if let error = error {
                                            statusMessage = error.localizedDescription
                                        } else {
                                            fetchRequestsAndFriends()
                                            statusMessage = "Friend removed"
                                        }
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(dynamicDestructiveColor)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(dynamicBackgroundColor)
            }
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Friends")
                        .fontWeight(.bold)
                        .foregroundColor(dynamicTextColor)
                }
            }
            .onAppear {
                fetchRequestsAndFriends()
                setupFriendRequestListener()
            }
            .onDisappear {
                removeFriendRequestListener()
            }
        }
        .navigationViewStyle(.stack)
    }

    func fetchRequestsAndFriends() {
        firebaseManager.fetchPendingFriendRequests { requests in
            self.pendingRequests = requests
        }
        firebaseManager.fetchAcceptedFriends { friends in
            self.acceptedFriends = friends
        }
    }
    
    func setupFriendRequestListener() {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        let db = Firestore.firestore()
        friendRequestListener = db.collection("users").document(currentUserId)
            .collection("friend_requests")
            .whereField("status", isEqualTo: "pending")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error listening to friend requests: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.pendingRequests = []
                    return
                }
                
                let requests: [FriendRequest] = documents.compactMap { doc in
                    let data = doc.data()
                    guard let fromUserId = data["fromUserId"] as? String,
                          let displayName = data["displayName"] as? String else {
                        return nil
                    }
                    return FriendRequest(fromUserId: fromUserId, displayName: displayName)
                }
                
                DispatchQueue.main.async {
                    self.pendingRequests = requests
                }
            }
    }
    
    func removeFriendRequestListener() {
        friendRequestListener?.remove()
        friendRequestListener = nil
    }
}

struct FriendRequest: Identifiable {
    var id: String { fromUserId }
    let fromUserId: String
    let displayName: String
}

struct FriendEntry: Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
}
