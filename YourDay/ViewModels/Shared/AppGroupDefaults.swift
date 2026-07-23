import Foundation

enum AppGroupDefaults {
    static let suiteName = "group.Yourday.dev.screentime"

    enum Key {
        static let shieldSnapshot = "shieldSnapshot.v1"
        static let pendingPenalties = "pendingFocusPenalties.v1"
        static let shieldEnabled = "screenTimeShieldEnabled"
        static let familySelection = "screenTimeFamilySelection"
        /// Unix timestamp (seconds since 1970) recorded by the shield-action
        /// extension immediately before it calls `stopMonitoring` on a stale
        /// break-focus grace activity. The monitor extension checks this on
        /// `intervalDidEnd` to suppress the "grace window expired → reapply
        /// shield" path when the end was caused by our own manual restart.
        static let graceStopSuppressUntil = "breakFocusGraceStopSuppressUntil"
        /// Wall-clock end of the current shield unblock (Unix time). Set by the
        /// shield-action extension to match the `DeviceActivity` reshield schedule;
        /// cleared when the monitor reapplies or the main app forces full shield.
        /// The main app reads this only to avoid reapplying selection during the unblock.
        static let graceWindowEndsAt = "breakFocusGraceWindowEndsAt"
        /// `yyyy-MM-dd` for the last day the user cleared Today (no open tasks left after planning).
        static let planningFulfilledDayKey = "shieldPlanningFulfilledDayKey"
        /// When `true`, apps are only shielded while a scheduled focus task is
        /// active right now. Between tasks — or when nothing is scheduled — apps
        /// stay unblocked (no "plan your day" or "between tasks" soft block).
        /// Default (unset → `false`) preserves the full soft-block behavior.
        static let scheduledTasksOnly = "screenTimeScheduledTasksOnly"
    }

    // Cache the app-group UserDefaults as a single shared instance. Creating
    // a new UserDefaults object on every access is unnecessary and makes
    // durability guarantees harder to reason about.
    private static let sharedDefaults: UserDefaults = {
        if let suite = UserDefaults(suiteName: suiteName) {
            return suite
        }
        assertionFailure("AppGroupDefaults: failed to open suite '\(suiteName)'. Check app-group entitlements. Falling back to standard defaults.")
        return .standard
    }()

    static var defaults: UserDefaults { sharedDefaults }

    // Force-flush pending writes to disk. UserDefaults normally writes
    // asynchronously, so values written shortly before a force-quit can be
    // lost. Call this after toggling any shield-critical flags and when the
    // app backgrounds so cross-process extensions see a consistent state.
    static func flush() {
        sharedDefaults.synchronize()
    }

    static func loadSnapshot() -> ShieldSnapshot? {
        guard let data = defaults.data(forKey: Key.shieldSnapshot) else { return nil }
        return try? JSONDecoder().decode(ShieldSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: ShieldSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.shieldSnapshot)
    }

    static func loadPendingPenalties() -> [PendingPenalty] {
        guard let data = defaults.data(forKey: Key.pendingPenalties) else { return [] }
        return (try? JSONDecoder().decode([PendingPenalty].self, from: data)) ?? []
    }

    static func savePendingPenalties(_ penalties: [PendingPenalty]) {
        guard let data = try? JSONEncoder().encode(penalties) else { return }
        defaults.set(data, forKey: Key.pendingPenalties)
    }

    static func appendPendingPenalty(_ penalty: PendingPenalty) {
        var current = loadPendingPenalties()
        current.append(penalty)
        savePendingPenalties(current)
    }

    static func clearPendingPenalties() {
        defaults.removeObject(forKey: Key.pendingPenalties)
    }

    // MARK: - Shield unblock window (until scheduled reshield)

    static func setGraceWindowEnd(_ date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.graceWindowEndsAt)
    }

    static func clearGraceWindowEnd() {
        defaults.removeObject(forKey: Key.graceWindowEndsAt)
    }

    static func graceWindowEndDate() -> Date? {
        let ts = defaults.double(forKey: Key.graceWindowEndsAt)
        guard ts > 0 else { return nil }
        return Date(timeIntervalSince1970: ts)
    }

    // MARK: - Daily planning fulfilled (shield off for rest of day)

    static func markTodayPlanningFulfilled(dayKey: String) {
        defaults.set(dayKey, forKey: Key.planningFulfilledDayKey)
    }

    static func isTodayPlanningFulfilled(dayKey: String) -> Bool {
        defaults.string(forKey: Key.planningFulfilledDayKey) == dayKey
    }

    // MARK: - Scheduled-tasks-only mode

    /// When `true`, the shield is limited to active scheduled focus windows.
    static var scheduledTasksOnlyMode: Bool {
        defaults.bool(forKey: Key.scheduledTasksOnly)
    }

    /// Whether ManagedSettings shields should be active right now.
    static func shouldApplyShieldBlocks() -> Bool {
        guard defaults.bool(forKey: Key.shieldEnabled) else { return false }
        guard let snapshot = loadSnapshot(), snapshot.dayKey == ShieldSnapshot.dayKey() else {
            // No fresh snapshot for today. In scheduled-tasks-only mode we can't
            // confirm an active task, so leave apps unblocked; otherwise fall
            // back to blocking (the full soft-block default).
            return !scheduledTasksOnlyMode
        }
        if scheduledTasksOnlyMode {
            // Only block while a scheduled focus task is active right now.
            return snapshot.isInTaskSlot()
        }
        return snapshot.shouldBlockApps
    }
}
