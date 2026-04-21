import ManagedSettings
import Foundation

final class ShieldActionExtension: ShieldActionDelegate {

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    // MARK: - Action handling

    private func response(for action: ShieldAction) -> ShieldActionResponse {
        switch action {
        case .primaryButtonPressed:
            recordPenaltyIfNeeded()
            return .defer
        case .secondaryButtonPressed:
            return .close
        @unknown default:
            return .close
        }
    }

    private func recordPenaltyIfNeeded() {
        let snapshot = AppGroupDefaults.loadSnapshot()
        let penaltyAmount = snapshot?.penaltyAmount ?? 100

        guard let snapshot, snapshot.dayKey == ShieldSnapshot.dayKey() else {
            AppGroupDefaults.appendPendingPenalty(
                PendingPenalty(amount: penaltyAmount, reason: .skippedPlanning)
            )
            return
        }

        if !snapshot.hasPlannedDay {
            AppGroupDefaults.appendPendingPenalty(
                PendingPenalty(amount: penaltyAmount, reason: .skippedPlanning)
            )
            return
        }

        if let active = snapshot.activeTask() {
            AppGroupDefaults.appendPendingPenalty(
                PendingPenalty(
                    amount: penaltyAmount,
                    reason: .clickedThroughDuringTask,
                    context: active.title
                )
            )
            return
        }

        // Planned day, outside any task slot → free click-through, no penalty.
    }
}
