import Foundation
import SwiftUI

final class DashboardFriendStatsViewModel: ObservableObject {
    @Published var cards: [FriendDashboardStats] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var hasLoadedOnce: Bool = false

    private let firebaseManager: FirebaseManager

    init(firebaseManager: FirebaseManager = .shared) {
        self.firebaseManager = firebaseManager
    }

    func load(force: Bool = false) {
        guard !isLoading else { return }
        guard force || !hasLoadedOnce else { return }

        isLoading = true
        errorMessage = nil

        firebaseManager.fetchFriendDashboardStats { [weak self] fetched in
            guard let self else { return }
            self.cards = Self.sortCards(fetched)
            self.isLoading = false
            self.hasLoadedOnce = true
        }
    }

    func refresh() {
        load(force: true)
    }

    static func sortCards(_ cards: [FriendDashboardStats]) -> [FriendDashboardStats] {
        cards.sorted { lhs, rhs in
            if lhs.yesterdayPoints != rhs.yesterdayPoints {
                return lhs.yesterdayPoints > rhs.yesterdayPoints
            }
            if lhs.taskStreak != rhs.taskStreak {
                return lhs.taskStreak > rhs.taskStreak
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
