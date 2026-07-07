import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct FriendsView: View {
    @State private var searchName: String = ""
    @State private var statusMessage: String?
    @State private var pendingRequests: [FriendRequest] = []
    @State private var acceptedFriends: [FriendEntry] = []
    @State private var friendRequestListener: ListenerRegistration?
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching: Bool = false
    @State private var showSearchResults: Bool = false

    @EnvironmentObject var firebaseManager: FirebaseManager

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Add a Friend").foregroundColor(dynamicTextColor)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(dynamicSecondaryTextColor)
                                
                                AppTextField(placeholder: "Search for friends...", text: $searchName)
                                    .autocapitalization(.none)
                                    .onChange(of: searchName) { _, newValue in
                                        performSearch(searchTerm: newValue)
                                    }
                                
                                if !searchName.isEmpty {
                                    Button(action: {
                                        searchName = ""
                                        searchResults = []
                                        showSearchResults = false
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(dynamicSecondaryTextColor)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(dynamicSecondaryBackgroundColor.opacity(0.3))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dynamicSecondaryTextColor.opacity(0.5), lineWidth: 1)
                            )
                            
                            // Search Results
                            if showSearchResults && !searchResults.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(searchResults) { result in
                                        Button(action: {
                                            sendFriendRequest(to: result.displayName)
                                            searchName = ""
                                            searchResults = []
                                            showSearchResults = false
                                        }) {
                                            HStack {
                                                Image(systemName: "person.circle.fill")
                                                    .foregroundColor(dynamicPrimaryColor)
                                                    .font(.title2)
                                                
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(result.displayName)
                                                        .font(.body)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(dynamicTextColor)
                                                    
                                                    Text("Tap to send friend request")
                                                        .font(.caption)
                                                        .foregroundColor(dynamicSecondaryTextColor)
                                                }
                                                
                                                Spacer()
                                                
                                                Image(systemName: "plus.circle")
                                                    .foregroundColor(dynamicPrimaryColor)
                                                    .font(.title3)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        if result.id != searchResults.last?.id {
                                            Divider()
                                                .background(dynamicSecondaryTextColor.opacity(0.3))
                                        }
                                    }
                                }
                                .background(dynamicSecondaryBackgroundColor.opacity(0.5))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(dynamicSecondaryTextColor.opacity(0.3), lineWidth: 1)
                                )
                            }
                            
                            if isSearching {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Searching...")
                                        .font(.caption)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .listRowBackground(dynamicBackgroundColor)
                    }

                    if let message = statusMessage {
                        Section {
                            Text(message)
                                .foregroundColor(dynamicSecondaryTextColor)
                                .listRowBackground(dynamicSecondaryBackgroundColor)
                        }
                    }

                    Section(header: Text("Pending Requests").foregroundColor(dynamicTextColor)) {
                        ForEach(pendingRequests) { request in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.displayName)
                                    .foregroundColor(dynamicTextColor)

                                HStack {
                                    Button("Accept") {
                                        firebaseManager.acceptFriendRequest(fromUserId: request.fromUserId, displayName: "") { error in
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
                        .listRowBackground(dynamicSecondaryBackgroundColor)
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
                        .listRowBackground(dynamicSecondaryBackgroundColor)
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
            .onAppear {
                firebaseManager.startListeningToAcceptedFriendsLive { updatedFriends in
                    self.acceptedFriends = updatedFriends
                }
                setupFriendRequestListener()
            }

            .onDisappear {
                firebaseManager.stopListeningToAcceptedFriends()
                removeFriendRequestListener()
            }
        }
        .navigationViewStyle(.stack)
    }
    
    private func performSearch(searchTerm: String) {
        guard searchTerm.count >= 2 else {
            searchResults = []
            showSearchResults = false
            isSearching = false
            return
        }
        
        isSearching = true
        showSearchResults = true
        
        // Debounce the search to avoid too many Firebase calls
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Only search if the search term hasn't changed
            guard searchTerm == searchName else { return }
            
            firebaseManager.searchUsers(byDisplayName: searchTerm) { results, error in
                DispatchQueue.main.async {
                    self.isSearching = false
                    
                    if let error = error {
                        print("Search error: \(error.localizedDescription)")
                        self.searchResults = []
                    } else {
                        self.searchResults = results
                    }
                }
            }
        }
    }
    
    private func sendFriendRequest(to displayName: String) {
        firebaseManager.sendFriendRequest(toDisplayName: displayName) { error in
            if let error = error {
                statusMessage = error.localizedDescription
            } else {
                statusMessage = "Friend request sent to \(displayName)"
            }
        }
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

struct FriendEntry: Identifiable, Hashable {
    var id: String { userId }
    let userId: String
    let displayName: String
}
