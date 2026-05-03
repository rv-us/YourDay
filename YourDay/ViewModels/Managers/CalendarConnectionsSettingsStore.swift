//
//  CalendarConnectionsSettingsStore.swift
//  YourDay
//
//  Non-secret calendar visibility preferences per Google identity (UserDefaults JSON).
//

import Foundation
import Combine

enum StoredCalendarAccountKind: String, Codable, Equatable {
    /// Main app Google Sign-In user (writes use this account).
    case primaryGID
    /// Additional account linked via OAuth (read-only).
    case linkedReadOnly
}

struct StoredCalendarAccountPreferences: Codable, Identifiable, Equatable {
    var accountKey: String
    var accountKind: StoredCalendarAccountKind
    var email: String?
    /// `nil` means “show all readable calendars” from calendarList until user customizes toggles.
    var enabledCalendarIds: [String]?

    var id: String { accountKey }

    /// Label for Connections and errors; avoids showing raw numeric `sub` for linked accounts when email is unknown.
    var connectionsDisplayTitle: String {
        if let e = email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
            return e
        }
        if accountKind == .linkedReadOnly {
            return "Google account"
        }
        return accountKey
    }
}

struct CalendarConnectionsRoot: Codable, Equatable {
    var perAccount: [StoredCalendarAccountPreferences]

    static let empty = CalendarConnectionsRoot(perAccount: [])
}

@MainActor
final class CalendarConnectionsSettingsStore: ObservableObject {
    static let shared = CalendarConnectionsSettingsStore()

    private let defaultsKey = "calendarConnectionsSettings.v1"

    @Published private(set) var root: CalendarConnectionsRoot

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(CalendarConnectionsRoot.self, from: data) {
            root = decoded
            let linked = decoded.perAccount.filter { $0.accountKind == .linkedReadOnly }.count
            print("[CalendarConnections] Store: init loaded from UserDefaults accounts=\(decoded.perAccount.count) linked=\(linked) bytes=\(data.count)")
        } else {
            root = .empty
            print("[CalendarConnections] Store: init empty (no saved settings)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(root)
            UserDefaults.standard.set(data, forKey: defaultsKey)
            let linked = root.perAccount.filter { $0.accountKind == .linkedReadOnly }.count
            print("[CalendarConnections] Store: persist OK bytes=\(data.count) totalAccounts=\(root.perAccount.count) linked=\(linked)")
        } catch {
            print("[CalendarConnections] Store: persist FAIL \(error.localizedDescription)")
            assertionFailure("CalendarConnectionsSettingsStore: failed to encode settings: \(error)")
        }
        objectWillChange.send()
    }

    /// Replaces `root` so `@Published` reliably notifies SwiftUI after in-place mutations.
    private func replaceRootPerAccount(_ accounts: [StoredCalendarAccountPreferences]) {
        let linked = accounts.filter { $0.accountKind == .linkedReadOnly }.map(\.accountKey)
        print("[CalendarConnections] Store: replaceRootPerAccount total=\(accounts.count) linkedKeys=\(linked)")
        root = CalendarConnectionsRoot(perAccount: accounts)
        persist()
    }

    func preferences(forAccountKey accountKey: String) -> StoredCalendarAccountPreferences? {
        root.perAccount.first { $0.accountKey == accountKey }
    }

    /// Returns explicit calendar id list, or `nil` meaning “all readable calendars from API”.
    func enabledCalendarIds(forAccountKey accountKey: String) -> [String]? {
        preferences(forAccountKey: accountKey)?.enabledCalendarIds
    }

    func setEnabledCalendarIds(_ ids: [String]?, forAccountKey accountKey: String) {
        guard let index = root.perAccount.firstIndex(where: { $0.accountKey == accountKey }) else { return }
        var accounts = root.perAccount
        accounts[index].enabledCalendarIds = ids
        replaceRootPerAccount(accounts)
    }

    /// Toggle one calendar; `nil` enabled list means “all readable”; when selection matches all ids again, clears to `nil`.
    func applyCalendarToggle(accountKey: String, calendarId: String, isOn: Bool, allReadableCalendarIds: [String]) {
        guard let index = root.perAccount.firstIndex(where: { $0.accountKey == accountKey }) else { return }
        var accounts = root.perAccount
        let all = Set(allReadableCalendarIds)
        var chosen: Set<String>
        if let existing = accounts[index].enabledCalendarIds {
            chosen = Set(existing)
        } else {
            chosen = all
        }
        if isOn {
            chosen.insert(calendarId)
        } else {
            chosen.remove(calendarId)
        }
        if chosen == all {
            accounts[index].enabledCalendarIds = nil
        } else {
            accounts[index].enabledCalendarIds = Array(chosen)
        }
        replaceRootPerAccount(accounts)
    }

    func isCalendarEnabled(accountKey: String, calendarId: String, allReadableCalendarIds: [String]) -> Bool {
        guard let prefs = preferences(forAccountKey: accountKey) else { return true }
        guard let explicit = prefs.enabledCalendarIds else { return true }
        if explicit.isEmpty { return false }
        return explicit.contains(calendarId)
    }

    func upsertPrimaryGIDAccount(accountKey: String, email: String?) {
        guard !accountKey.isEmpty else { return }
        print("[CalendarConnections] Store: upsertPrimaryGIDAccount key=\(accountKey) email=\(email ?? "nil")")
        var accounts = root.perAccount
        if let index = accounts.firstIndex(where: { $0.accountKey == accountKey }) {
            accounts[index].email = email
            accounts[index].accountKind = .primaryGID
        } else {
            accounts.append(
                StoredCalendarAccountPreferences(
                    accountKey: accountKey,
                    accountKind: .primaryGID,
                    email: email,
                    enabledCalendarIds: nil
                )
            )
        }
        replaceRootPerAccount(accounts)
    }

    func upsertLinkedAccount(accountKey: String, email: String?) {
        print("[CalendarConnections] Store: upsertLinkedAccount key=\(accountKey) email=\(email ?? "nil")")
        var accounts = root.perAccount
        if let index = accounts.firstIndex(where: { $0.accountKey == accountKey }) {
            if accounts[index].accountKind == .primaryGID {
                print("[CalendarConnections] Store: upsertLinkedAccount SKIP same key already primaryGID")
                return
            }
            accounts[index].accountKind = .linkedReadOnly
            if let email { accounts[index].email = email }
        } else {
            accounts.append(
                StoredCalendarAccountPreferences(
                    accountKey: accountKey,
                    accountKind: .linkedReadOnly,
                    email: email,
                    enabledCalendarIds: nil
                )
            )
        }
        replaceRootPerAccount(accounts)
    }

    func removeLinkedAccount(accountKey: String) {
        print("[CalendarConnections] Store: removeLinkedAccount key=\(accountKey)")
        let accounts = root.perAccount.filter { !($0.accountKey == accountKey && $0.accountKind == .linkedReadOnly) }
        replaceRootPerAccount(accounts)
    }

    func reloadFromDefaults() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(CalendarConnectionsRoot.self, from: data) {
            root = decoded
        } else {
            root = .empty
        }
        objectWillChange.send()
    }

    var linkedReadOnlyAccounts: [StoredCalendarAccountPreferences] {
        root.perAccount.filter { $0.accountKind == .linkedReadOnly }
    }
}
