//
//  TrelloConnectionsSettingsStore.swift
//  YourDay
//

import Foundation
import Combine

struct TrelloConnectionsRoot: Codable, Equatable {
    var memberId: String?
    var memberFullName: String?
    var memberUsername: String?
    /// `nil` means all boards the API returns are enabled until the user customizes toggles.
    var enabledBoardIds: [String]?

    static let empty = TrelloConnectionsRoot(memberId: nil, memberFullName: nil, memberUsername: nil, enabledBoardIds: nil)
}

@MainActor
final class TrelloConnectionsSettingsStore: ObservableObject {
    static let shared = TrelloConnectionsSettingsStore()

    private let defaultsKey = "trelloConnectionsSettings.v1"

    @Published private(set) var root: TrelloConnectionsRoot

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(TrelloConnectionsRoot.self, from: data) {
            root = decoded
        } else {
            root = .empty
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(root) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        objectWillChange.send()
    }

    private func replaceRoot(_ next: TrelloConnectionsRoot) {
        root = next
        persist()
    }

    func setMemberLabels(memberId: String?, fullName: String?, username: String?) {
        var next = root
        next.memberId = memberId
        next.memberFullName = fullName
        next.memberUsername = username
        replaceRoot(next)
    }

    func clearMemberLabels() {
        var next = root
        next.memberId = nil
        next.memberFullName = nil
        next.memberUsername = nil
        replaceRoot(next)
    }

    func setEnabledBoardIds(_ ids: [String]?) {
        var next = root
        next.enabledBoardIds = ids
        replaceRoot(next)
    }

    func applyBoardToggle(boardId: String, isOn: Bool, allBoardIds: [String]) {
        let all = Set(allBoardIds)
        var chosen: Set<String>
        if let existing = root.enabledBoardIds {
            chosen = Set(existing)
        } else {
            chosen = all
        }
        if isOn {
            chosen.insert(boardId)
        } else {
            chosen.remove(boardId)
        }
        var next = root
        if chosen == all {
            next.enabledBoardIds = nil
        } else {
            next.enabledBoardIds = Array(chosen)
        }
        replaceRoot(next)
    }

    func isBoardEnabled(boardId: String, allBoardIds: [String]) -> Bool {
        guard let explicit = root.enabledBoardIds else { return true }
        if explicit.isEmpty { return false }
        return explicit.contains(boardId)
    }

    func clearAllPreferences() {
        replaceRoot(.empty)
    }
}
