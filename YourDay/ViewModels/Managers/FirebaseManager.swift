//
//  FirebaseManager.swift
//  YourDay
//
//  Created by Rachit Verma on 5/19/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

struct UserSearchResult: Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
}

final class TaskProofFeedListenerToken {
    fileprivate var friendsListener: ListenerRegistration?
    fileprivate var postListeners: [String: ListenerRegistration] = [:]
    fileprivate var authorPosts: [String: [TaskProofPost]] = [:]
    fileprivate var friendSinceMap: [String: Date] = [:]

    func remove() {
        friendsListener?.remove()
        postListeners.values.forEach { $0.remove() }
        postListeners.removeAll()
        authorPosts.removeAll()
        friendSinceMap.removeAll()
    }
}

/// Per-task proof bonus: task ids that earned 1.5× yesterday; `qualifyingPostIds` are deleted after daily eval when save succeeds.
/// `proofVoteRollups*` aggregate all check/x votes (including self) per linked task for summary UI.
struct YesterdayTaskProofTallyResult {
    let eligibleLocalTaskIds: Set<String>
    let eligibleSharedTaskIds: Set<String>
    let qualifyingPostIds: [String]
    let proofVoteRollupsByLocalTaskId: [String: ProofFeedVoteRollup]
    let proofVoteRollupsBySharedTaskId: [String: ProofFeedVoteRollup]
}

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    private var db = Firestore.firestore()
    private var listenerRegistrations: [ListenerRegistration] = []
    var acceptedFriendsListener: ListenerRegistration?

    private var userId: String? {
        Auth.auth().currentUser?.uid
    }

    // MARK: - PlayerStats (Using PlayerStatsCodable)
    func savePlayerStats(_ playerStatsCodable: PlayerStatsCodable, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            let error = NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated for saving PlayerStats."])
            completion(error)
            return
        }
        let docRef = db.collection("users").document(userId).collection("playerData").document("playerStats")
        do {
            try docRef.setData(from: playerStatsCodable) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func loadPlayerStats(completion: @escaping (PlayerStatsCodable?, Error?) -> Void) {
        guard let userId = userId else {
            let error = NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated for loading PlayerStats."])
            completion(nil, error)
            return
        }
        let docRef = db.collection("users").document(userId).collection("playerData").document("playerStats")
        docRef.getDocument { (document, error) in
            if let error = error {
                completion(nil, error)
                return
            }
            if let document = document, document.exists {
                do {
                    let playerStatsCodable = try document.data(as: PlayerStatsCodable.self)
                    completion(playerStatsCodable, nil)
                } catch let decodeError {
                    print("FirebaseManager: Failed to decode PlayerStatsCodable from Firestore: \(decodeError.localizedDescription)")
                    
                    // Handle schema migration - create default data if decoding fails
                    print("FirebaseManager: Creating default PlayerStats due to schema incompatibility")
                    let defaultStats = PlayerStatsCodable()
                    completion(defaultStats, nil)
                }
            } else {
                print("No PlayerStatsCodable found for user \(userId). Creating and saving default.")
                let defaultStats = PlayerStatsCodable()
                self.savePlayerStats(defaultStats) { saveError in
                    if let saveError = saveError {
                        completion(nil, saveError)
                    } else {
                        completion(defaultStats, nil)
                    }
                }
            }
        }
    }

    // MARK: - Leaderboard
    /// Saves or updates a user's entry in the leaderboard collection.
    func updateLeaderboardEntry(entry: LeaderboardEntry, completion: @escaping (Error?) -> Void) {
        // The document ID for a leaderboard entry should be the user's ID.
        let docRef = db.collection("leaderboard_entries").document(entry.id)
        do {
            // Use setData(from: merge: true) to update if exists, or create if not.
            // This is useful if you only want to update specific fields, but for a full entry,
            // direct setData is also fine (it will overwrite).
            try docRef.setData(from: entry, merge: true) { error in // merge:true is good for updates
                if let error = error {
                    print("Error updating leaderboard entry for \(entry.id): \(error.localizedDescription)")
                } else {
                    print("Leaderboard entry updated for \(entry.id)")
                }
                completion(error)
            }
        } catch {
            print("Error encoding leaderboard entry for \(entry.id): \(error.localizedDescription)")
            completion(error)
        }
    }

    /// Fetches leaderboard entries, ordered and limited.
    func fetchLeaderboardEntries(orderBy field: String, descending: Bool = true, limit: Int = 100, completion: @escaping ([LeaderboardEntry]?, Error?) -> Void) {
        db.collection("leaderboard_entries")
          .order(by: field, descending: descending)
          .limit(to: limit)
          .getDocuments { (querySnapshot, error) in
            if let error = error {
                print("Error fetching leaderboard entries: \(error.localizedDescription)")
                completion(nil, error)
                return
            }
            
            let entries = querySnapshot?.documents.compactMap { document -> LeaderboardEntry? in
                do {
                    // Manually add the document ID to the entry if it's not stored as a field
                    let entry = try document.data(as: LeaderboardEntry.self)
                    // If LeaderboardEntry's 'id' field is meant to be the documentID (userID)
                    // and it's not explicitly stored as a field in Firestore,
                    // you can assign it here:
                    // entry.id = document.documentID // This assumes LeaderboardEntry.id is var
                    // However, our LeaderboardEntry has 'id' as a Codable field mapped to 'userID'.
                    // If 'userID' is not stored in the document, you'd need to adjust.
                    // For now, assuming 'userID' field exists or LeaderboardEntry.id is correctly decoded.
                    return entry
                } catch {
                    print("Error decoding leaderboard entry: \(error.localizedDescription)")
                    return nil
                }
            } ?? []
            
            print("Fetched \(entries.count) leaderboard entries.")
            completion(entries, nil)
        }
    }
    func deleteAllUserData(completion: @escaping (Error?) -> Void) {
            guard let userId = userId else {
                let error = NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated for deletion."])
                completion(error)
                return
            }

            let group = DispatchGroup()
            var capturedError: Error?

            // Delete PlayerStats document
            group.enter()
            let playerStatsDocRef = db.collection("users").document(userId).collection("playerData").document("playerStats")
            playerStatsDocRef.delete { error in
                if let error = error {
                    print("Error deleting playerStats for user \(userId): \(error.localizedDescription)")
                    capturedError = error
                } else {
                    print("Deleted playerStats for user \(userId).")
                }
                group.leave()
            }

            // Delete Leaderboard Entry document
            group.enter()
            let leaderboardDocRef = db.collection("leaderboard_entries").document(userId)
            leaderboardDocRef.delete { error in
                if let error = error {
                    print("Error deleting leaderboard entry for user \(userId): \(error.localizedDescription)")
                    if capturedError == nil { capturedError = error }
                } else {
                    print("Deleted leaderboard entry for user \(userId).")
                }
                group.leave()
            }

            // Delete all Tasks documents
            group.enter()
            deleteAllDocumentsInSubcollection(userId: userId, subcollection: "tasks") { error in
                if let error = error {
                    print("Error deleting tasks for user \(userId): \(error.localizedDescription)")
                    if capturedError == nil { capturedError = error }
                } else {
                    print("Deleted tasks for user \(userId).")
                }
                group.leave()
            }

            // Delete all Notes documents
            group.enter()
            deleteAllDocumentsInSubcollection(userId: userId, subcollection: "notes") { error in
                if let error = error {
                    print("Error deleting notes for user \(userId): \(error.localizedDescription)")
                    if capturedError == nil { capturedError = error }
                } else {
                    print("Deleted notes for user \(userId).")
                }
                group.leave()
            }

            // Notify when all deletions are complete
            group.notify(queue: .main) {
                if let error = capturedError {
                    print("Finished deleting user data for \(userId) with errors.")
                    completion(error)
                } else {
                    print("Successfully deleted all user data from Firestore for user \(userId).")
                    completion(nil)
                }
            }
        }

    /// Helper method to delete all documents in a user's subcollection
    private func deleteAllDocumentsInSubcollection(userId: String, subcollection: String, completion: @escaping (Error?) -> Void) {
        db.collection("users").document(userId).collection(subcollection)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else {
                    completion(nil)
                    return
                }

                if let error = error {
                    completion(error)
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    completion(nil)
                    return
                }

                let batch = self.db.batch()
                for doc in documents {
                    batch.deleteDocument(doc.reference)
                }

                batch.commit { error in
                    completion(error)
                }
            }
    }

    func checkDisplayNameExists(displayName: String, completion: @escaping (Bool, Error?) -> Void) {
            db.collection("leaderboard_entries")
              .whereField("displayName", isEqualTo: displayName)
              .limit(to: 1) // We only need to know if at least one exists
              .getDocuments { (querySnapshot, error) in
                if let error = error {
                    print("Error checking display name existence for '\(displayName)': \(error.localizedDescription)")
                    completion(false, error)
                    return
                }
                
                if let snapshot = querySnapshot, !snapshot.documents.isEmpty {
                    // If we found any document with this display name
                    print("Display name '\(displayName)' exists.")
                    completion(true, nil)
                } else {
                    // No document found with this display name
                    print("Display name '\(displayName)' does not exist.")
                    completion(false, nil)
                }
            }
        }
    // MARK: - User Search for Friends
    func searchUsers(byDisplayName searchTerm: String, completion: @escaping ([UserSearchResult], Error?) -> Void) {
        guard let currentUserId = userId else {
            completion([], NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Don't search if term is too short
        guard searchTerm.count >= 2 else {
            completion([], nil)
            return
        }
        
        let leaderboardRef = db.collection("leaderboard_entries")
        
        // Search for users whose display name starts with the search term
        leaderboardRef.whereField("displayName", isGreaterThanOrEqualTo: searchTerm)
            .whereField("displayName", isLessThan: searchTerm + "\u{f8ff}")
            .limit(to: 10) // Limit results for performance
            .getDocuments { snapshot, error in
                if let error = error {
                    completion([], error)
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    completion([], nil)
                    return
                }
                
                let searchResults: [UserSearchResult] = documents.compactMap { doc in
                    let data = doc.data()
                    guard let displayName = data["displayName"] as? String,
                          let userId = doc.documentID as String?,
                          userId != currentUserId else { // Don't show current user
                        return nil
                    }
                    
                    return UserSearchResult(
                        userId: userId,
                        displayName: displayName
                    )
                }
                
                completion(searchResults, nil)
            }
    }
    
    // MARK: - Other Data Types (Placeholders - ensure Codable versions or mapping)
    // func saveTodoItem(_ todoItem: CodableTodoItem, completion: @escaping (Error?) -> Void) { ... }
    // func loadTodoItems(completion: @escaping ([CodableTodoItem]?, Error?) -> Void) { ... }
    // ... and so on for NoteItem, DailySummaryTask ...
    
    // MARK: - Listener Management
    // Send a friend request by display name
    func sendFriendRequest(toDisplayName: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = userId else { return }

        let leaderboardRef = db.collection("leaderboard_entries")

        // First, fetch recipient UID by display name
        leaderboardRef.whereField("displayName", isEqualTo: toDisplayName)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(error)
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    completion(NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found."]))
                    return
                }

                let toUserId = doc.documentID

                // ✅ Now fetch the sender’s display name
                leaderboardRef.document(currentUserId).getDocument { senderSnapshot, err in
                    guard let senderData = senderSnapshot?.data(),
                          let senderDisplayName = senderData["displayName"] as? String else {
                        completion(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve your display name."]))
                        return
                    }

                    let friendRequest = [
                        "fromUserId": currentUserId,
                        "toUserId": toUserId,
                        "displayName": senderDisplayName, // ✅ Sender’s display name shown to recipient
                        "status": "pending",
                        "timestamp": FieldValue.serverTimestamp()
                    ] as [String : Any]

                    self.db.collection("users").document(toUserId)
                        .collection("friend_requests")
                        .addDocument(data: friendRequest) { error in
                            completion(error)
                        }
                }
            }
    }
    func declineFriendRequest(fromUserId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = userId else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"]))
            return
        }

        let requestQuery = db.collection("users").document(currentUserId)
            .collection("friend_requests")
            .whereField("fromUserId", isEqualTo: fromUserId)

        requestQuery.getDocuments { snapshot, error in
            guard let doc = snapshot?.documents.first else {
                completion(error ?? NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Request not found"]))
                return
            }

            doc.reference.delete(completion: completion)
        }
    }

    // Accept a friend request and establish friendship
    func acceptFriendRequest(fromUserId: String, displayName: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = userId else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let myRef = db.collection("users").document(currentUserId).collection("friends").document(fromUserId)
        let theirRef = db.collection("users").document(fromUserId).collection("friends").document(currentUserId)

        let requestQuery = db.collection("users").document(currentUserId)
            .collection("friend_requests")
            .whereField("fromUserId", isEqualTo: fromUserId)

        requestQuery.getDocuments { snapshot, error in
            guard let doc = snapshot?.documents.first else {
                completion(error ?? NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Friend request not found"]))
                return
            }

            let requestRef = doc.reference
            let leaderboardRef = self.db.collection("leaderboard_entries")

            // Fetch current user's display name
            leaderboardRef.document(currentUserId).getDocument { currentUserSnapshot, currentUserError in
                guard let currentUserData = currentUserSnapshot?.data(),
                      let currentUserDisplayName = currentUserData["displayName"] as? String else {
                    completion(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve your display name."]))
                    return
                }

                // ✅ Fetch sender's display name fresh
                leaderboardRef.document(fromUserId).getDocument { senderSnapshot, senderError in
                    guard let senderData = senderSnapshot?.data(),
                          let senderDisplayName = senderData["displayName"] as? String else {
                        completion(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Could not retrieve sender's display name."]))
                        return
                    }

                    let myFriendData: [String: Any] = [
                        "status": "accepted",
                        "displayName": senderDisplayName,
                        "timestamp": FieldValue.serverTimestamp()
                    ]

                    let theirFriendData: [String: Any] = [
                        "status": "accepted",
                        "displayName": currentUserDisplayName,
                        "timestamp": FieldValue.serverTimestamp()
                    ]

                    let batch = self.db.batch()
                    batch.setData(myFriendData, forDocument: myRef)
                    batch.setData(theirFriendData, forDocument: theirRef)
                    batch.deleteDocument(requestRef)

                    batch.commit(completion: completion)
                }
            }
        }
    }

    func startListeningToAcceptedFriendsLive(onUpdate: @escaping ([FriendEntry]) -> Void) {
            guard let currentUserId = userId else {
                onUpdate([])
                return
            }

            acceptedFriendsListener?.remove() // Clean up old listener if any

            acceptedFriendsListener = db.collection("users")
                .document(currentUserId)
                .collection("friends")
                .whereField("status", isEqualTo: "accepted")
                .addSnapshotListener { snapshot, error in
                    guard let documents = snapshot?.documents, error == nil else {
                        print("Error listening to friends:", error?.localizedDescription ?? "unknown")
                        onUpdate([])
                        return
                    }

                    let friendUIDs = documents.map { $0.documentID }
                    if friendUIDs.isEmpty {
                        onUpdate([])
                        return
                    }

                    // Fetch display names from leaderboard_entries
                    self.db.collection("leaderboard_entries")
                        .whereField(FieldPath.documentID(), in: friendUIDs)
                        .getDocuments { snap, err in
                            guard let docs = snap?.documents, err == nil else {
                                onUpdate([])
                                return
                            }

                            let friends = docs.compactMap { doc -> FriendEntry? in
                                guard let displayName = doc.data()["displayName"] as? String else { return nil }
                                return FriendEntry(userId: doc.documentID, displayName: displayName)
                            }

                            onUpdate(friends)
                        }
                }
        }

        func stopListeningToAcceptedFriends() {
            acceptedFriendsListener?.remove()
            acceptedFriendsListener = nil
        }

    // Fetch friend user IDs
    func fetchFriendUserIDs(completion: @escaping ([String]) -> Void) {
        guard let currentUserId = userId else {
            completion([])
            return
        }

        db.collection("users").document(currentUserId).collection("friends")
            .whereField("status", isEqualTo: "accepted")
            .getDocuments { snapshot, error in
                if let documents = snapshot?.documents {
                    let ids = documents.map { $0.documentID }
                    completion(ids)
                } else {
                    completion([])
                }
            }
    }
    // Fetch pending friend requests sent to current user
    func fetchPendingFriendRequests(completion: @escaping ([FriendRequest]) -> Void) {
        guard let currentUserId = userId else {
            completion([])
            return
        }

        db.collection("users").document(currentUserId)
            .collection("friend_requests")
            .whereField("status", isEqualTo: "pending")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, error == nil else {
                    completion([])
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

                completion(requests)
            }
    }

    // Fetch accepted friends of current user
    func fetchAcceptedFriends(completion: @escaping ([FriendEntry]) -> Void) {
        guard let currentUserId = userId else {
            completion([])
            return
        }

        let friendRef = db.collection("users").document(currentUserId).collection("friends")
        
        friendRef.whereField("status", isEqualTo: "accepted").getDocuments { snapshot, error in
            guard let documents = snapshot?.documents, error == nil else {
                completion([])
                return
            }

            let friendUIDs = documents.map { $0.documentID }
            if friendUIDs.isEmpty {
                completion([])
                return
            }

            // Fetch leaderboard entries in a single call using `.whereField(.in:)`
            self.db.collection("leaderboard_entries")
                .whereField(FieldPath.documentID(), in: friendUIDs)
                .getDocuments { snap, err in
                    guard let docs = snap?.documents, err == nil else {
                        completion([])
                        return
                    }

                    let friends: [FriendEntry] = docs.compactMap { doc in
                        let data = doc.data()
                        guard let displayName = data["displayName"] as? String else {
                            return nil
                        }
                        return FriendEntry(userId: doc.documentID, displayName: displayName)
                    }

                    completion(friends)
                }
        }
    }

    func fetchFriendDashboardStats(completion: @escaping ([FriendDashboardStats]) -> Void) {
        guard userId != nil else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        fetchAcceptedFriends { [weak self] friends in
            guard let self else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            guard !friends.isEmpty else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let group = DispatchGroup()
            let lock = NSLock()
            var statsCards: [FriendDashboardStats] = []

            for friend in friends {
                group.enter()
                self.db.collection("users")
                    .document(friend.userId)
                    .collection("playerData")
                    .document("playerStats")
                    .getDocument { snapshot, error in
                        defer { group.leave() }

                        let mapped: FriendDashboardStats
                        if let snapshot = snapshot,
                           snapshot.exists,
                           error == nil,
                           let playerStats = try? snapshot.data(as: PlayerStatsCodable.self) {
                            mapped = FriendDashboardStats(
                                userId: friend.userId,
                                displayName: friend.displayName,
                                yesterdayPoints: playerStats.lastDailyPointsEarned,
                                completedTasksYesterday: playerStats.lastDailyCompletedTasks,
                                totalTasksYesterday: playerStats.lastDailyTotalTasks,
                                taskStreak: playerStats.taskCompletionStreak,
                                lastEvaluated: playerStats.lastEvaluated
                            )
                        } else {
                            mapped = FriendDashboardStats(
                                userId: friend.userId,
                                displayName: friend.displayName,
                                yesterdayPoints: 0,
                                completedTasksYesterday: 0,
                                totalTasksYesterday: 0,
                                taskStreak: 0,
                                lastEvaluated: nil
                            )
                        }

                        lock.lock()
                        statsCards.append(mapped)
                        lock.unlock()
                    }
            }

            group.notify(queue: .main) {
                completion(statsCards)
            }
        }
    }

    // Remove a friend (unfriend)
    func removeFriend(friendUserId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = userId else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let myRef = db.collection("users").document(currentUserId).collection("friends").document(friendUserId)
        let theirRef = db.collection("users").document(friendUserId).collection("friends").document(currentUserId)

        let batch = db.batch()
        batch.deleteDocument(myRef)
        batch.deleteDocument(theirRef)

        batch.commit { error in
            if let error = error {
                print("Error removing friend: \(error.localizedDescription)")
            } else {
                print("Successfully removed friend relationship between \(currentUserId) and \(friendUserId)")
            }
            completion(error)
        }
    }
    // Send a message
    func sendChatMessage(_ message: ChatMessage, completion: @escaping (Error?) -> Void) {
        do {
            try db.collection("chat_messages").addDocument(from: message, completion: completion)
        } catch {
            completion(error)
        }
    }

    // Listen for messages between two users
    func listenToChat(with friendId: String, onUpdate: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }

        return db.collection("chat_messages")
            .whereFilter(Filter.orFilter([
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: currentUserId),
                    Filter.whereField("receiverId", isEqualTo: friendId)
                ]),
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: friendId),
                    Filter.whereField("receiverId", isEqualTo: currentUserId)
                ])
            ]))
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                let messages = documents.compactMap { try? $0.data(as: ChatMessage.self) }
                onUpdate(messages)
            }
    }
    func fetchLastMessage(with friendId: String, completion: @escaping (ChatMessage?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(nil)
            return
        }

        db.collection("chat_messages")
            .whereFilter(Filter.orFilter([
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: currentUserId),
                    Filter.whereField("receiverId", isEqualTo: friendId)
                ]),
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: friendId),
                    Filter.whereField("receiverId", isEqualTo: currentUserId)
                ])
            ]))
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                let msg = snapshot?.documents.first.flatMap { try? $0.data(as: ChatMessage.self) }
                completion(msg)
            }
    }

    /// Fetches the display name for a friend from the current user's friends subcollection.
    func fetchDisplayNameForFriend(userId: String, completion: @escaping (String?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(nil)
            return
        }
        db.collection("users").document(currentUserId).collection("friends").document(userId)
            .getDocument { snapshot, _ in
                guard let data = snapshot?.data(),
                      let displayName = data["displayName"] as? String else {
                    completion(nil)
                    return
                }
                completion(displayName)
            }
    }

    /// Listens for new chat messages where the current user is the receiver. Calls onNewMessage for each new message with the message and sender's display name. Skips the initial snapshot so existing messages do not trigger notifications.
    func listenToIncomingChatMessages(onNewMessage: @escaping (ChatMessage, String) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }

        var hasSeenInitialSnapshot = false
        return db.collection("chat_messages")
            .whereField("receiverId", isEqualTo: currentUserId)
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self,
                      let snapshot = snapshot,
                      error == nil else { return }

                if !hasSeenInitialSnapshot {
                    hasSeenInitialSnapshot = true
                    return
                }

                for change in snapshot.documentChanges {
                    guard change.type == .added else { continue }
                    guard let message = try? change.document.data(as: ChatMessage.self) else { continue }

                    self.fetchDisplayNameForFriend(userId: message.senderId) { displayName in
                        let name = displayName ?? "Someone"
                        DispatchQueue.main.async {
                            onNewMessage(message, name)
                        }
                    }
                }
            }
    }

    func fetchLastLoginDate(for userId: String, completion: @escaping (Date?) -> Void) {
        db.collection("users")
          .document(userId)
          .collection("playerData")
          .document("playerStats")
          .getDocument { snapshot, error in
              if let doc = snapshot, doc.exists {
                  do {
                      let stats = try doc.data(as: PlayerStatsCodable.self)
//                      print("📆 [DEBUG] Last login for \(userId): \(String(describing: stats.lastLoginDate))")
                      completion(stats.lastLoginDate)
                  } catch {
//                      print("❌ [ERROR] Failed to decode PlayerStatsCodable for \(userId): \(error)")
                      completion(nil)
                  }
              } else {
//                  print("⚠️ [WARNING] No playerStats document found for \(userId)")
                  completion(nil)
              }
          }
    }

    // MARK: - Shared Tasks

    func sendSharedTask(to receiverId: String, title: String, detail: String, dueDate: Date, subtasks: [SharedSubtask] = [], completion: @escaping (Error?, String?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }
        let docRef = db.collection("shared_tasks").document()
        let payload: [String: Any] = [
            "senderId": currentUserId,
            "receiverId": receiverId,
            "title": title,
            "detail": detail,
            "dueDate": Timestamp(date: dueDate),
            "isAccepted": false,
            "isCompleted": false,
            "createdAt": FieldValue.serverTimestamp(),
            "completedAt": NSNull(),
            "isProgressShare": false, // Regular task assignment
            "subtasks": subtasks.map { [
                "id": $0.id,
                "title": $0.title,
                "isDone": $0.isDone
            ] }
        ]
        docRef.setData(payload) { error in
            if error == nil {
                // Placeholder push code
                print("[PlaceholderPush] Sent shared task notification to userId=\(receiverId) title=\(title)")
            }
            completion(error, docRef.documentID)
        }
    }

    func updateSharedSubtasks(sharedTaskId: String, subtasks: [SharedSubtask], completion: @escaping (Error?) -> Void) {
        let serializable = subtasks.map { [
            "id": $0.id,
            "title": $0.title,
            "isDone": $0.isDone
        ] }
        db.collection("shared_tasks").document(sharedTaskId).updateData([
            "subtasks": serializable
        ], completion: completion)
    }

    func listenToSharedTasks(with friendId: String, onUpdate: @escaping ([SharedTask]) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("shared_tasks")
            .whereFilter(Filter.orFilter([
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: currentUserId),
                    Filter.whereField("receiverId", isEqualTo: friendId)
                ]),
                Filter.andFilter([
                    Filter.whereField("senderId", isEqualTo: friendId),
                    Filter.whereField("receiverId", isEqualTo: currentUserId)
                ])
            ]))
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    if let error = error { print("listenToSharedTasks error: \(error.localizedDescription)") }
                    onUpdate([])
                    return
                }
                var tasks = documents.compactMap { try? $0.data(as: SharedTask.self) }
                tasks.sort { $0.createdAt < $1.createdAt }
                onUpdate(tasks)
            }
    }

    func listenToSharedTask(taskId: String, onUpdate: @escaping (SharedTask?) -> Void) -> ListenerRegistration {
        return db.collection("shared_tasks").document(taskId)
            .addSnapshotListener { snapshot, error in
                guard let doc = snapshot, doc.exists else {
                    onUpdate(nil)
                    return
                }
                let task = try? doc.data(as: SharedTask.self)
                onUpdate(task)
            }
    }

    func acceptSharedTask(_ task: SharedTask, completion: @escaping (Error?) -> Void) {
        guard let taskId = task.id else {
            completion(NSError(domain: "", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing shared task id"]))
            return
        }
        db.collection("shared_tasks").document(taskId).updateData([
            "isAccepted": true
        ]) { error in
            completion(error)
        }
    }

    func updateSharedTaskProgress(sharedTaskId: String, isCompleted: Bool, completion: @escaping (Error?) -> Void) {
        var data: [String: Any] = [
            "isCompleted": isCompleted
        ]
        if isCompleted {
            data["completedAt"] = FieldValue.serverTimestamp()
        } else {
            data["completedAt"] = NSNull()
        }
        db.collection("shared_tasks").document(sharedTaskId).updateData(data) { error in
            completion(error)
        }
    }

    func nudgeSharedTask(sharedTaskId: String, to receiverId: String, message: String? = nil, completion: @escaping (Error?) -> Void) {
        // Placeholder push notification: In production, trigger FCM push to receiverId about this sharedTaskId
        // This might call a HTTPS endpoint or rely on a Cloud Function.
        print("[PlaceholderPush] Nudge sent for sharedTaskId=\(sharedTaskId) to userId=\(receiverId) message=\(message ?? "")")
        completion(nil)
    }

    func rejectSharedTask(sharedTaskId: String, completion: @escaping (Error?) -> Void) {
        db.collection("shared_tasks").document(sharedTaskId).updateData([
            "isAccepted": false,
            "isCompleted": false,
            "completedAt": NSNull()
        ]) { error in
            completion(error)
        }
    }

    func deleteSharedTask(sharedTaskId: String, completion: @escaping (Error?) -> Void) {
        db.collection("shared_tasks").document(sharedTaskId).delete(completion: completion)
    }
    
    // Mark shared task as rejected/discarded (softer than delete, preserves history)
    func markSharedTaskDiscarded(sharedTaskId: String, completion: @escaping (Error?) -> Void) {
        db.collection("shared_tasks").document(sharedTaskId).updateData([
            "isAccepted": false,
            "isCompleted": false
        ]) { error in
            completion(error)
        }
    }
    
    // Sync local task changes to Firebase SharedTask
    func syncLocalTaskToSharedTask(localTask: TodoItem, completion: @escaping (Error?) -> Void) {
        guard let sharedId = localTask.sharedTaskId else {
            completion(nil) // Not a shared task, nothing to sync
            return
        }
        
        let sharedSubtasks = localTask.subtasks.map { SharedSubtask(id: UUID().uuidString, title: $0.title, isDone: $0.isDone) }
        
        var data: [String: Any] = [
            "title": localTask.title,
            "detail": localTask.detail,
            "dueDate": Timestamp(date: localTask.dueDate),
            "isCompleted": localTask.isDone,
            "subtasks": sharedSubtasks.map { [
                "id": $0.id,
                "title": $0.title,
                "isDone": $0.isDone
            ] }
        ]
        
        if localTask.isDone {
            data["completedAt"] = Timestamp(date: localTask.completedAt ?? Date())
        } else {
            data["completedAt"] = NSNull()
        }
        
        db.collection("shared_tasks").document(sharedId).updateData(data) { error in
            if let error = error {
                print("Failed to sync local task '\(localTask.title)' to Firebase: \(error.localizedDescription)")
            } else {
                print("✅ Synced local task '\(localTask.title)' to Firebase SharedTask")
            }
            completion(error)
        }
    }
    
    // Share progress of an already completed/in-progress task
    func shareProgress(to receiverId: String, title: String, detail: String, dueDate: Date, subtasks: [SharedSubtask] = [], isCompleted: Bool, completion: @escaping (Error?, String?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }
        let docRef = db.collection("shared_tasks").document()
        let payload: [String: Any] = [
            "senderId": currentUserId,
            "receiverId": receiverId,
            "title": title,
            "detail": detail,
            "dueDate": Timestamp(date: dueDate),
            "isAccepted": true, // Progress shares are automatically accepted
            "isCompleted": isCompleted,
            "createdAt": FieldValue.serverTimestamp(),
            "completedAt": isCompleted ? FieldValue.serverTimestamp() : NSNull(),
            "isProgressShare": true, // This is a progress share
            "subtasks": subtasks.map { [
                "id": $0.id,
                "title": $0.title,
                "isDone": $0.isDone
            ] }
        ]
        docRef.setData(payload) { error in
            if error == nil {
                print("[Progress] Shared progress to userId=\(receiverId) title=\(title) completed=\(isCompleted)")
            }
            completion(error, docRef.documentID)
        }
    }

    // MARK: - Task Proof Feed

    func createTaskProofPost(
        taskTitle: String,
        sourceType: TaskProofSourceType,
        scheduledEventId: String?,
        localTaskId: String?,
        sharedTaskId: String?,
        completedAt: Date,
        imageData: Data,
        completion: @escaping (Error?, String?) -> Void
    ) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }

        let postRef = db.collection("task_proof_posts").document()
        let postId = postRef.documentID
        let storagePath = "taskProofPhotos/\(currentUserId)/\(postId).jpg"
        let storageRef = Storage.storage().reference(withPath: storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        storageRef.putData(imageData, metadata: metadata) { [weak self] _, uploadError in
            guard let self = self else { return }
            if let uploadError = uploadError {
                completion(uploadError, nil)
                return
            }

            storageRef.downloadURL { url, urlError in
                if let urlError = urlError {
                    completion(urlError, nil)
                    return
                }
                guard let downloadURL = url?.absoluteString else {
                    completion(NSError(domain: "", code: 500, userInfo: [NSLocalizedDescriptionKey: "Could not generate photo URL"]), nil)
                    return
                }

                let payload: [String: Any] = [
                    "authorId": currentUserId,
                    "authorDisplayName": Auth.auth().currentUser?.displayName ?? "Anonymous Gardener",
                    "taskTitle": taskTitle,
                    "sourceType": sourceType.rawValue,
                    "scheduledEventId": scheduledEventId ?? NSNull(),
                    "localTaskId": localTaskId ?? NSNull(),
                    "sharedTaskId": sharedTaskId ?? NSNull(),
                    "completedAt": Timestamp(date: completedAt),
                    "createdAt": FieldValue.serverTimestamp(),
                    "photoURL": downloadURL,
                    "photoStoragePath": storagePath
                ]

                postRef.setData(payload) { error in
                    completion(error, error == nil ? postId : nil)
                }
            }
        }
    }

    func deleteTaskProofPost(postId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let postRef = db.collection("task_proof_posts").document(postId)
        postRef.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                completion(error)
                return
            }
            guard let snapshot = snapshot, snapshot.exists else {
                completion(nil)
                return
            }

            let data = snapshot.data() ?? [:]
            let authorId = data["authorId"] as? String
            guard authorId == currentUserId else {
                completion(NSError(domain: "", code: 403, userInfo: [NSLocalizedDescriptionKey: "Only the author can delete this post"]))
                return
            }
            let storagePath = data["photoStoragePath"] as? String

            postRef.collection("votes").getDocuments { voteSnapshot, voteError in
                if let voteError = voteError {
                    completion(voteError)
                    return
                }

                let batch = self.db.batch()
                voteSnapshot?.documents.forEach { batch.deleteDocument($0.reference) }
                batch.deleteDocument(postRef)

                batch.commit { batchError in
                    if let batchError = batchError {
                        completion(batchError)
                        return
                    }

                    guard let storagePath = storagePath, !storagePath.isEmpty else {
                        completion(nil)
                        return
                    }

                    Storage.storage().reference(withPath: storagePath).delete { storageError in
                        if let nsError = storageError as NSError?,
                           nsError.domain == StorageErrorDomain,
                           nsError.code == StorageErrorCode.objectNotFound.rawValue {
                            completion(nil)
                            return
                        }
                        completion(storageError)
                    }
                }
            }
        }
    }

    /// Fetches yesterday-window proof posts; per post, if non-self votes satisfy checks > xs, links that task for 1.5× XP and lists the post for deletion.
    /// On error or no auth, returns empty sets.
    func fetchYesterdayTaskProofTallyForPoints(evaluationDate: Date = Date(), completion: @escaping (YesterdayTaskProofTallyResult) -> Void) {
        let empty = YesterdayTaskProofTallyResult(
            eligibleLocalTaskIds: Set(),
            eligibleSharedTaskIds: Set(),
            qualifyingPostIds: [],
            proofVoteRollupsByLocalTaskId: [:],
            proofVoteRollupsBySharedTaskId: [:]
        )

        guard let uid = Auth.auth().currentUser?.uid else {
            print("[DailyEval] proof tally: skip (no signed-in user)")
            completion(empty)
            return
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: evaluationDate)
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) else {
            print("[DailyEval] proof tally: skip (could not compute yesterday)")
            completion(empty)
            return
        }

        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "yyyy-MM-dd"
        print("[DailyEval] proof tally: querying posts with createdAt in [\(dayFmt.string(from: yesterdayStart)), \(dayFmt.string(from: todayStart))) authorId=\(uid)")

        let startTs = Timestamp(date: yesterdayStart)
        let endTs = Timestamp(date: todayStart)

        db.collection("task_proof_posts")
            .whereField("authorId", isEqualTo: uid)
            .whereField("createdAt", isGreaterThanOrEqualTo: startTs)
            .whereField("createdAt", isLessThan: endTs)
            .limit(to: 50)
            .getDocuments { [weak self] snapshot, error in
                guard self != nil else {
                    print("[DailyEval] proof tally: aborted (FirebaseManager deallocated)")
                    completion(empty)
                    return
                }
                if let error {
                    print("[DailyEval] proof tally: Firestore query failed — \(error.localizedDescription)")
                    completion(empty)
                    return
                }

                let docs = snapshot?.documents ?? []
                if docs.isEmpty {
                    print("[DailyEval] proof tally: 0 posts in window → no per-task bonus, no deletions")
                    completion(empty)
                    return
                }

                let postIds = docs.map(\.documentID)
                print("[DailyEval] proof tally: found \(docs.count) post(s) ids=\(postIds.joined(separator: ", ")) — fetching votes per post")

                var eligibleLocalTaskIds = Set<String>()
                var eligibleSharedTaskIds = Set<String>()
                var qualifyingPostIds: [String] = []
                var rollupsLocal: [String: (checks: Int, xs: Int)] = [:]
                var rollupsShared: [String: (checks: Int, xs: Int)] = [:]
                let tallyLock = NSLock()
                let group = DispatchGroup()

                for doc in docs {
                    group.enter()
                    let postId = doc.documentID
                    let postOptional = try? doc.data(as: TaskProofPost.self)

                    doc.reference.collection("votes").getDocuments { voteSnapshot, voteError in
                        defer { group.leave() }
                        if let voteError {
                            print("[DailyEval] proof tally: votes read failed for post \(postId) — \(voteError.localizedDescription)")
                            return
                        }
                        guard let post = postOptional else {
                            print("[DailyEval] proof tally: post \(postId) skipped — TaskProofPost decode failed")
                            return
                        }

                        let votes = voteSnapshot?.documents.compactMap { try? $0.data(as: TaskProofVote.self) } ?? []
                        var allChecks = 0
                        var allXs = 0
                        var nonSelfChecks = 0
                        var nonSelfXs = 0
                        var sawNonSelf = false
                        for vote in votes {
                            switch vote.voteType {
                            case .check: allChecks += 1
                            case .xmark: allXs += 1
                            }
                            if vote.voterId != uid {
                                sawNonSelf = true
                                switch vote.voteType {
                                case .check: nonSelfChecks += 1
                                case .xmark: nonSelfXs += 1
                                }
                            }
                        }
                        let postEligible = sawNonSelf && nonSelfChecks > nonSelfXs
                        print("[DailyEval] proof tally: post \(postId) rawVotes=\(votes.count) allChecks=\(allChecks) allXs=\(allXs) nonSelfChecks=\(nonSelfChecks) nonSelfXs=\(nonSelfXs) perPostEligible=\(postEligible)")

                        let linkLocal = post.localTaskId.flatMap { $0.isEmpty ? nil : $0 }
                        let linkShared = post.sharedTaskId.flatMap { $0.isEmpty ? nil : $0 }

                        tallyLock.lock()
                        if let lid = linkLocal {
                            let cur = rollupsLocal[lid] ?? (0, 0)
                            rollupsLocal[lid] = (cur.checks + allChecks, cur.xs + allXs)
                            if postEligible {
                                qualifyingPostIds.append(postId)
                                eligibleLocalTaskIds.insert(lid)
                            }
                        } else if let sid = linkShared {
                            let cur = rollupsShared[sid] ?? (0, 0)
                            rollupsShared[sid] = (cur.checks + allChecks, cur.xs + allXs)
                            if postEligible {
                                qualifyingPostIds.append(postId)
                                eligibleSharedTaskIds.insert(sid)
                            }
                        } else if postEligible {
                            print("[DailyEval] proof tally: post \(postId) vote-eligible but no localTaskId/sharedTaskId (e.g. scheduled journal) — no XP bonus and no auto-delete")
                        }
                        tallyLock.unlock()
                    }
                }

                group.notify(queue: .main) {
                    let mapLocal: [String: ProofFeedVoteRollup] = rollupsLocal.mapValues { ProofFeedVoteRollup(allCheckVotes: $0.checks, allXVotes: $0.xs) }
                    let mapShared: [String: ProofFeedVoteRollup] = rollupsShared.mapValues { ProofFeedVoteRollup(allCheckVotes: $0.checks, allXVotes: $0.xs) }
                    print("[DailyEval] proof tally: done eligibleLocal=\(eligibleLocalTaskIds.sorted()) eligibleShared=\(eligibleSharedTaskIds.sorted()) qualifyingPosts=\(qualifyingPostIds.count) rollupLocalKeys=\(mapLocal.keys.count) rollupSharedKeys=\(mapShared.keys.count)")
                    completion(YesterdayTaskProofTallyResult(
                        eligibleLocalTaskIds: eligibleLocalTaskIds,
                        eligibleSharedTaskIds: eligibleSharedTaskIds,
                        qualifyingPostIds: qualifyingPostIds,
                        proofVoteRollupsByLocalTaskId: mapLocal,
                        proofVoteRollupsBySharedTaskId: mapShared
                    ))
                }
            }
    }

    func fetchAcceptedFriendsWithSince(completion: @escaping ([FriendWithSince]) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion([])
            return
        }

        db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .whereField("status", isEqualTo: "accepted")
            .getDocuments { snapshot, _ in
                let docs = snapshot?.documents ?? []
                let entries: [FriendWithSince] = docs.map { doc in
                    let rawTimestamp = doc.data()["timestamp"]
                    let since: Date
                    if let timestamp = rawTimestamp as? Timestamp {
                        since = timestamp.dateValue()
                    } else if let date = rawTimestamp as? Date {
                        since = date
                    } else {
                        since = Date()
                    }
                    return FriendWithSince(userId: doc.documentID, since: since)
                }
                completion(entries)
            }
    }

    func listenToTaskProofFeed(onUpdate: @escaping ([TaskProofPost]) -> Void) -> TaskProofFeedListenerToken? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }

        let token = TaskProofFeedListenerToken()

        func emitMergedFeed() {
            var uniqueById: [String: TaskProofPost] = [:]
            for posts in token.authorPosts.values {
                for post in posts {
                    guard let id = post.id else { continue }
                    uniqueById[id] = post
                }
            }

            let filtered: [TaskProofPost] = uniqueById.values.filter { post in
                if post.authorId == currentUserId {
                    return true
                }
                guard let friendshipStart = token.friendSinceMap[post.authorId] else {
                    return false
                }
                return post.createdAt >= friendshipStart
            }
            .sorted { $0.createdAt > $1.createdAt }

            onUpdate(filtered)
        }

        func rebuildPostListeners() {
            token.postListeners.values.forEach { $0.remove() }
            token.postListeners.removeAll()
            token.authorPosts.removeAll()

            var authorIds = Set(token.friendSinceMap.keys)
            authorIds.insert(currentUserId)

            if authorIds.isEmpty {
                onUpdate([])
                return
            }

            for authorId in authorIds {
                let listener = db.collection("task_proof_posts")
                    .whereField("authorId", isEqualTo: authorId)
                    .order(by: "createdAt", descending: true)
                    .limit(to: 200)
                    .addSnapshotListener { snapshot, error in
                        if let error = error {
                            let nsError = error as NSError
                            if nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                                print("listenToTaskProofFeed permission denied for authorId \(authorId)")
                            } else {
                                print("listenToTaskProofFeed error for authorId \(authorId): \(error.localizedDescription)")
                            }
                            token.authorPosts[authorId] = []
                            token.postListeners[authorId]?.remove()
                            token.postListeners.removeValue(forKey: authorId)
                            emitMergedFeed()
                            return
                        }
                        let posts = snapshot?.documents.compactMap { try? $0.data(as: TaskProofPost.self) } ?? []
                        token.authorPosts[authorId] = posts
                        emitMergedFeed()
                    }
                token.postListeners[authorId] = listener
            }
        }

        token.friendsListener = db.collection("users")
            .document(currentUserId)
            .collection("friends")
            .whereField("status", isEqualTo: "accepted")
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("listenToTaskProofFeed friends listener error: \(error.localizedDescription)")
                    token.friendSinceMap = [:]
                    rebuildPostListeners()
                    return
                }
                let docs = snapshot?.documents ?? []
                var friendSince: [String: Date] = [:]
                docs.forEach { doc in
                    let rawTimestamp = doc.data()["timestamp"]
                    if let timestamp = rawTimestamp as? Timestamp {
                        friendSince[doc.documentID] = timestamp.dateValue()
                    } else if let date = rawTimestamp as? Date {
                        friendSince[doc.documentID] = date
                    } else {
                        friendSince[doc.documentID] = Date()
                    }
                }
                token.friendSinceMap = friendSince
                rebuildPostListeners()
            }

        return token
    }

    func listenToTaskProofVotes(postId: String, onUpdate: @escaping ([TaskProofVote]) -> Void) -> ListenerRegistration {
        db.collection("task_proof_posts")
            .document(postId)
            .collection("votes")
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, _ in
                let votes = snapshot?.documents.compactMap { try? $0.data(as: TaskProofVote.self) } ?? []
                onUpdate(votes)
            }
    }

    func setTaskProofVote(postId: String, voteType: TaskProofVoteType, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let voteRef = db.collection("task_proof_posts")
            .document(postId)
            .collection("votes")
            .document(currentUserId)

        let payload: [String: Any] = [
            "voterId": currentUserId,
            "voterDisplayName": Auth.auth().currentUser?.displayName ?? "Friend",
            "voteType": voteType.rawValue,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        voteRef.setData(payload, merge: true, completion: completion)
    }

    func removeAllListeners() {
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        print("All Firestore listeners removed.")
    }
    
    // MARK: - Backlog Items
    
    func saveBacklogItem(_ item: BacklogItem, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let docRef = db.collection("users").document(userId).collection("backlog").document()
        do {
            let itemToSave = item
            if item.id == nil {
                // Create a new item
                try docRef.setData(from: itemToSave) { error in
                    completion(error)
                }
            } else {
                // Update existing item
                try db.collection("users").document(userId).collection("backlog").document(item.id!).setData(from: itemToSave) { error in
                    completion(error)
                }
            }
        } catch {
            completion(error)
        }
    }
    
    func fetchBacklogItems(completion: @escaping ([BacklogItem]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("backlog")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let items = snapshot?.documents.compactMap { doc -> BacklogItem? in
                    try? doc.data(as: BacklogItem.self)
                } ?? []
                
                completion(items, nil)
            }
    }
    
    func deleteBacklogItem(_ itemId: String, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("backlog").document(itemId).delete(completion: completion)
    }
    
    // MARK: - Schedule Preferences
    
    func saveSchedulePreference(_ preference: UserSchedulePreference, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Ensure userId is set in the preference (in case it's missing)
        var preferenceToSave = preference
        // Note: UserSchedulePreference has userId as a let property, so we need to create a new instance
        // But since we're using setData(from:), it will encode all fields including userId
        // However, if userId is different, we should use the one from the preference parameter
        // For safety, we'll use setData with merge to ensure userId is always present
        let docRef = db.collection("users").document(userId).collection("schedulePreferences").document("preferences")
        
        do {
            // Encode the preference to a dictionary
            let encoder = Firestore.Encoder()
            var preferenceDict = try encoder.encode(preference)
            
            // Explicitly ensure userId is set
            preferenceDict["userId"] = userId
            
            print("🧠 [AGENT MEMORY DEBUG] 💾 Saving schedule preference with userId: \(userId)")
            
            // Use setData with merge: false to replace the document, ensuring userId is included
            docRef.setData(preferenceDict, merge: false) { error in
                if let error = error {
                    print("🧠 [AGENT MEMORY DEBUG] ❌ Error saving schedule preference: \(error.localizedDescription)")
                } else {
                    print("🧠 [AGENT MEMORY DEBUG] ✅ Successfully saved schedule preference with userId")
                }
                completion(error)
            }
        } catch {
            print("🧠 [AGENT MEMORY DEBUG] ❌ Error encoding schedule preference: \(error.localizedDescription)")
            completion(error)
        }
    }
    
    func fetchSchedulePreference(completion: @escaping (UserSchedulePreference?, Error?) -> Void) {
        guard let userId = userId else {
            print("🧠 [AGENT MEMORY DEBUG] ❌ User not authenticated - cannot fetch schedule preference")
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        print("🧠 [AGENT MEMORY DEBUG] 🔍 Fetching agent memories from Firebase for userId: \(userId)")
        print("🧠 [AGENT MEMORY DEBUG] 📍 Path: users/\(userId)/schedulePreferences/preferences")
        
        db.collection("users").document(userId).collection("schedulePreferences").document("preferences")
            .getDocument { document, error in
                if let error = error {
                    print("🧠 [AGENT MEMORY DEBUG] ❌ Error fetching schedule preference: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }
                
                if let document = document, document.exists {
                    print("🧠 [AGENT MEMORY DEBUG] ✅ Document exists - attempting to decode UserSchedulePreference")
                    
                    // Log raw document data for debugging
                    guard let data = document.data() else {
                        print("🧠 [AGENT MEMORY DEBUG] ⚠️ Document exists but has no data() - creating default preference")
                        let defaultPreference = UserSchedulePreference(userId: userId)
                        completion(defaultPreference, nil)
                        return
                    }
                    
                    print("🧠 [AGENT MEMORY DEBUG] 📄 Raw document data keys: \(data.keys.sorted())")
                    print("🧠 [AGENT MEMORY DEBUG] 📄 Document data count: \(data.count) fields")
                    
                    // Check for required userId field
                    let hasUserId = data["userId"] != nil
                    if hasUserId, let docUserId = data["userId"] as? String {
                        print("🧠 [AGENT MEMORY DEBUG] ✅ userId found in document: \(docUserId)")
                    } else {
                        print("🧠 [AGENT MEMORY DEBUG] ⚠️ userId MISSING in document data - will inject during decode")
                    }
                    
                    // Log some key fields for debugging
                    if let dayMemories = data["dayOfWeekMemories"] {
                        print("🧠 [AGENT MEMORY DEBUG] 📄 dayOfWeekMemories type: \(type(of: dayMemories))")
                    }
                    if let constraints = data["scheduleConstraints"] {
                        print("🧠 [AGENT MEMORY DEBUG] 📄 scheduleConstraints type: \(type(of: constraints))")
                    }
                    if let stats = data["acceptanceStats"] {
                        print("🧠 [AGENT MEMORY DEBUG] 📄 acceptanceStats type: \(type(of: stats))")
                    }
                    
                    do {
                        var preference: UserSchedulePreference
                        
                        // Try to decode normally first
                        if hasUserId {
                            preference = try document.data(as: UserSchedulePreference.self)
                        } else {
                            // If userId is missing, manually decode fields and construct the object
                            print("🧠 [AGENT MEMORY DEBUG] 🔧 Manually decoding fields due to missing userId")
                            
                            // Helper function to decode nested Firestore data
                            func decodeField<T: Decodable>(_ field: Any?, as type: T.Type) -> T? {
                                guard let field = field else { return nil }
                                // Convert to JSON data for decoding
                                guard let jsonData = try? JSONSerialization.data(withJSONObject: field) else { return nil }
                                return try? JSONDecoder().decode(type, from: jsonData)
                            }
                            
                            // Decode nested structures
                            let dayOfWeekMemories: [String: [String]]? = decodeField(data["dayOfWeekMemories"], as: [String: [String]].self)
                            let learnedPatterns: [String: String]? = decodeField(data["learnedPatterns"], as: [String: String].self)
                            let scheduleConstraints: [ScheduleConstraint] = decodeField(data["scheduleConstraints"], as: [ScheduleConstraint].self) ?? []
                            let recurringCommitments: [RecurringCommitment] = decodeField(data["recurringCommitments"], as: [RecurringCommitment].self) ?? []
                            let dayContexts: [String: DayContext]? = decodeField(data["dayContexts"], as: [String: DayContext].self)
                            let acceptanceStats: AcceptanceStats? = decodeField(data["acceptanceStats"], as: AcceptanceStats.self)
                            
                            // Construct preference with injected userId
                            preference = UserSchedulePreference(
                                id: document.documentID,
                                userId: userId,
                                preferredWakeTime: data["preferredWakeTime"] as? String,
                                lunchTime: data["lunchTime"] as? String,
                                preferredWorkTimes: data["preferredWorkTimes"] as? [String],
                                blockedTimes: data["blockedTimes"] as? [String],
                                learnedPatterns: learnedPatterns,
                                dayOfWeekMemories: dayOfWeekMemories,
                                scheduleConstraints: scheduleConstraints,
                                recurringCommitments: recurringCommitments,
                                dayContexts: dayContexts,
                                acceptanceStats: acceptanceStats
                            )
                            
                            print("🧠 [AGENT MEMORY DEBUG] ✅ Successfully decoded schedule preference with injected userId")
                            
                            // Update the document in Firebase to include userId for future fetches
                            print("🧠 [AGENT MEMORY DEBUG] 💾 Updating document to include userId for future fetches")
                            let docRef = self.db.collection("users").document(userId).collection("schedulePreferences").document("preferences")
                            docRef.updateData(["userId": userId]) { error in
                                if let error = error {
                                    print("🧠 [AGENT MEMORY DEBUG] ⚠️ Failed to update document with userId: \(error.localizedDescription)")
                                } else {
                                    print("🧠 [AGENT MEMORY DEBUG] ✅ Successfully updated document with userId")
                                }
                            }
                        }
                        
                        print("🧠 [AGENT MEMORY DEBUG] ✅ Successfully decoded schedule preference")
                        print("🧠 [AGENT MEMORY DEBUG] 📊 Preference details:")
                        print("   - Day of week memories: \(preference.dayOfWeekMemories?.count ?? 0) days")
                        print("   - Schedule constraints: \(preference.scheduleConstraints.count)")
                        print("   - Learned patterns: \(preference.learnedPatterns?.count ?? 0)")
                        if let stats = preference.acceptanceStats {
                            print("   - Acceptance stats: \(stats.totalAccepted) accepted, \(stats.totalDeclined) declined, \(stats.totalModified) modified")
                        }
                        completion(preference, nil)
                    } catch {
                        print("🧠 [AGENT MEMORY DEBUG] ⚠️ Failed to decode schedule preference: \(error.localizedDescription)")
                        if let decodingError = error as? DecodingError {
                            switch decodingError {
                            case .keyNotFound(let key, let context):
                                print("🧠 [AGENT MEMORY DEBUG] 🔑 Missing key: \(key.stringValue) - \(context.debugDescription)")
                            case .typeMismatch(let type, let context):
                                print("🧠 [AGENT MEMORY DEBUG] 🔄 Type mismatch: expected \(type), found \(context.debugDescription)")
                            case .valueNotFound(let type, let context):
                                print("🧠 [AGENT MEMORY DEBUG] 📭 Value not found: \(type) - \(context.debugDescription)")
                            case .dataCorrupted(let context):
                                print("🧠 [AGENT MEMORY DEBUG] 💥 Data corrupted: \(context.debugDescription)")
                            @unknown default:
                                print("🧠 [AGENT MEMORY DEBUG] ❓ Unknown decoding error: \(decodingError)")
                            }
                        }
                        print("🧠 [AGENT MEMORY DEBUG] 🔄 Creating default preference due to decode failure")
                        // Create default preference if decoding fails
                        let defaultPreference = UserSchedulePreference(userId: userId)
                        completion(defaultPreference, nil)
                    }
                } else {
                    print("🧠 [AGENT MEMORY DEBUG] ⚠️ Document does not exist - creating default preference")
                    // Create default preference if doesn't exist
                    let defaultPreference = UserSchedulePreference(userId: userId)
                    completion(defaultPreference, nil)
                }
            }
    }
    
    func updateSchedulePreference(_ updates: [String: Any], completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Ensure userId is always included in updates
        var updatesWithUserId = updates
        updatesWithUserId["userId"] = userId
        
        let docRef = db.collection("users").document(userId).collection("schedulePreferences").document("preferences")
        
        print("🧠 [AGENT MEMORY DEBUG] 💾 Updating schedule preference with userId: \(userId)")
        
        // Use setData with merge: true to create document if it doesn't exist, or update if it does
        docRef.setData(updatesWithUserId, merge: true) { error in
            if let error = error {
                print("🧠 [AGENT MEMORY DEBUG] ❌ Error updating schedule preference: \(error.localizedDescription)")
            } else {
                print("🧠 [AGENT MEMORY DEBUG] ✅ Successfully updated schedule preference with userId")
            }
            completion(error)
        }
    }
    
    // MARK: - Scheduling Messages
    
    func saveSchedulingMessage(_ message: SchedulingMessage, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let docRef = db.collection("users").document(userId).collection("schedulingMessages").document()
        do {
            try docRef.setData(from: message) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    func fetchSchedulingHistory(limit: Int = 50, completion: @escaping ([SchedulingMessage]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("schedulingMessages")
            .order(by: "timestamp", descending: false)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                let messages = snapshot?.documents.compactMap { doc -> SchedulingMessage? in
                    try? doc.data(as: SchedulingMessage.self)
                } ?? []

                completion(messages, nil)
            }
    }

    // MARK: - Day Contexts

    func saveDayContext(_ dayContext: DayContext, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let docRef = db.collection("users").document(userId).collection("dayContexts").document(dayContext.dayOfWeek.lowercased())
        do {
            try docRef.setData(from: dayContext) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func fetchDayContexts(completion: @escaping ([String: DayContext]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("dayContexts")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                var contexts: [String: DayContext] = [:]
                for doc in snapshot?.documents ?? [] {
                    if let context = try? doc.data(as: DayContext.self) {
                        contexts[doc.documentID] = context
                    }
                }
                completion(contexts, nil)
            }
    }

    func fetchDayContext(for dayOfWeek: String, completion: @escaping (DayContext?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("dayContexts").document(dayOfWeek.lowercased())
            .getDocument { document, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                if let document = document, document.exists {
                    let context = try? document.data(as: DayContext.self)
                    completion(context, nil)
                } else {
                    completion(nil, nil)
                }
            }
    }

    // MARK: - Schedule Notes

    func saveScheduleNote(_ note: ScheduleNote, completion: @escaping (Error?, String?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }

        let docRef = db.collection("users").document(userId).collection("scheduleNotes").document()
        do {
            try docRef.setData(from: note) { error in
                completion(error, docRef.documentID)
            }
        } catch {
            completion(error, nil)
        }
    }

    func fetchScheduleNotes(for date: Date, completion: @escaping ([ScheduleNote]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        // Get start and end of day for the given date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        db.collection("users").document(userId).collection("scheduleNotes")
            .whereField("date", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("date", isLessThan: Timestamp(date: endOfDay))
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                let notes = snapshot?.documents.compactMap { doc -> ScheduleNote? in
                    try? doc.data(as: ScheduleNote.self)
                } ?? []

                completion(notes, nil)
            }
    }

    func deleteScheduleNote(_ noteId: String, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("scheduleNotes").document(noteId).delete(completion: completion)
    }

    // MARK: - Proposal Interactions

    func saveProposalInteraction(_ interaction: ProposalInteraction, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let docRef = db.collection("users").document(userId).collection("proposalInteractions").document()
        do {
            try docRef.setData(from: interaction) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }

    func fetchRecentInteractions(limit: Int = 20, completion: @escaping ([ProposalInteraction]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("proposalInteractions")
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                let interactions = snapshot?.documents.compactMap { doc -> ProposalInteraction? in
                    try? doc.data(as: ProposalInteraction.self)
                } ?? []

                completion(interactions, nil)
            }
    }

    func fetchInteractionsForDay(_ dayOfWeek: String, limit: Int = 10, completion: @escaping ([ProposalInteraction]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("proposalInteractions")
            .whereField("dayOfWeek", isEqualTo: dayOfWeek.lowercased())
            .order(by: "timestamp", descending: true)
            .limit(to: limit)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }

                let interactions = snapshot?.documents.compactMap { doc -> ProposalInteraction? in
                    try? doc.data(as: ProposalInteraction.self)
                } ?? []

                completion(interactions, nil)
            }
    }

    // MARK: - Acceptance Stats

    func updateAcceptanceStats(_ stats: AcceptanceStats, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        // Convert stats to dictionary for Firestore
        var statsDict: [String: Any] = [
            "totalAccepted": stats.totalAccepted,
            "totalDeclined": stats.totalDeclined,
            "totalModified": stats.totalModified,
            "totalSkipped": stats.totalSkipped
        ]

        // Convert Int keys to String for Firestore compatibility
        var preferredHoursString: [String: Int] = [:]
        for (key, value) in stats.preferredHours {
            preferredHoursString[String(key)] = value
        }
        statsDict["preferredHours"] = preferredHoursString

        var preferredDurationsString: [String: Int] = [:]
        for (key, value) in stats.preferredDurations {
            preferredDurationsString[String(key)] = value
        }
        statsDict["preferredDurations"] = preferredDurationsString

        if let avgDuration = stats.averageAcceptedDuration {
            statsDict["averageAcceptedDuration"] = avgDuration
        }

        let docRef = db.collection("users").document(userId).collection("schedulePreferences").document("preferences")
        docRef.setData(["acceptanceStats": statsDict], merge: true) { error in
            completion(error)
        }
    }
    
    // MARK: - Scheduled Events Tracking
    
    func saveScheduledEvent(eventId: String, taskTitle: String, tasks: [String], startTime: Date, endTime: Date, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let docRef = db.collection("users").document(userId).collection("scheduledEvents").document(eventId)
        let data: [String: Any] = [
            "eventId": eventId,
            "taskTitle": taskTitle,
            "tasks": tasks,
            "startTime": Timestamp(date: startTime),
            "endTime": Timestamp(date: endTime),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        docRef.setData(data, merge: true) { error in
            completion(error)
        }
    }
    
    func fetchScheduledEvent(eventId: String, completion: @escaping ([String: Any]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("scheduledEvents").document(eventId)
            .getDocument { document, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                if let document = document, document.exists {
                    completion(document.data(), nil)
                } else {
                    completion(nil, nil)
                }
            }
    }
    
    func fetchScheduledEventIds(completion: @escaping ([String]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("scheduledEvents")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let eventIds = snapshot?.documents.map { $0.documentID } ?? []
                completion(eventIds, nil)
            }
    }
    
    func fetchScheduledEvents(completion: @escaping ([[String: Any]]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("scheduledEvents")
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let events = snapshot?.documents.compactMap { $0.data() } ?? []
                completion(events, nil)
            }
    }
    
    // MARK: - Journal Entries
    
    func saveJournalEntry(_ entry: JournalEntry, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let docRef = db.collection("users").document(userId).collection("journalEntries").document()
        do {
            try docRef.setData(from: entry) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    func fetchJournalEntries(completion: @escaping ([JournalEntry]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("journalEntries")
            .order(by: "timestamp", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let entries = snapshot?.documents.compactMap { doc -> JournalEntry? in
                    try? doc.data(as: JournalEntry.self)
                } ?? []
                
                completion(entries, nil)
            }
    }
    
    func fetchJournalEntries(for date: Date, completion: @escaping ([JournalEntry]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        db.collection("users").document(userId).collection("journalEntries")
            .whereField("scheduledStartTime", isGreaterThanOrEqualTo: Timestamp(date: startOfDay))
            .whereField("scheduledStartTime", isLessThan: Timestamp(date: endOfDay))
            .order(by: "scheduledStartTime", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    completion(nil, error)
                    return
                }
                
                let entries = snapshot?.documents.compactMap { doc -> JournalEntry? in
                    try? doc.data(as: JournalEntry.self)
                } ?? []
                
                completion(entries, nil)
            }
    }
    
    func updateJournalEntry(_ entry: JournalEntry, completion: @escaping (Error?) -> Void) {
        guard let userId = userId, let entryId = entry.id else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated or entry ID missing"]))
            return
        }
        
        let docRef = db.collection("users").document(userId).collection("journalEntries").document(entryId)
        do {
            try docRef.setData(from: entry, merge: true) { error in
                completion(error)
            }
        } catch {
            completion(error)
        }
    }
    
    func deleteJournalEntry(_ entryId: String, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        db.collection("users").document(userId).collection("journalEntries").document(entryId).delete(completion: completion)
    }
    
    func checkJournalEntryExists(eventId: String, completion: @escaping (Bool) -> Void) {
        guard let userId = userId else {
            completion(false)
            return
        }

        db.collection("users").document(userId).collection("journalEntries")
            .whereField("eventId", isEqualTo: eventId)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error checking journal entry: \(error.localizedDescription)")
                    completion(false)
                    return
                }

                let exists = snapshot?.documents.isEmpty == false
                completion(exists)
            }
    }

    // MARK: - TodoItem (Tasks) Firebase Storage

    /// Save a single TodoItem to Firestore
    func saveTodoItem(_ item: TodoItemCodable, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let docRef = db.collection("users").document(userId).collection("tasks").document(item.localTaskId)
        do {
            var itemToSave = item
            itemToSave.updatedAt = Date()
            try docRef.setData(from: itemToSave) { error in
                if let error = error {
                    print("FirebaseManager: Error saving TodoItem '\(item.title)': \(error.localizedDescription)")
                } else {
                    print("FirebaseManager: Successfully saved TodoItem '\(item.title)'")
                }
                completion(error)
            }
        } catch {
            print("FirebaseManager: Error encoding TodoItem '\(item.title)': \(error.localizedDescription)")
            completion(error)
        }
    }

    /// Save multiple TodoItems to Firestore using batch write
    func saveTodoItems(_ items: [TodoItemCodable], completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        guard !items.isEmpty else {
            completion(nil)
            return
        }

        let batch = db.batch()
        let encoder = Firestore.Encoder()

        for item in items {
            var itemToSave = item
            itemToSave.updatedAt = Date()
            let docRef = db.collection("users").document(userId).collection("tasks").document(item.localTaskId)
            do {
                let data = try encoder.encode(itemToSave)
                batch.setData(data, forDocument: docRef)
            } catch {
                print("FirebaseManager: Error encoding TodoItem '\(item.title)' for batch: \(error.localizedDescription)")
                completion(error)
                return
            }
        }

        batch.commit { error in
            if let error = error {
                print("FirebaseManager: Error batch saving \(items.count) TodoItems: \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully batch saved \(items.count) TodoItems")
            }
            completion(error)
        }
    }

    /// Fetch all TodoItems for the current user from Firestore
    func fetchTodoItems(completion: @escaping ([TodoItemCodable]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("tasks")
            .order(by: "dueDate", descending: false)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("FirebaseManager: Error fetching TodoItems: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }

                let items = snapshot?.documents.compactMap { doc -> TodoItemCodable? in
                    do {
                        return try doc.data(as: TodoItemCodable.self)
                    } catch {
                        print("FirebaseManager: Error decoding TodoItem document \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                } ?? []

                print("FirebaseManager: Fetched \(items.count) TodoItems from Firestore")
                completion(items, nil)
            }
    }

    /// Delete a TodoItem from Firestore
    func deleteTodoItem(localTaskId: String, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("tasks").document(localTaskId).delete { error in
            if let error = error {
                print("FirebaseManager: Error deleting TodoItem \(localTaskId): \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully deleted TodoItem \(localTaskId)")
            }
            completion(error)
        }
    }

    /// Delete multiple TodoItems from Firestore using batch write
    func deleteTodoItems(localTaskIds: [String], completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        guard !localTaskIds.isEmpty else {
            completion(nil)
            return
        }

        let batch = db.batch()

        for taskId in localTaskIds {
            let docRef = db.collection("users").document(userId).collection("tasks").document(taskId)
            batch.deleteDocument(docRef)
        }

        batch.commit { error in
            if let error = error {
                print("FirebaseManager: Error batch deleting \(localTaskIds.count) TodoItems: \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully batch deleted \(localTaskIds.count) TodoItems")
            }
            completion(error)
        }
    }

    /// Listen to real-time updates for TodoItems
    func listenToTodoItems(onUpdate: @escaping ([TodoItemCodable]) -> Void) -> ListenerRegistration? {
        guard let userId = userId else {
            onUpdate([])
            return nil
        }

        return db.collection("users").document(userId).collection("tasks")
            .order(by: "dueDate", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("FirebaseManager: Error listening to TodoItems: \(error.localizedDescription)")
                    onUpdate([])
                    return
                }

                let items = snapshot?.documents.compactMap { doc -> TodoItemCodable? in
                    try? doc.data(as: TodoItemCodable.self)
                } ?? []

                onUpdate(items)
            }
    }

    // MARK: - NoteItem (Notes) Firebase Storage

    /// Save a single NoteItem to Firestore
    func saveNoteItem(_ item: NoteItemCodable, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        let docRef = db.collection("users").document(userId).collection("notes").document(item.localNoteId)
        do {
            var itemToSave = item
            itemToSave.updatedAt = Date()
            try docRef.setData(from: itemToSave) { error in
                if let error = error {
                    print("FirebaseManager: Error saving NoteItem: \(error.localizedDescription)")
                } else {
                    print("FirebaseManager: Successfully saved NoteItem")
                }
                completion(error)
            }
        } catch {
            print("FirebaseManager: Error encoding NoteItem: \(error.localizedDescription)")
            completion(error)
        }
    }

    /// Save multiple NoteItems to Firestore using batch write
    func saveNoteItems(_ items: [NoteItemCodable], completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        guard !items.isEmpty else {
            completion(nil)
            return
        }

        let batch = db.batch()
        let encoder = Firestore.Encoder()

        for item in items {
            var itemToSave = item
            itemToSave.updatedAt = Date()
            let docRef = db.collection("users").document(userId).collection("notes").document(item.localNoteId)
            do {
                let data = try encoder.encode(itemToSave)
                batch.setData(data, forDocument: docRef)
            } catch {
                print("FirebaseManager: Error encoding NoteItem for batch: \(error.localizedDescription)")
                completion(error)
                return
            }
        }

        batch.commit { error in
            if let error = error {
                print("FirebaseManager: Error batch saving \(items.count) NoteItems: \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully batch saved \(items.count) NoteItems")
            }
            completion(error)
        }
    }

    /// Fetch all NoteItems for the current user from Firestore
    func fetchNoteItems(completion: @escaping ([NoteItemCodable]?, Error?) -> Void) {
        guard let userId = userId else {
            completion(nil, NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("notes")
            .order(by: "createdAt", descending: true)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("FirebaseManager: Error fetching NoteItems: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }

                let items = snapshot?.documents.compactMap { doc -> NoteItemCodable? in
                    do {
                        return try doc.data(as: NoteItemCodable.self)
                    } catch {
                        print("FirebaseManager: Error decoding NoteItem document \(doc.documentID): \(error.localizedDescription)")
                        return nil
                    }
                } ?? []

                print("FirebaseManager: Fetched \(items.count) NoteItems from Firestore")
                completion(items, nil)
            }
    }

    /// Delete a NoteItem from Firestore
    func deleteNoteItem(localNoteId: String, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        db.collection("users").document(userId).collection("notes").document(localNoteId).delete { error in
            if let error = error {
                print("FirebaseManager: Error deleting NoteItem \(localNoteId): \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully deleted NoteItem \(localNoteId)")
            }
            completion(error)
        }
    }

    /// Delete multiple NoteItems from Firestore using batch write
    func deleteNoteItems(localNoteIds: [String], completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }

        guard !localNoteIds.isEmpty else {
            completion(nil)
            return
        }

        let batch = db.batch()

        for noteId in localNoteIds {
            let docRef = db.collection("users").document(userId).collection("notes").document(noteId)
            batch.deleteDocument(docRef)
        }

        batch.commit { error in
            if let error = error {
                print("FirebaseManager: Error batch deleting \(localNoteIds.count) NoteItems: \(error.localizedDescription)")
            } else {
                print("FirebaseManager: Successfully batch deleted \(localNoteIds.count) NoteItems")
            }
            completion(error)
        }
    }
    
    /// Delete all cloud TodoItems that are not in the provided local task IDs set (for local-first sync)
    func deleteCloudTasksNotInLocal(localTaskIds: Set<String>, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Fetch all cloud tasks
        db.collection("users").document(userId).collection("tasks").getDocuments { [weak self] snapshot, error in
            guard let self = self else {
                completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"]))
                return
            }
            
            if let error = error {
                print("FirebaseManager: Error fetching cloud tasks for cleanup: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }
            
            // Find cloud tasks that are not in local set
            let cloudTaskIds = Set(documents.map { $0.documentID })
            let tasksToDelete = cloudTaskIds.subtracting(localTaskIds)
            
            guard !tasksToDelete.isEmpty else {
                print("FirebaseManager: No cloud tasks to delete (all cloud tasks exist locally)")
                completion(nil)
                return
            }
            
            print("FirebaseManager: Deleting \(tasksToDelete.count) cloud tasks not in local set")
            
            // Delete in batches (Firestore batch limit is 500)
            let batchSize = 500
            let taskIdsArray = Array(tasksToDelete)
            var completedBatches = 0
            var lastError: Error?
            let totalBatches = (taskIdsArray.count + batchSize - 1) / batchSize
            
            guard totalBatches > 0 else {
                completion(nil)
                return
            }
            
            for batchIndex in 0..<totalBatches {
                let startIndex = batchIndex * batchSize
                let endIndex = min(startIndex + batchSize, taskIdsArray.count)
                let batchTaskIds = Array(taskIdsArray[startIndex..<endIndex])
                
                let batch = self.db.batch()
                for taskId in batchTaskIds {
                    let docRef = self.db.collection("users").document(userId).collection("tasks").document(taskId)
                    batch.deleteDocument(docRef)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("FirebaseManager: Error deleting batch of cloud tasks: \(error.localizedDescription)")
                        lastError = error
                    } else {
                        print("FirebaseManager: Successfully deleted batch \(batchIndex + 1)/\(totalBatches) of cloud tasks")
                    }
                    
                    completedBatches += 1
                    if completedBatches == totalBatches {
                        completion(lastError)
                    }
                }
            }
        }
    }
    
    /// Delete all cloud NoteItems that are not in the provided local note IDs set (for local-first sync)
    func deleteCloudNotesNotInLocal(localNoteIds: Set<String>, completion: @escaping (Error?) -> Void) {
        guard let userId = userId else {
            completion(NSError(domain: "FirebaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        // Fetch all cloud notes
        db.collection("users").document(userId).collection("notes").getDocuments { [weak self] snapshot, error in
            guard let self = self else {
                completion(NSError(domain: "FirebaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"]))
                return
            }
            
            if let error = error {
                print("FirebaseManager: Error fetching cloud notes for cleanup: \(error.localizedDescription)")
                completion(error)
                return
            }
            
            guard let documents = snapshot?.documents else {
                completion(nil)
                return
            }
            
            // Find cloud notes that are not in local set
            let cloudNoteIds = Set(documents.map { $0.documentID })
            let notesToDelete = cloudNoteIds.subtracting(localNoteIds)
            
            guard !notesToDelete.isEmpty else {
                print("FirebaseManager: No cloud notes to delete (all cloud notes exist locally)")
                completion(nil)
                return
            }
            
            print("FirebaseManager: Deleting \(notesToDelete.count) cloud notes not in local set")
            
            // Delete in batches (Firestore batch limit is 500)
            let batchSize = 500
            let noteIdsArray = Array(notesToDelete)
            var completedBatches = 0
            var lastError: Error?
            let totalBatches = (noteIdsArray.count + batchSize - 1) / batchSize
            
            guard totalBatches > 0 else {
                completion(nil)
                return
            }
            
            for batchIndex in 0..<totalBatches {
                let startIndex = batchIndex * batchSize
                let endIndex = min(startIndex + batchSize, noteIdsArray.count)
                let batchNoteIds = Array(noteIdsArray[startIndex..<endIndex])
                
                let batch = self.db.batch()
                for noteId in batchNoteIds {
                    let docRef = self.db.collection("users").document(userId).collection("notes").document(noteId)
                    batch.deleteDocument(docRef)
                }
                
                batch.commit { error in
                    if let error = error {
                        print("FirebaseManager: Error deleting batch of cloud notes: \(error.localizedDescription)")
                        lastError = error
                    } else {
                        print("FirebaseManager: Successfully deleted batch \(batchIndex + 1)/\(totalBatches) of cloud notes")
                    }
                    
                    completedBatches += 1
                    if completedBatches == totalBatches {
                        completion(lastError)
                    }
                }
            }
        }
    }

    /// Listen to real-time updates for NoteItems
    func listenToNoteItems(onUpdate: @escaping ([NoteItemCodable]) -> Void) -> ListenerRegistration? {
        guard let userId = userId else {
            onUpdate([])
            return nil
        }

        return db.collection("users").document(userId).collection("notes")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("FirebaseManager: Error listening to NoteItems: \(error.localizedDescription)")
                    onUpdate([])
                    return
                }

                let items = snapshot?.documents.compactMap { doc -> NoteItemCodable? in
                    try? doc.data(as: NoteItemCodable.self)
                } ?? []

                onUpdate(items)
            }
    }

    // MARK: - Group Chats

    func createGroup(name: String, memberIds: [String], memberDisplayNames: [String: String], completion: @escaping (Error?, String?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }
        let groupRef = db.collection("group_chats").document()
        let groupId = groupRef.documentID
        let now = Date()
        let batch = db.batch()

        let groupData: [String: Any] = [
            "name": name,
            "adminId": currentUserId,
            "memberIds": memberIds,
            "lastMessageText": "",
            "lastMessageAt": Timestamp(date: now),
            "lastMessageSenderId": "",
            "createdAt": Timestamp(date: now)
        ]
        batch.setData(groupData, forDocument: groupRef)

        for memberId in memberIds {
            let memberRef = groupRef.collection("members").document(memberId)
            let memberData: [String: Any] = [
                "displayName": memberDisplayNames[memberId] ?? "",
                "joinedAt": Timestamp(date: now),
                "role": memberId == currentUserId ? "admin" : "member"
            ]
            batch.setData(memberData, forDocument: memberRef)
        }

        batch.commit { error in
            completion(error, error == nil ? groupId : nil)
        }
    }

    func listenToMyGroups(onUpdate: @escaping ([GroupConversation]) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("group_chats")
            .whereField("memberIds", arrayContains: currentUserId)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                var groups = documents.compactMap { try? $0.data(as: GroupConversation.self) }
                groups.sort { $0.lastMessageAt > $1.lastMessageAt }
                onUpdate(groups)
            }
    }

    func sendGroupMessage(groupId: String, content: String, senderDisplayName: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        let groupRef = db.collection("group_chats").document(groupId)
        let msgRef = groupRef.collection("messages").document()
        let now = Date()
        let msgData: [String: Any] = [
            "senderId": currentUserId,
            "senderDisplayName": senderDisplayName,
            "receiverId": "",
            "content": content,
            "timestamp": Timestamp(date: now)
        ]
        msgRef.setData(msgData) { error in
            if let error = error {
                completion(error)
                return
            }
            groupRef.updateData([
                "lastMessageText": content,
                "lastMessageAt": Timestamp(date: now),
                "lastMessageSenderId": currentUserId
            ]) { error in
                completion(error)
            }
        }
    }

    func listenToGroupChat(groupId: String, onUpdate: @escaping ([ChatMessage]) -> Void) -> ListenerRegistration? {
        return db.collection("group_chats").document(groupId).collection("messages")
            .order(by: "timestamp")
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                let messages: [ChatMessage] = documents.compactMap { doc in
                    guard var msg = try? doc.data(as: ChatMessage.self) else { return nil }
                    msg.groupId = groupId
                    return msg
                }
                onUpdate(messages)
            }
    }

    func fetchGroupMembers(groupId: String, completion: @escaping ([GroupMember]) -> Void) {
        db.collection("group_chats").document(groupId).collection("members")
            .getDocuments { snapshot, _ in
                let members = snapshot?.documents.compactMap { try? $0.data(as: GroupMember.self) } ?? []
                completion(members)
            }
    }

    func addMemberToGroup(groupId: String, userId: String, displayName: String, completion: @escaping (Error?) -> Void) {
        let groupRef = db.collection("group_chats").document(groupId)
        let memberRef = groupRef.collection("members").document(userId)
        let batch = db.batch()
        let memberData: [String: Any] = [
            "displayName": displayName,
            "joinedAt": Timestamp(date: Date()),
            "role": "member"
        ]
        batch.setData(memberData, forDocument: memberRef)
        batch.updateData(["memberIds": FieldValue.arrayUnion([userId])], forDocument: groupRef)
        batch.commit(completion: completion)
    }

    func removeMemberFromGroup(groupId: String, userId: String, completion: @escaping (Error?) -> Void) {
        let groupRef = db.collection("group_chats").document(groupId)
        let memberRef = groupRef.collection("members").document(userId)
        let batch = db.batch()
        batch.deleteDocument(memberRef)
        batch.updateData(["memberIds": FieldValue.arrayRemove([userId])], forDocument: groupRef)
        batch.commit(completion: completion)
    }

    func leaveGroup(groupId: String, completion: @escaping (Error?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        let groupRef = db.collection("group_chats").document(groupId)
        groupRef.getDocument { [weak self] snapshot, error in
            guard let self = self, let data = snapshot?.data() else {
                completion(error)
                return
            }
            let memberIds = data["memberIds"] as? [String] ?? []
            let remaining = memberIds.filter { $0 != currentUserId }

            if remaining.isEmpty {
                // Last member — delete the group
                groupRef.delete(completion: completion)
                return
            }

            let isAdmin = (data["adminId"] as? String) == currentUserId
            let batch = self.db.batch()
            batch.deleteDocument(groupRef.collection("members").document(currentUserId))
            batch.updateData(["memberIds": FieldValue.arrayRemove([currentUserId])], forDocument: groupRef)
            if isAdmin {
                // Transfer admin to the first remaining member
                batch.updateData(["adminId": remaining[0]], forDocument: groupRef)
            }
            batch.commit(completion: completion)
        }
    }

    func sendSharedTaskToGroup(groupId: String, groupName: String, recipientIds: [String], title: String, detail: String, dueDate: Date, subtasks: [SharedSubtask], senderDisplayName: String, completion: @escaping (Error?, [String]?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }
        let batch = db.batch()
        var createdIds: [String] = []
        let subtasksPayload = subtasks.map { ["id": $0.id, "title": $0.title, "isDone": $0.isDone] as [String: Any] }

        for recipientId in recipientIds {
            let docRef = db.collection("shared_tasks").document()
            createdIds.append(docRef.documentID)
            let payload: [String: Any] = [
                "senderId": currentUserId,
                "receiverId": recipientId,
                "title": title,
                "detail": detail,
                "dueDate": Timestamp(date: dueDate),
                "isAccepted": false,
                "isCompleted": false,
                "createdAt": FieldValue.serverTimestamp(),
                "completedAt": NSNull(),
                "isProgressShare": false,
                "subtasks": subtasksPayload,
                "groupId": groupId,
                "senderDisplayName": senderDisplayName
            ]
            batch.setData(payload, forDocument: docRef)
        }

        // System message in group chat
        let msgRef = db.collection("group_chats").document(groupId).collection("messages").document()
        let now = Date()
        batch.setData([
            "senderId": currentUserId,
            "senderDisplayName": senderDisplayName,
            "receiverId": "",
            "content": "Sent task: \(title)",
            "timestamp": Timestamp(date: now)
        ], forDocument: msgRef)

        let groupRef = db.collection("group_chats").document(groupId)
        batch.updateData([
            "lastMessageText": "Sent task: \(title)",
            "lastMessageAt": Timestamp(date: now),
            "lastMessageSenderId": currentUserId
        ], forDocument: groupRef)

        batch.commit { error in
            completion(error, error == nil ? createdIds : nil)
        }
    }

    func shareProgressToGroup(groupId: String, recipientIds: [String], title: String, detail: String, dueDate: Date, subtasks: [SharedSubtask], isCompleted: Bool, senderDisplayName: String, completion: @escaping (Error?, [String]?) -> Void) {
        guard let currentUserId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]), nil)
            return
        }
        let batch = db.batch()
        var createdIds: [String] = []
        let subtasksPayload = subtasks.map { ["id": $0.id, "title": $0.title, "isDone": $0.isDone] as [String: Any] }
        let now = Date()

        for recipientId in recipientIds {
            let docRef = db.collection("shared_tasks").document()
            createdIds.append(docRef.documentID)
            let payload: [String: Any] = [
                "senderId": currentUserId,
                "receiverId": recipientId,
                "title": title,
                "detail": detail,
                "dueDate": Timestamp(date: dueDate),
                "isAccepted": true,
                "isCompleted": isCompleted,
                "createdAt": FieldValue.serverTimestamp(),
                "completedAt": isCompleted ? Timestamp(date: now) : NSNull(),
                "isProgressShare": true,
                "subtasks": subtasksPayload,
                "groupId": groupId,
                "senderDisplayName": senderDisplayName
            ]
            batch.setData(payload, forDocument: docRef)
        }

        let msgRef = db.collection("group_chats").document(groupId).collection("messages").document()
        batch.setData([
            "senderId": currentUserId,
            "senderDisplayName": senderDisplayName,
            "receiverId": "",
            "content": "Shared progress: \(title)",
            "timestamp": Timestamp(date: now)
        ], forDocument: msgRef)

        let groupRef = db.collection("group_chats").document(groupId)
        batch.updateData([
            "lastMessageText": "Shared progress: \(title)",
            "lastMessageAt": Timestamp(date: now),
            "lastMessageSenderId": currentUserId
        ], forDocument: groupRef)

        batch.commit { error in
            completion(error, error == nil ? createdIds : nil)
        }
    }

    func listenToSharedTasksInGroup(groupId: String, onUpdate: @escaping ([SharedTask]) -> Void) -> ListenerRegistration? {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return nil }
        return db.collection("shared_tasks")
            .whereField("groupId", isEqualTo: groupId)
            .whereFilter(Filter.orFilter([
                Filter.whereField("senderId", isEqualTo: currentUserId),
                Filter.whereField("receiverId", isEqualTo: currentUserId)
            ]))
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    onUpdate([])
                    return
                }
                var tasks = documents.compactMap { try? $0.data(as: SharedTask.self) }
                tasks.sort { $0.createdAt < $1.createdAt }
                onUpdate(tasks)
            }
    }

    func fetchGroup(groupId: String, completion: @escaping (GroupConversation?) -> Void) {
        db.collection("group_chats").document(groupId).getDocument { snapshot, _ in
            let group = snapshot.flatMap { try? $0.data(as: GroupConversation.self) }
            completion(group)
        }
    }
}
