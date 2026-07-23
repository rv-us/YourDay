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
    /// Must match `DeviceActivityMonitorNames.breakFocusGrace` in extensions; stop when forcing full shield from the app.
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
    /// When `true`, apps are only shielded during an active scheduled focus task.
    @Published var scheduledTasksOnly: Bool

    private var snapshotDebounceTask: Task<Void, Never>?

    private init() {
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        self.isEnabled = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled)
        self.scheduledTasksOnly = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.scheduledTasksOnly)
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
        self.scheduledTasksOnly = AppGroupDefaults.defaults.bool(forKey: AppGroupDefaults.Key.scheduledTasksOnly)
        if let data = AppGroupDefaults.defaults.data(forKey: AppGroupDefaults.Key.familySelection),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            self.selection = decoded
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        try await authCenter.requestAuthorization(for: .individual)
        self.authorizationStatus = authCenter.authorizationStatus
    }

    /// Reconciles Screen Time authorization on startup and foregrounding.
    /// Only calls `requestAuthorization` when focus blocking is enabled and
    /// status is `.notDetermined` (including stale cache on cold launch).
    /// Never re-prompts after `.denied` — the user must grant access in iOS Settings.
    func refreshAuthorizationAndReapplyShieldIfNeeded() async {
        logger.notice("ScreenTimeManager refreshAuthorizationAndReapplyShieldIfNeeded ENTER now=\(Self.isoNow(), privacy: .public) isEnabled=\(self.isEnabled, privacy: .public)")

        guard isEnabled else {
            authorizationStatus = authCenter.authorizationStatus
            logger.notice("ScreenTimeManager refresh: isEnabled=false, noop")
            return
        }

        authorizationStatus = authCenter.authorizationStatus
        logger.notice("ScreenTimeManager auth status=\(String(describing: self.authorizationStatus), privacy: .public)")

        if authorizationStatus == .denied {
            logger.notice("ScreenTimeManager refresh: denied → clearShield + stopMonitoring (no re-prompt)")
            clearShield()
            stopMonitoring()
            return
        }

        if authorizationStatus == .notDetermined {
            do {
                try await authCenter.requestAuthorization(for: .individual)
            } catch {
                print("ScreenTimeManager: refresh auth failed — \(error.localizedDescription)")
                logger.error("ScreenTimeManager refresh auth failed: \(error.localizedDescription, privacy: .public)")
            }
            authorizationStatus = authCenter.authorizationStatus
            logger.notice("ScreenTimeManager auth status after request=\(String(describing: self.authorizationStatus), privacy: .public)")
        }

        if authorizationStatus == .approved {
            logger.notice("ScreenTimeManager refresh: isEnabled && approved → applyShieldIfNeeded + startDailyMonitoring")
            applyShieldIfNeeded()
            startDailyMonitoring()
        } else {
            // Authorization was revoked or not granted. Clear the shield but keep
            // `isEnabled == true` so Settings can show the authorization banner.
            logger.notice("ScreenTimeManager refresh: not approved → clearShield + stopMonitoring")
            clearShield()
            stopMonitoring()
        }
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

    /// Toggles whether the shield is limited to active scheduled focus windows.
    /// Persists immediately and re-evaluates the shield under the new rule so
    /// tokens are cleared (or re-applied) without waiting for the next snapshot.
    func setScheduledTasksOnly(_ on: Bool) {
        self.scheduledTasksOnly = on
        AppGroupDefaults.defaults.set(on, forKey: AppGroupDefaults.Key.scheduledTasksOnly)
        AppGroupDefaults.flush()
        applyShieldIfNeeded(ignoringBreakFocusGrace: true)
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

    /// - Parameter ignoringBreakFocusGrace: Pass `true` when forcing full shield from the app (toggle, selection change).
    ///   While an unblock is active (after shield tap), we skip reapplying so foregrounding YourDay does not undo
    ///   token removal until `DeviceActivityMonitor` reshields at interval end.
    func applyShieldIfNeeded(ignoringBreakFocusGrace: Bool = false) {
        if !ignoringBreakFocusGrace,
           let gEnd = AppGroupDefaults.graceWindowEndDate(), gEnd > Date() {
            logger.notice("ScreenTimeManager applyShieldIfNeeded: skipped (unblock active until scheduled reshield)")
            return
        }
        logger.notice("ScreenTimeManager applyShieldIfNeeded now=\(Self.isoNow(), privacy: .public) isEnabled=\(self.isEnabled, privacy: .public) auth=\(String(describing: self.authorizationStatus), privacy: .public) selection apps=\(self.selection.applicationTokens.count) cats=\(self.selection.categoryTokens.count) webs=\(self.selection.webDomainTokens.count)")

        guard isEnabled,
              authorizationStatus == .approved,
              AppGroupDefaults.shouldApplyShieldBlocks(),
              !(selection.applicationTokens.isEmpty
                && selection.categoryTokens.isEmpty
                && selection.webDomainTokens.isEmpty) else {
            logger.notice("ScreenTimeManager applyShieldIfNeeded: guard failed → clearing shield")
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            if ignoringBreakFocusGrace { endBreakFocusUnblockTracking() }
            return
        }
        if ignoringBreakFocusGrace { endBreakFocusUnblockTracking() }
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

    private func endBreakFocusUnblockTracking() {
        AppGroupDefaults.clearGraceWindowEnd()
        AppGroupDefaults.flush()
        activityCenter.stopMonitoring([Self.breakFocusGraceActivity])
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
        activityCenter.stopMonitoring([Self.activityName, Self.breakFocusGraceActivity])
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
        let calendarScheduled = todayListItems.filter { $0.manualScheduleGoogleEventId != nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        print("ScreenTimeManager: snapshot build todayCount=\(todayListItems.count) calendarScheduledCount=\(calendarScheduled.count)")
        for (idx, item) in todayListItems.enumerated() {
            let startStr = item.scheduledStartTime.map { isoFormatter.string(from: $0) } ?? "nil"
            let endStr = item.scheduledEndTime.map { isoFormatter.string(from: $0) } ?? "nil"
            let evt = item.manualScheduleGoogleEventId ?? "nil"
            print("ScreenTimeManager: task[\(idx)] title=\(item.title) isDone=\(item.isDone) start=\(startStr) end=\(endStr) evt=\(evt)")
        }

        let briefs: [ScheduledTaskBrief] = todayListItems.map { item in
            let onCalendar = item.manualScheduleGoogleEventId != nil
            return ScheduledTaskBrief(
                title: item.title,
                startTime: onCalendar ? item.scheduledStartTime : nil,
                endTime: onCalendar ? item.scheduledEndTime : nil,
                isDone: item.isDone,
                isCalendarScheduled: onCalendar
            )
        }
        let completedCount = todayListItems.filter { $0.isDone }.count
        let openCount = todayListItems.count - completedCount
        let hasPlanned = openCount > 0
        let dayKey = ShieldSnapshot.dayKey()

        if openCount == 0, completedCount > 0 || !todayListItems.isEmpty {
            AppGroupDefaults.markTodayPlanningFulfilled(dayKey: dayKey)
        }

        let shouldBlockApps: Bool
        if openCount > 0 {
            shouldBlockApps = true
        } else if completedCount > 0 || !todayListItems.isEmpty {
            shouldBlockApps = false
        } else {
            shouldBlockApps = !AppGroupDefaults.isTodayPlanningFulfilled(dayKey: dayKey)
        }

        let statsDescriptor = FetchDescriptor<PlayerStats>()
        let playerStats = (try? context.fetch(statsDescriptor))?.first
        let gardenValue = playerStats?.gardenValue ?? 100
        let penalty = max(100, Int((gardenValue * 0.10).rounded(.down)))

        let snapshot = ShieldSnapshot(
            dayKey: dayKey,
            hasPlannedDay: hasPlanned,
            shouldBlockApps: shouldBlockApps,
            scheduledTasks: briefs,
            completedCount: completedCount,
            totalScheduledCount: todayListItems.count,
            penaltyAmount: penalty,
            updatedAt: Date()
        )
        AppGroupDefaults.saveSnapshot(snapshot)
        AppGroupDefaults.flush()

        if isEnabled, authorizationStatus == .approved {
            // Read-time gate: honors scheduled-tasks-only mode by checking for an
            // active scheduled task against the snapshot we just persisted.
            if AppGroupDefaults.shouldApplyShieldBlocks() {
                applyShieldIfNeeded()
            } else {
                logger.notice("ScreenTimeManager: shield not needed (day fulfilled or outside a scheduled task) — clearing shield")
                clearShield()
                endBreakFocusUnblockTracking()
            }
        }
    }
}
