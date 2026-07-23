import ManagedSettings
import DeviceActivity
import FamilyControls
import Foundation
import OSLog

/// Shared constants that must match the strings used by
/// `DeviceActivityMonitorExtension`. Duplicated here (rather than imported)
/// because the two extensions live in separate build targets; the
/// `DeviceActivity` framework only compares raw values so string equality is
/// all that's required.
private enum DeviceActivityMonitorNames {
    static let breakFocusGrace = DeviceActivityName("YourDayBreakFocusGrace")
}

final class ShieldActionExtension: ShieldActionDelegate {

    private let logger = Logger(subsystem: "com.yourday.app", category: "ShieldAction")
    private let store = ManagedSettingsStore(named: .init("YourDayShield"))
    private let activityCenter = DeviceActivityCenter()

    /// Unblock duration after the user taps through the shield. iOS requires
    /// `DeviceActivitySchedule` intervals to be long enough (~15 minutes);
    /// reshielding happens only when this interval ends (`DeviceActivityMonitor`).
    private static let reshieldIntervalSeconds: TimeInterval = 15 * 60

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logStoreState(tag: "before handle(application)")
        logger.notice("ShieldAction action=\(String(describing: action), privacy: .public) target=application now=\(Self.isoNow(), privacy: .public)")
        switch action {
        case .primaryButtonPressed:
            recordPenaltyIfNeeded()
            let beforeCount = store.shield.applications?.count ?? -1
            store.shield.applications?.remove(application)
            let afterCount = store.shield.applications?.count ?? -1
            logger.notice("ShieldAction: removed app token. shield.applications count \(beforeCount) -> \(afterCount)")
            logStoreState(tag: "after remove app")
            startReshieldGraceWindow()
            logger.notice("ShieldAction: calling completionHandler(.none) for application")
            completionHandler(.none)
        case .secondaryButtonPressed:
            logger.notice("ShieldAction: calling completionHandler(.close) for application")
            completionHandler(.close)
        @unknown default:
            logger.notice("ShieldAction: @unknown action, calling completionHandler(.close) for application")
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logStoreState(tag: "before handle(webDomain)")
        logger.notice("ShieldAction action=\(String(describing: action), privacy: .public) target=webDomain now=\(Self.isoNow(), privacy: .public)")
        switch action {
        case .primaryButtonPressed:
            recordPenaltyIfNeeded()
            let beforeCount = store.shield.webDomains?.count ?? -1
            store.shield.webDomains?.remove(webDomain)
            let afterCount = store.shield.webDomains?.count ?? -1
            logger.notice("ShieldAction: removed web domain token. shield.webDomains count \(beforeCount) -> \(afterCount)")
            logStoreState(tag: "after remove webDomain")
            startReshieldGraceWindow()
            logger.notice("ShieldAction: calling completionHandler(.none) for webDomain")
            completionHandler(.none)
        case .secondaryButtonPressed:
            logger.notice("ShieldAction: calling completionHandler(.close) for webDomain")
            completionHandler(.close)
        @unknown default:
            logger.notice("ShieldAction: @unknown action, calling completionHandler(.close) for webDomain")
            completionHandler(.close)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        logStoreState(tag: "before handle(category)")
        logger.notice("ShieldAction action=\(String(describing: action), privacy: .public) target=category now=\(Self.isoNow(), privacy: .public)")
        switch action {
        case .primaryButtonPressed:
            recordPenaltyIfNeeded()
            // Category shields cover a group of apps; we can't remove a single
            // app token here, so the best we can do is clear the category
            // shield entirely for now. The monitor extension re-applies it
            // when the unblock `DeviceActivity` interval ends.
            store.shield.applicationCategories = nil
            logger.notice("ShieldAction: cleared shield.applicationCategories")
            logStoreState(tag: "after clear categories")
            startReshieldGraceWindow()
            logger.notice("ShieldAction: calling completionHandler(.none) for category")
            completionHandler(.none)
        case .secondaryButtonPressed:
            logger.notice("ShieldAction: calling completionHandler(.close) for category")
            completionHandler(.close)
        @unknown default:
            logger.notice("ShieldAction: @unknown action, calling completionHandler(.close) for category")
            completionHandler(.close)
        }
    }

    // MARK: - Scheduled reshield (DeviceActivity)

    /// Starts a one-shot `DeviceActivity` interval. When it ends,
    /// `DeviceActivityMonitorExtension.intervalDidEnd` re-applies the full
    /// shield from the persisted `FamilyActivitySelection`.
    private func startReshieldGraceWindow() {
        // Log all currently-running activities so we can tell if there's an
        // orphan or duplicate schedule that might be triggering an unexpected
        // `intervalDidStart` in the monitor extension.
        let existing = activityCenter.activities
        logger.notice("ShieldAction: existing DeviceActivityCenter activities=\(existing.map { $0.rawValue }, privacy: .public)")

        // Calling `stopMonitoring` on a running activity causes iOS to fire
        // `intervalDidEnd` in the monitor extension. Without coordination
        // that callback would reapply the persisted shield (treating it as
        // "grace window naturally expired") and undo the unblock we just
        // granted the user. Stamp a short suppression window in the shared
        // app group so the monitor knows to ignore the next grace-end that
        // fires within the next few seconds.
        let suppressUntil = Date().timeIntervalSince1970 + 10
        AppGroupDefaults.defaults.set(suppressUntil, forKey: AppGroupDefaults.Key.graceStopSuppressUntil)
        AppGroupDefaults.flush()
        logger.notice("ShieldAction: set graceStopSuppressUntil=\(suppressUntil, privacy: .public)")

        activityCenter.stopMonitoring([DeviceActivityMonitorNames.breakFocusGrace])
        logger.notice("ShieldAction: stopped any prior grace activity")

        let calendar = Calendar.current
        let now = Date()
        let windowEnd = now.addingTimeInterval(Self.reshieldIntervalSeconds)
        // Full Y-M-D h:m:s for `DeviceActivitySchedule` (reliable for same / next day).
        let startComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now
        )
        let endComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: windowEnd
        )
        let scheduleLengthSec = windowEnd.timeIntervalSince(now)
        logger.notice("ShieldAction: reshield via DeviceActivity in \(scheduleLengthSec, privacy: .public)s")

        // Same instant as the schedule end: main app uses this only to avoid
        // reapplying the full selection while the unblock is active (no timer).
        AppGroupDefaults.setGraceWindowEnd(windowEnd)
        AppGroupDefaults.flush()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logger.notice("ShieldAction: reshield at \(iso.string(from: windowEnd), privacy: .public)")

        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )

        do {
            try activityCenter.startMonitoring(
                DeviceActivityMonitorNames.breakFocusGrace,
                during: schedule
            )
            let afterActivities = activityCenter.activities
            logger.notice("ShieldAction: started re-shield grace DeviceActivity; activitiesAfterStart=\(afterActivities.map { $0.rawValue }, privacy: .public)")
        } catch {
            logger.error("ShieldAction: DeviceActivity start failed — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Logging helpers

    private func logStoreState(tag: String) {
        let appsCount = store.shield.applications?.count ?? -1
        let catsDescription = String(describing: store.shield.applicationCategories)
        let websCount = store.shield.webDomains?.count ?? -1
        let enabled = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled)
        logger.notice("ShieldAction store[\(tag, privacy: .public)] appsCount=\(appsCount) cats=\(catsDescription, privacy: .public) websCount=\(websCount) shieldEnabledFlag=\(enabled, privacy: .public)")
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    // MARK: - Penalty handling

    private func recordPenaltyIfNeeded() {
        let snapshot = AppGroupDefaults.loadSnapshot()
        let penaltyAmount = snapshot?.penaltyAmount ?? 100

        // Scheduled-tasks-only mode: the shield exists solely to guard active
        // focus windows, so only breaking an active scheduled task costs points.
        // Any pass-through outside a task (or with a stale snapshot) is free.
        if AppGroupDefaults.scheduledTasksOnlyMode {
            if let snapshot,
               snapshot.dayKey == ShieldSnapshot.dayKey(),
               let active = snapshot.activeTask() {
                AppGroupDefaults.appendPendingPenalty(
                    PendingPenalty(
                        amount: penaltyAmount,
                        reason: .clickedThroughDuringTask,
                        context: active.title
                    )
                )
            }
            return
        }

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
    }
}
