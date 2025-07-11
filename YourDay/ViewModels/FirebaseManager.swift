//
//  FirebaseManager.swift
//  YourDay
//
//  Created by Rachit Verma on 5/19/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    private var db = Firestore.firestore()
    private var listenerRegistrations: [ListenerRegistration] = []

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
                    completion(nil, decodeError)
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

        let friendData: [String: Any] = [
            "status": "accepted",
            "displayName": displayName,
            "timestamp": FieldValue.serverTimestamp()
        ]

        // Locate the request first
        let requestQuery = db.collection("users").document(currentUserId)
            .collection("friend_requests")
            .whereField("fromUserId", isEqualTo: fromUserId)

        requestQuery.getDocuments { snapshot, error in
            guard let doc = snapshot?.documents.first else {
                completion(error ?? NSError(domain: "", code: 404, userInfo: [NSLocalizedDescriptionKey: "Friend request not found"]))
                return
            }

            let requestRef = doc.reference

            let batch = self.db.batch()
            batch.setData(friendData, forDocument: myRef)
            batch.setData(friendData, forDocument: theirRef)
            batch.deleteDocument(requestRef)

            batch.commit(completion: completion)
        }
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

        db.collection("users").document(currentUserId)
            .collection("friends")
            .whereField("status", isEqualTo: "accepted")
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents, error == nil else {
                    completion([])
                    return
                }

                let friends: [FriendEntry] = documents.compactMap { doc in
                    let data = doc.data()
                    let friendUserId = doc.documentID
                    guard let displayName = data["displayName"] as? String else {
                        return nil
                    }
                    return FriendEntry(userId: friendUserId, displayName: displayName)
                }

                completion(friends)
            }
    }

    func removeAllListeners() {
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        print("All Firestore listeners removed.")
    }
}
