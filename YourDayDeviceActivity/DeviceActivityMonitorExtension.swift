import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation
import OSLog

/// Shared names used across the main app, the shield-action extension and
/// this monitor extension so they all agree on which `DeviceActivity` the
/// break-focus grace window is keyed under.
enum DeviceActivityMonitorNames {
    static let breakFocusGrace = DeviceActivityName("YourDayBreakFocusGrace")
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let logger = Logger(subsystem: "com.yourday.app", category: "DeviceActivityMonitor")
    private let store = ManagedSettingsStore(named: .init("YourDayShield"))
    private let activityCenter = DeviceActivityCenter()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.notice("DAMonitor intervalDidStart activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier)")
        logStoreState(tag: "intervalDidStart[\(activity.rawValue)] before")

        // IMPORTANT: do NOT reapply the shield for the break-focus grace
        // activity here. iOS fires `intervalDidStart` synchronously the first
        // time we call `startMonitoring` (because the schedule already covers
        // "now"), so reapplying here would instantly undo the unblock the
        // user just earned by pressing "Continue anyway". The grace window
        // only ends reshielding on `intervalDidEnd` (wall-clock timer from tap).
        guard activity != DeviceActivityMonitorNames.breakFocusGrace else {
            logger.notice("DAMonitor intervalDidStart: break-focus interval started (skipping reapply; reshield on intervalDidEnd)")
            return
        }

        logger.notice("DAMonitor intervalDidStart: reapplying shield for activity=\(activity.rawValue, privacy: .public)")
        reapplyShieldFromPersistedSelection(reason: "intervalDidStart[\(activity.rawValue)]")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.notice("DAMonitor intervalDidEnd activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public)")
        logStoreState(tag: "intervalDidEnd[\(activity.rawValue)] before")

        if activity == DeviceActivityMonitorNames.breakFocusGrace {
            // If the shield-action extension just called `stopMonitoring` to
            // restart the grace window, iOS delivers that here as an
            // `intervalDidEnd`. We must NOT reapply the shield in that case
            // — doing so instantly undoes the unblock the user just earned.
            let suppressUntil = AppGroupDefaults.defaults.double(forKey: AppGroupDefaults.Key.graceStopSuppressUntil)
            let nowTs = Date().timeIntervalSince1970
            if suppressUntil > 0 && nowTs < suppressUntil {
                logger.notice("DAMonitor intervalDidEnd: SUPPRESSED grace-end reshield (suppressUntil=\(suppressUntil, privacy: .public) now=\(nowTs, privacy: .public))")
                AppGroupDefaults.defaults.removeObject(forKey: AppGroupDefaults.Key.graceStopSuppressUntil)
                AppGroupDefaults.flush()
                return
            }

            if AppGroupDefaults.graceWindowEndDate() == nil {
                logger.notice("DAMonitor intervalDidEnd: unblock tracking already cleared; stopping activity only")
                activityCenter.stopMonitoring([DeviceActivityMonitorNames.breakFocusGrace])
                return
            }

            logger.notice("DAMonitor intervalDidEnd: unblock interval ended, reapplying shield")
            reapplyShieldFromPersistedSelection(reason: "graceIntervalDidEnd")
            AppGroupDefaults.clearGraceWindowEnd()
            AppGroupDefaults.flush()
            activityCenter.stopMonitoring([DeviceActivityMonitorNames.breakFocusGrace])
            logger.notice("DAMonitor intervalDidEnd: stopped grace activity")
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.notice("DAMonitor eventDidReachThreshold event=\(event.rawValue, privacy: .public) activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public)")
        logStoreState(tag: "eventDidReachThreshold[\(activity.rawValue)/\(event.rawValue)] before")
        // Break-focus grace uses schedule-only monitoring (no threshold events).
        logger.notice("DAMonitor eventDidReachThreshold: ignoring (grace is wall-clock only)")
    }

    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        logger.notice("DAMonitor intervalWillStartWarning activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public)")
    }

    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        logger.notice("DAMonitor intervalWillEndWarning activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public)")
    }

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        logger.notice("DAMonitor eventWillReachThresholdWarning event=\(event.rawValue, privacy: .public) activity=\(activity.rawValue, privacy: .public) now=\(Self.isoNow(), privacy: .public)")
    }

    // MARK: - Shield reapplication

    private func reapplyShieldFromPersistedSelection(reason: String) {
        let defaults = AppGroupDefaults.defaults
        let enabled = defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled)
        let hasData = defaults.data(forKey: AppGroupDefaults.Key.familySelection) != nil
        logger.notice("DAMonitor reapplyShield[reason=\(reason, privacy: .public)] enabled=\(enabled, privacy: .public) hasSelectionData=\(hasData, privacy: .public)")

        guard enabled,
              AppGroupDefaults.shouldApplyShieldBlocks(),
              let data = defaults.data(forKey: AppGroupDefaults.Key.familySelection),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            logger.notice("DAMonitor reapplyShield: clearing shield (disabled, day fulfilled, or no selection)")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            logStoreState(tag: "after clear")
            return
        }

        let appsBefore = store.shield.applications?.count ?? -1
        let websBefore = store.shield.webDomains?.count ?? -1
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        let appsAfter = store.shield.applications?.count ?? -1
        let websAfter = store.shield.webDomains?.count ?? -1
        logger.notice("DAMonitor reapplyShield: applied. apps \(appsBefore)->\(appsAfter) webs \(websBefore)->\(websAfter) selectionApps=\(selection.applicationTokens.count) selectionCats=\(selection.categoryTokens.count) selectionWebs=\(selection.webDomainTokens.count)")
    }

    // MARK: - Logging helpers

    private func logStoreState(tag: String) {
        let appsCount = store.shield.applications?.count ?? -1
        let catsDescription = String(describing: store.shield.applicationCategories)
        let websCount = store.shield.webDomains?.count ?? -1
        logger.notice("DAMonitor store[\(tag, privacy: .public)] appsCount=\(appsCount) cats=\(catsDescription, privacy: .public) websCount=\(websCount)")
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }
}
