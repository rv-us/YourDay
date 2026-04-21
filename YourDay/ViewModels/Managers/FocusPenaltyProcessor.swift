import Foundation
import SwiftData
import SwiftUI
import Combine

@MainActor
final class FocusPenaltyProcessor: ObservableObject {
    static let shared = FocusPenaltyProcessor()

    struct DrainResult: Equatable {
        var totalDeducted: Int
        var penaltyCount: Int
        var reasons: [String]
    }

    @Published var lastDrainResult: DrainResult?

    private init() {}

    func drainPending(
        context: ModelContext,
        loginViewModel: LoginViewModel?
    ) async {
        let pending = AppGroupDefaults.loadPendingPenalties()
        guard !pending.isEmpty else { return }

        let total = pending.reduce(0) { $0 + $1.amount }
        let reasons = pending.map(\.displayReason)

        let descriptor = FetchDescriptor<PlayerStats>()
        let stats = (try? context.fetch(descriptor))?.first
        guard let stats else {
            print("FocusPenaltyProcessor: no PlayerStats found, keeping penalties queued")
            return
        }

        let newTotal = max(0, stats.totalPoints - Double(total))
        stats.totalPoints = newTotal

        do {
            try context.save()
        } catch {
            print("FocusPenaltyProcessor: save failed — \(error.localizedDescription)")
            return
        }

        loginViewModel?.syncLocalPlayerStatsToFirestore(playerStatsModel: stats)

        AppGroupDefaults.clearPendingPenalties()
        self.lastDrainResult = DrainResult(
            totalDeducted: total,
            penaltyCount: pending.count,
            reasons: reasons
        )
    }

    func acknowledgeLastDrain() {
        self.lastDrainResult = nil
    }
}
