//
//  FirebaseManager.swift
//  YourDay
//
//  Created by Rachit Verma on 5/19/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct UserSearchResult: Identifiable {
    var id: String { userId }
    let userId: String
    let displayName: String
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
                    var entry = try document.data(as: LeaderboardEntry.self)
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

    func removeAllListeners() {
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        print("All Firestore listeners removed.")
    }
}
