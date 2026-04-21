import Foundation
import SwiftUI
import SwiftData
import Combine
import FamilyControls
import ManagedSettings
import DeviceActivity

@MainActor
final class ScreenTimeManager: ObservableObject {
    static let shared = ScreenTimeManager()

    static let activityName = DeviceActivityName("YourDayDailyBlock")
    private let store = ManagedSettingsStore(named: .init("YourDayShield"))
    private let activityCenter = DeviceActivityCenter()
    private let authCenter = AuthorizationCenter.shared

    @Published var authorizationStatus: AuthorizationStatus
    @Published var isEnabled: Bool
    @Published var selection: FamilyActivitySelection

    private var snapshotDebounceTask: Task<Void, Never>?

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
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        try await authCenter.requestAuthorization(for: .individual)
        self.authorizationStatus = authCenter.authorizationStatus
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
                return
            }
            guard authorizationStatus == .approved else {
                self.isEnabled = false
                AppGroupDefaults.defaults.set(false, forKey: AppGroupDefaults.Key.shieldEnabled)
                return
            }
            self.isEnabled = true
            AppGroupDefaults.defaults.set(true, forKey: AppGroupDefaults.Key.shieldEnabled)
            applyShieldIfNeeded()
            startDailyMonitoring()
        } else {
            self.isEnabled = false
            AppGroupDefaults.defaults.set(false, forKey: AppGroupDefaults.Key.shieldEnabled)
            clearShield()
            stopMonitoring()
        }
    }

    // MARK: - Selection

    func updateSelection(_ newSelection: FamilyActivitySelection) {
        self.selection = newSelection
        if let data = try? JSONEncoder().encode(newSelection) {
            AppGroupDefaults.defaults.set(data, forKey: AppGroupDefaults.Key.familySelection)
        }
        applyShieldIfNeeded()
    }

    // MARK: - Shield application

    func applyShieldIfNeeded() {
        guard isEnabled,
              authorizationStatus == .approved,
              !(selection.applicationTokens.isEmpty
                && selection.categoryTokens.isEmpty
                && selection.webDomainTokens.isEmpty) else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            store.shield.webDomainCategories = nil
            return
        }
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
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let descriptor = FetchDescriptor<TodoItem>(
            predicate: #Predicate<TodoItem> { item in
                item.dueDate >= today && item.dueDate < tomorrow
            }
        )
        let items = (try? context.fetch(descriptor)) ?? []
        let scheduled = items.filter { $0.manualScheduleGoogleEventId != nil }

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
