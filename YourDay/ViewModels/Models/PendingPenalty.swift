import Foundation

struct PendingPenalty: Codable, Identifiable, Hashable {
    enum Reason: String, Codable {
        case skippedPlanning
        case clickedThroughDuringTask
    }

    var id: UUID
    var amount: Int
    var reason: Reason
    var context: String?
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        amount: Int,
        reason: Reason,
        context: String? = nil,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.reason = reason
        self.context = context
        self.occurredAt = occurredAt
    }

    var displayReason: String {
        switch reason {
        case .skippedPlanning:
            return "Skipped planning"
        case .clickedThroughDuringTask:
            if let context, !context.isEmpty {
                return "Broke focus during: \(context)"
            }
            return "Broke focus during a scheduled task"
        }
    }
}
