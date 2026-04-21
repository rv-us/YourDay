import Foundation

enum AppGroupDefaults {
    static let suiteName = "group.Yourday.dev.screentime"

    enum Key {
        static let shieldSnapshot = "shieldSnapshot.v1"
        static let pendingPenalties = "pendingFocusPenalties.v1"
        static let shieldEnabled = "screenTimeShieldEnabled"
        static let familySelection = "screenTimeFamilySelection"
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
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
}
