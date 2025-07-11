//
//  LeaderBoardViewModel.swift
//  YourDay
//
//  Created by Rachit Verma on 5/20/25.
//

import SwiftUI
import Combine
import FirebaseAuth // To get current user ID

class LeaderboardViewModel: ObservableObject {
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentUserRank: Int? = nil
    
    // This should be updated by the view if the authenticated user changes
    // or when the ViewModel is initialized with the current user's context.
    @Published var currentUserID: String?

    private let firebaseManager = FirebaseManager()
    private var cancellables = Set<AnyCancellable>()

    init(currentUserID: String? = Auth.auth().currentUser?.uid) {
        self.currentUserID = currentUserID
        print("LeaderboardViewModel initialized. Current User ID for ranking: \(currentUserID ?? "nil"). Attempting to fetch data.")
        fetchLeaderboardData()

        // If currentUserID can change after init (e.g., due to login/logout while view is alive),
        // you might want to observe it and re-fetch.
        // For instance, if passed from a parent view that observes LoginViewModel:
        // $currentUserID
        //    .dropFirst() // Avoid re-fetch on initial set if fetchLeaderboardData is already called
        //    .removeDuplicates() // Avoid re-fetch if ID is set to the same value
        //    .sink { [weak self] newUserID in
        //        print("LeaderboardViewModel: currentUserID changed to \(newUserID ?? "nil"). Re-fetching leaderboard.")
        //        self?.fetchLeaderboardData()
        //    }
        //    .store(in: &cancellables)
    }

    /// Fetches leaderboard data from Firebase, ordered by a specified field.
    /// - Parameters:
    ///   - orderBy: The field to sort by (e.g., "gardenValue", "playerLevel").
    ///   - limit: The maximum number of entries to fetch.
    func fetchLeaderboardData(orderBy: String = "gardenValue", limit: Int = 200) {
        self.isLoading = true
        self.errorMessage = nil
        // Clearing entries immediately can cause a flicker. Consider updating existing or replacing.
        // self.leaderboardEntries = []
        self.currentUserRank = nil // Reset current user's rank before fetching

        print("LeaderboardViewModel: Fetching leaderboard data from Firebase, ordered by \(orderBy), limit \(limit)...")

        firebaseManager.fetchLeaderboardEntries(orderBy: orderBy, descending: true, limit: limit) { [weak self] (entries, error) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to load leaderboard: \(error.localizedDescription)"
                    print("LeaderboardViewModel: Error fetching leaderboard - \(self.errorMessage ?? "Unknown error")")
                } else if var fetchedEntries = entries {
                    // Assign ranks based on the fetched order (which is already sorted by Firestore)
                    for i in 0..<fetchedEntries.count {
                        fetchedEntries[i].rank = i + 1 // Assign 1-based rank
                        if let currentUID = self.currentUserID, fetchedEntries[i].id == currentUID {
                            self.currentUserRank = fetchedEntries[i].rank
                            print("LeaderboardViewModel: Current user (\(currentUID)) found at rank \(self.currentUserRank!).")
                        }
                    }
                    self.leaderboardEntries = fetchedEntries
                    print("LeaderboardViewModel: Successfully fetched and ranked \(fetchedEntries.count) entries.")
                    if self.currentUserID != nil && self.currentUserRank == nil {
                        print("LeaderboardViewModel: Current user (\(self.currentUserID!)) not found in the top \(limit) leaderboard entries for order '\(orderBy)'.")
                    }
                } else {
                    self.leaderboardEntries = [] // Ensure it's empty if no entries are returned
                    print("LeaderboardViewModel: No leaderboard entries found or returned from Firebase, but no error.")
                }
            }
        }
    }
    
    /// Refreshes the leaderboard data by re-fetching from Firebase.
    func refreshLeaderboard() {
        print("LeaderboardViewModel: Refreshing leaderboard...")
        // Re-fetch with currentUserID, which might have been updated by the view
        self.currentUserID = Auth.auth().currentUser?.uid
        fetchLeaderboardData()
    }
    func fetchLeaderboardFriendsOnly(orderBy: String = "gardenValue", limit: Int = 200) {
        guard let uid = currentUserID else { return }

        firebaseManager.fetchFriendUserIDs { [weak self] friendIds in
            guard let self = self else { return }

            self.firebaseManager.fetchLeaderboardEntries(orderBy: orderBy, descending: true, limit: limit) { (entries, error) in
                DispatchQueue.main.async {
                    if let entries = entries {
                        self.leaderboardEntries = entries.filter { entry in
                            return entry.id == uid || friendIds.contains(entry.id)
                        }
                        self.currentUserRank = nil
                        for (i, entry) in self.leaderboardEntries.enumerated() {
                            if entry.id == uid {
                                self.currentUserRank = i + 1
                            }
                        }
                    }
                }
            }
        }
    }

    /// Updates the current user's entry in the leaderboard.
    /// This should be called when the user's PlayerStats (level, gardenValue) or display name changes.
    /// - Parameters:
    ///   - playerStats: The user's current PlayerStats @Model instance.
    ///   - displayName: The user's current display name (from Firebase Auth or LoginViewModel).
    func updateUserEntryInLeaderboard(playerStats: PlayerStats, displayName: String?) {
        guard let userID = Auth.auth().currentUser?.uid else {
            print("LeaderboardViewModel: Cannot update leaderboard entry, user not authenticated.")
            return
        }
        
        // Ensure the displayName used is the most current one.
        let nameForLeaderboard = displayName ?? Auth.auth().currentUser?.displayName ?? "Anonymous"

        print("LeaderboardViewModel: Preparing to update leaderboard entry for user \(userID) with Name: \(nameForLeaderboard), Level: \(playerStats.playerLevel), GardenValue: \(playerStats.gardenValue)")

        let updatedEntry = LeaderboardEntry(
            id: userID, // This ID must match the document ID in Firestore for the update to target correctly
            displayName: nameForLeaderboard,
            playerLevel: playerStats.playerLevel,
            gardenValue: playerStats.gardenValue
            // rank will be determined by sorting, not stored directly unless you manage it differently
        )
        
        firebaseManager.updateLeaderboardEntry(entry: updatedEntry) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    // Potentially set an errorMessage for the UI
                    self?.errorMessage = "Failed to update your leaderboard score: \(error.localizedDescription)"
                    print("LeaderboardViewModel: Failed to update user's leaderboard entry: \(error.localizedDescription)")
                } else {
                    print("LeaderboardViewModel: User's leaderboard entry update sent successfully. Leaderboard will refresh on next view or manual refresh.")
                    // Optionally, you could try to update the local entry if it exists in `leaderboardEntries`
                    // or trigger a full refresh of the leaderboard to see immediate changes.
                    // self?.refreshLeaderboard() // Uncomment to auto-refresh after update
                }
            }
        }
    }
}

