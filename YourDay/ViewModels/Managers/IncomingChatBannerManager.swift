import Foundation
import Combine

struct IncomingChatBannerPayload: Identifiable, Equatable {
    var id: String { senderId }
    let senderId: String
    let senderName: String
    let preview: String
}

@MainActor
final class IncomingChatBannerManager: ObservableObject {
    static let shared = IncomingChatBannerManager()

    @Published private(set) var activeBanner: IncomingChatBannerPayload?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    func show(message: ChatMessage, senderName: String) {
        guard ChatPresenceStore.shared.shouldShowInAppBanner(forSenderId: message.senderId) else { return }

        let preview = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        activeBanner = IncomingChatBannerPayload(
            senderId: message.senderId,
            senderName: senderName,
            preview: preview.isEmpty ? "New message" : preview
        )

        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        activeBanner = nil
    }
}
