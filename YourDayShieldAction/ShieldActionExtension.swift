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

    /// How long the user is allowed off-focus before we restore the shield
    /// (app-side, using `AppGroupDefaults.graceWindowEndDate()`).
    private static let graceIntervalSeconds: TimeInterval = 120

    /// iOS refuses short `DeviceActivitySchedule` intervals — you'll see
    /// "The activity's schedule is too short" for 2 minutes. The system
    /// schedule must be at least this long; we still reapply at
    /// `graceIntervalSeconds` from the main app when the user opens YourDay
    /// (or in foreground) before this fires.
    private static let minimumDeviceActivityScheduleDuration: TimeInterval = 15 * 60

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
            // when the grace window interval ends.
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

    // MARK: - Re-shield grace window

    /// Starts a wall-clock `DeviceActivity` interval (no usage events). When
    /// it ends, `DeviceActivityMonitorExtension.intervalDidEnd` re-applies the
    /// full shield from the persisted `FamilyActivitySelection` so the next
    /// launch of a blocked app shows the shield again.
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
        let userFacingEnd = now.addingTimeInterval(Self.graceIntervalSeconds)
        let systemScheduleEnd = now.addingTimeInterval(
            max(Self.graceIntervalSeconds, Self.minimumDeviceActivityScheduleDuration)
        )
        // Full Y-M-D h:m:s for `DeviceActivitySchedule` (reliable for same / next day).
        let startComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: now
        )
        let endComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: systemScheduleEnd
        )
        let scheduleLengthSec = systemScheduleEnd.timeIntervalSince(now)
        logger.notice("ShieldAction: user-facing grace end in \(Self.graceIntervalSeconds, privacy: .public)s; system DA schedule length \(scheduleLengthSec, privacy: .public)s (iOS min ~15m)")

        // Always record wall-clock for main-app reapply, even if DeviceActivity fails.
        AppGroupDefaults.setGraceWindowEnd(userFacingEnd)
        AppGroupDefaults.flush()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        logger.notice("ShieldAction: grace reapply (user clock) at \(iso.string(from: userFacingEnd), privacy: .public) — main app enforces; system interval ends at \(iso.string(from: systemScheduleEnd), privacy: .public)")

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
            logger.error("ShieldAction: DeviceActivity start failed — \(error.localizedDescription, privacy: .public). Main app will still reapply at user-facing time above.")
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
