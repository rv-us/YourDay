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
    
    // MARK: - Other Data Types (Placeholders - ensure Codable versions or mapping)
    // func saveTodoItem(_ todoItem: CodableTodoItem, completion: @escaping (Error?) -> Void) { ... }
    // func loadTodoItems(completion: @escaping ([CodableTodoItem]?, Error?) -> Void) { ... }
    // ... and so on for NoteItem, DailySummaryTask ...
    
    // MARK: - Listener Management
    func removeAllListeners() {
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        print("All Firestore listeners removed.")
    }
}
