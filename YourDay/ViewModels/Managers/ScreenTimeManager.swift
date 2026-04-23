import Foundation
import SwiftUI
import SwiftData
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity
import OSLog

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    static let activityName = DeviceActivityName("YourDayDailyBlock")
    /// Must match `DeviceActivityMonitorNames.breakFocusGrace` in extensions.
    private static let breakFocusGraceActivity = DeviceActivityName("YourDayBreakFocusGrace")
    private let logger = Logger(subsystem: "com.yourday.app", category: "ScreenTimeManager")
    private let store = ManagedSettingsStore(named: .init("YourDayShield"))
    private let activityCenter = DeviceActivityCenter()
    private let authCenter = AuthorizationCenter.shared

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date())
    }

    @Published var authorizationStatus: AuthorizationStatus
    @Published var isEnabled: Bool
    @Published var selection: FamilyActivitySelection

    private var snapshotDebounceTask: Task<Void, Never>?
    private var graceCountdownLogTimer: Timer?
    private let graceCountdownLogger = Logger(subsystem: "com.yourday.app", category: "BreakFocusGrace")

    /// `Logger` + `print` so you always see lines in the Xcode console (filter `GRACE` or `BreakFocusGrace`).
    private func graceSanityLog(_ message: String) {
        graceCountdownLogger.notice("\(message, privacy: .public)")
        print("[YourDay][GRACE] \(message)")
    }

    private func invalidateGraceCountdownTimerSilently() {
        graceCountdownLogTimer?.invalidate()
        graceCountdownLogTimer = nil
    }

    private init() {
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        self.isEnabled = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled)
        if let data = AppGroupDefaults.defaults.data(forKey: AppGroupDefaults.Key.familySelection),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = decoded
        } else {
            self.selection = FamilyActivitySelection()
        }
    }

    // MARK: - Lifecycle

    func loadPersistedState() {
        self.authorizationStatus = authCenter.authorizationStatus
        self.isEnabled = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled)
        if let data = AppGroupDefaults.defaults.data(forKey: AppGroupDefaults.Key.familySelection),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = decoded
        }
        reapplyIfUserGraceWindowElapsedByWallClock()
        startGraceCountdownLoggingIfNeeded()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        try await authCenter.requestAuthorization(for: .individual)
        self.authorizationStatus = authCenter.authorizationStatus
    }

    /// On a cold launch `AuthorizationCenter.authorizationStatus` sometimes
    /// returns `.notDetermined` even when the user has previously granted
    /// authorization — the framework hasn't re-hydrated its cached value yet.
    /// Silently calling `requestAuthorization(for:)` on the same scope does
    /// **not** re-prompt the user once authorization has been granted; it just
    /// resolves to the real status. We use this to reconcile the cached
    /// status on startup and on foregrounding. If the persisted shield flag
    /// is on and authorization resolves to `.approved`, we (re)apply the
    /// shield and restart monitoring so protection resumes without the user
    /// having to toggle the switch.
    func refreshAuthorizationAndReapplyShieldIfNeeded() async {
        logger.notice("ScreenTimeManager refreshAuthorizationAndReapplyShieldIfNeeded ENTER now=\(Self.isoNow(), privacy: .public) isEnabled=\(self.isEnabled, privacy: .public)")
        do {
            try await authCenter.requestAuthorization(for: .individual)
        } catch {
            print("ScreenTimeManager: refresh auth failed — \(error.localizedDescription)")
            logger.error("ScreenTimeManager refresh auth failed: \(error.localizedDescription, privacy: .public)")
        }
        self.authorizationStatus = authCenter.authorizationStatus
        logger.notice("ScreenTimeManager auth status=\(String(describing: self.authorizationStatus), privacy: .public)")

        reapplyIfUserGraceWindowElapsedByWallClock()

        if isEnabled {
            if authorizationStatus == .approved {
                logger.notice("ScreenTimeManager refresh: isEnabled && approved → applyShieldIfNeeded + startDailyMonitoring")
                applyShieldIfNeeded()
                startDailyMonitoring()
            } else {
                // Authorization was revoked outside of the app (e.g. in iOS
                // Settings). Clear the shield so we don't leave stale rules
                // in place, but keep `isEnabled == true` so the UI can
                // surface the "authorization required" banner and the user
                // can re-grant without re-toggling from scratch.
                logger.notice("ScreenTimeManager refresh: not approved → clearShield + stopMonitoring")
                clearShield()
                stopMonitoring()
            }
        } else {
            logger.notice("ScreenTimeManager refresh: isEnabled=false, noop")
        }
        startGraceCountdownLoggingIfNeeded()
    }

    // MARK: - Break-focus grace (countdown + wall-clock re-shield in main app)

    /// `ShieldAction` stores `AppGroupDefaults.graceWindowEndDate()` at user tap. When that
    /// time is past (and this process runs — foreground / launch), restore the full shield.
    /// This is the only way to reapply at a short (e.g. 2m) “product” window; `DeviceActivity`
    /// enforces a longer minimum schedule for `intervalDidEnd` callbacks.
    func reapplyIfUserGraceWindowElapsedByWallClock() {
        guard isEnabled,
              authorizationStatus == .approved,
              !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty,
              let end = AppGroupDefaults.graceWindowEndDate(),
              end <= Date() else { return }

        logger.notice("ScreenTimeManager reapplyIfUserGraceWindowElapsed: restoring shield (user grace clock expired) now=\(Self.isoNow(), privacy: .public)")
        applyShieldIfNeeded(ignoringBreakFocusGrace: true)
        AppGroupDefaults.clearGraceWindowEnd()
        let suppressUntil = Date().timeIntervalSince1970 + 10
        AppGroupDefaults.defaults.set(suppressUntil, forKey: AppGroupDefaults.Key.graceStopSuppressUntil)
        AppGroupDefaults.flush()
        activityCenter.stopMonitoring([Self.breakFocusGraceActivity])
    }

    /// 1s `Logger` + `print` while a grace window is active (`AppGroupDefaults.graceWindowEndDate()`).
    /// Only ticks while **YourDay is in the foreground**; on background we pause the ticker (wall clock still runs).
    func startGraceCountdownLoggingIfNeeded() {
        invalidateGraceCountdownTimerSilently()
        reapplyIfUserGraceWindowElapsedByWallClock()
        guard let end = AppGroupDefaults.graceWindowEndDate(), end > Date() else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let totalSec = max(0, Int(end.timeIntervalSinceNow.rounded(.down)))
        graceSanityLog("▶︎ START — 1s ticks | user-clock reshield at \(iso.string(from: end)) | ~\(totalSec)s left | Xcode: filter [YourDay][GRACE] or subsystem BreakFocusGrace")

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.logGraceCountdownTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        graceCountdownLogTimer = timer
        logGraceCountdownTick()
    }

    /// Call when the app backgrounds; timer pauses. Resumes when `startGraceCountdownLoggingIfNeeded` runs again on become-active.
    func stopGraceCountdownLogging() {
        if graceCountdownLogTimer != nil {
            graceSanityLog("⏸ PAUSED — YourDay left foreground; ticks stop until next active (reshield time unchanged)")
        }
        invalidateGraceCountdownTimerSilently()
    }

    private func logGraceCountdownTick() {
        guard let end = AppGroupDefaults.graceWindowEndDate() else {
            graceSanityLog("⏹ STOP — grace key was cleared; timer off")
            invalidateGraceCountdownTimerSilently()
            return
        }
        let rem = end.timeIntervalSinceNow
        if rem <= 0 {
            graceSanityLog("⏰ EXPIRED (0s) — reapplying full shield from main app (user clock)")
            reapplyIfUserGraceWindowElapsedByWallClock()
            invalidateGraceCountdownTimerSilently()
            return
        }
        let totalSec = Int(rem.rounded(.down))
        let m = totalSec / 60
        let s = totalSec % 60
        let mmss = String(format: "%d:%02d", m, s)
        graceSanityLog("⏱ tick \(mmss) (\(totalSec) seconds left) until user-clock reshield")
    }

    // MARK: - Toggle

    func setEnabled(_ enabled: Bool) async {
        if enabled {
            do {
                try await requestAuthorization()
            } catch {
                print("ScreenTimeManager: authorization failed — \(error.localizedDescription)")
                self.isEnabled = false
                AppGroupDefaults.defaults.set(false, forKey: AppGroupDefaults.Key.shieldEnabled)
                AppGroupDefaults.flush()
                return
            }
            guard authorizationStatus == .approved else {
                self.isEnabled = false
                AppGroupDefaults.defaults.set(false, forKey: AppGroupDefaults.Key.shieldEnabled)
                AppGroupDefaults.flush()
                return
            }
            self.isEnabled = true
            AppGroupDefaults.defaults.set(true, forKey: AppGroupDefaults.Key.shieldEnabled)
            // Force-flush immediately so a subsequent force-quit can't drop
            // the write and leave the toggle appearing "off" on next launch.
            AppGroupDefaults.flush()
            AppGroupDefaults.clearGraceWindowEnd()
            applyShieldIfNeeded(ignoringBreakFocusGrace: true)
            startDailyMonitoring()
        } else {
            self.isEnabled = false
            AppGroupDefaults.defaults.set(false, forKey: AppGroupDefaults.Key.shieldEnabled)
            AppGroupDefaults.flush()
            clearShield()
            stopMonitoring()
        }
    }

    // MARK: - Selection

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        self.selection = newSelection
        if let data = try? JSONEncoder().encode(newSelection) {
            AppGroupDefaults.defaults.set(data, forKey: AppGroupDefaults.Key.familySelection)
            AppGroupDefaults.flush()
        }
        applyShieldIfNeeded(ignoringBreakFocusGrace: true)
    }

    // MARK: - Shield application

    /// - Parameter ignoringBreakFocusGrace: Pass `true` when the user just toggled the shield, changed selection, or
    ///   after the user’s grace end time. While break-focus grace is active (short wall-clock from shield tap), we
    ///   skip reapplying the full selection so foregrounding the main app does not **undo** the extension’s token removal.
    func applyShieldIfNeeded(ignoringBreakFocusGrace: Bool = false) {
        if !ignoringBreakFocusGrace,
           let gEnd = AppGroupDefaults.graceWindowEndDate(), gEnd > Date() {
            logger.notice("ScreenTimeManager applyShieldIfNeeded: skipped (break-focus grace active until app-group wall clock)")
            return
        }
        logger.notice("ScreenTimeManager applyShieldIfNeeded now=\(Self.isoNow(), privacy: .public) isEnabled=\(self.isEnabled, privacy: .public) auth=\(String(describing: self.authorizationStatus), privacy: .public) selection apps=\(self.selection.applicationTokens.count) cats=\(self.selection.categoryTokens.count) webs=\(self.selection.webDomainTokens.count)")

        guard isEnabled,
              authorizationStatus == .approved,
              !(selection.applicationTokens.isEmpty
                && selection.categoryTokens.isEmpty
                && selection.webDomainTokens.isEmpty) else {
            logger.notice("ScreenTimeManager applyShieldIfNeeded: guard failed → clearing shield")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }
        logger.notice("ScreenTimeManager applyShieldIfNeeded: applying full selection to store")
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
        if selection.webDomainTokens.isEmpty {
            store.shield.webDomains = nil
        } else {
            store.shield.webDomains = selection.webDomainTokens
        }
    }

    func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
    }

    // MARK: - Device Activity monitoring

    func startDailyMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            try activityCenter.startMonitoring(Self.activityName, during: schedule)
        } catch {
            print("ScreenTimeManager: startMonitoring failed — \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        activityCenter.stopMonitoring([Self.activityName])
    }

    // MARK: - Snapshot

    func scheduleSnapshotRefresh(context: ModelContext) {
        snapshotDebounceTask?.cancel()
        snapshotDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            await self?.writeSnapshotFromCurrentTasks(context: context)
        }
    }

    func flushPendingSnapshotWrites(context: ModelContext) {
        snapshotDebounceTask?.cancel()
        snapshotDebounceTask = nil
        Task { await writeSnapshotFromCurrentTasks(context: context) }
    }

    func writeSnapshotFromCurrentTasks(context: ModelContext) async {
        let descriptor = FetchDescriptor<TodoItem>()
        let items = (try? context.fetch(descriptor)) ?? []
        let todayListItems = items.filter { $0.origin == .today }
        let scheduled = todayListItems.filter { $0.manualScheduleGoogleEventId != nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        print("ScreenTimeManager: snapshot build todayCount=\(todayListItems.count) scheduledCount=\(scheduled.count)")
        for (idx, item) in scheduled.enumerated() {
            let startStr = item.scheduledStartTime.map { isoFormatter.string(from: $0) } ?? "nil"
            let endStr = item.scheduledEndTime.map { isoFormatter.string(from: $0) } ?? "nil"
            let evt = item.manualScheduleGoogleEventId ?? "nil"
            print("ScreenTimeManager: task[\(idx)] title=\(item.title) isDone=\(item.isDone) start=\(startStr) end=\(endStr) evt=\(evt)")
        }

        let briefs: [ScheduledTaskBrief] = scheduled.map {
            ScheduledTaskBrief(
                title: $0.title,
                startTime: $0.scheduledStartTime,
                endTime: $0.scheduledEndTime,
                isDone: $0.isDone
            )
        }
        let completedCount = scheduled.filter { $0.isDone }.count
        let hasPlanned = scheduled.contains { !$0.isDone }

        let statsDescriptor = FetchDescriptor<PlayerStats>()
        let playerStats = (try? context.fetch(statsDescriptor))?.first
        let gardenValue = playerStats?.gardenValue ?? 100
        let penalty = max(100, Int((gardenValue * 0.10).rounded(.down)))

        let snapshot = ShieldSnapshot(
            dayKey: ShieldSnapshot.dayKey(),
            hasPlannedDay: hasPlanned,
            scheduledTasks: briefs,
            completedCount: completedCount,
            totalScheduledCount: scheduled.count,
            penaltyAmount: penalty,
            updatedAt: Date()
        )
        AppGroupDefaults.saveSnapshot(snapshot)
    }
}
