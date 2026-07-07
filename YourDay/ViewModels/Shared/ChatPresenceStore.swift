import Foundation
import Combine

/// Tracks where the user is in the chat UI so we can suppress in-app banners appropriately.
@MainActor
final class ChatPresenceStore: ObservableObject {
    static let shared = ChatPresenceStore()

    /// True while `ChatListView` is visible.
    var isOnChatList = false
    /// The friend whose DM thread is currently open, if any.
    var activeChatFriendId: String?

    private init() {}

    func shouldShowInAppBanner(forSenderId senderId: String) -> Bool {
        if isOnChatList { return false }
        if activeChatFriendId == senderId { return false }
        return true
    }
}
