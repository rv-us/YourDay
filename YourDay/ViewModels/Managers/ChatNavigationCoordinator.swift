import Foundation
import Combine

/// Routes the user directly into a DM thread from global UI (e.g. in-app message banner).
@MainActor
final class ChatNavigationCoordinator: ObservableObject {
    static let shared = ChatNavigationCoordinator()

    @Published private(set) var pendingFriend: FriendEntry?

    private init() {}

    func openChat(_ friend: FriendEntry) {
        pendingFriend = friend
    }

    func clearPending() {
        pendingFriend = nil
    }
}
