import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    private let store = ManagedSettingsStore(named: .init("YourDayShield"))

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        reapplyShieldFromPersistedSelection()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
    }

    private func reapplyShieldFromPersistedSelection() {
        let defaults = AppGroupDefaults.defaults
        guard defaults.bool(forKey: AppGroupDefaults.Key.shieldEnabled),
              let data = defaults.data(forKey: AppGroupDefaults.Key.familySelection),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            store.shield.applications = nil
            store.shield.applicationCategories = nil
            store.shield.webDomains = nil
            return
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        if selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = nil
        } else {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }
}
