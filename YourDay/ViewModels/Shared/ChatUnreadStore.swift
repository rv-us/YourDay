import Foundation
import Combine

/// Tracks which DM message each friend conversation was last read through.
@MainActor
final class ChatUnreadStore: ObservableObject {
    static let shared = ChatUnreadStore()

    @Published private(set) var dmLastReadMessageId: [String: String] = [:]

    private let storageKey = "dmLastReadMessageIds"

    private init() {
        load()
    }

    func load() {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            dmLastReadMessageId = [:]
            return
        }
        dmLastReadMessageId = decoded
    }

    /// Marks a DM conversation read through `message` (typically the latest message in the thread).
    func markDMRead(friendId: String, upToMessage message: ChatMessage?) {
        guard let messageId = message?.id else { return }
        guard dmLastReadMessageId[friendId] != messageId else { return }
        dmLastReadMessageId[friendId] = messageId
        persist()
    }

    func isDMUnread(friendId: String, lastMessage: ChatMessage?) -> Bool {
        guard let message = lastMessage,
              message.senderId == friendId,
              let messageId = message.id else {
            return false
        }
        return dmLastReadMessageId[friendId] != messageId
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(dmLastReadMessageId),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: storageKey)
    }
}
