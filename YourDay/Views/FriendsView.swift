//
//  FriendsView.swift
//  YourDay
//
//  Created by Rachit Verma on 7/10/25.
//

import SwiftUI

struct FriendsView: View {
    @State private var searchName: String = ""
    @State private var statusMessage: String?
    @State private var pendingRequests: [FriendRequest] = []
    @State private var acceptedFriends: [FriendEntry] = []
    
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
                            Text(friend.displayName)
                                .foregroundColor(dynamicTextColor)
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
            .onAppear(perform: fetchRequestsAndFriends)
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
