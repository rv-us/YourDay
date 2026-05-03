//
//  TrelloTaskSyncService.swift
//  YourDay
//

import FirebaseAuth
import Foundation
import SwiftData

@MainActor
enum TrelloTaskSyncService {
    private static let calendar = Calendar.current

    static func runDailyTrelloImport(modelContext: ModelContext) async {
        await importOrRefresh(modelContext: modelContext, deleteMissingMirrors: false)
    }

    static func refreshTrelloMirroredTasks(modelContext: ModelContext) async {
        await importOrRefresh(modelContext: modelContext, deleteMissingMirrors: true)
    }

    static func pushCompletion(for item: TodoItem) async {
        guard let cardId = item.trelloCardId, let token = TrelloConnectionKeychain.loadUserToken() else { return }
        do {
            try await TrelloAPIClient.updateCardDueComplete(cardId: cardId, isComplete: item.isDone, token: token)
        } catch {
            print("[TrelloTaskSync] Failed to push completion for \(cardId): \(error.localizedDescription)")
        }
    }

    static func pushEdit(for item: TodoItem) async {
        guard let cardId = item.trelloCardId, let token = TrelloConnectionKeychain.loadUserToken() else { return }
        do {
            try await TrelloAPIClient.updateCard(
                cardId: cardId,
                name: item.title,
                desc: item.detail,
                due: item.dueDate,
                token: token
            )
        } catch {
            print("[TrelloTaskSync] Failed to push edit for \(cardId): \(error.localizedDescription)")
        }
    }

    static func deleteRemoteCardIfNeeded(for item: TodoItem) async {
        guard let cardId = item.trelloCardId, let token = TrelloConnectionKeychain.loadUserToken() else { return }
        do {
            try await TrelloAPIClient.deleteCard(cardId: cardId, token: token)
        } catch {
            print("[TrelloTaskSync] Failed to delete Trello card \(cardId): \(error.localizedDescription)")
        }
    }

    static func purgeAllMirroredTasks(modelContext: ModelContext) {
        purgeMirroredTasks(modelContext: modelContext) { _ in true }
    }

    static func purgeMirroredTasksNotInEnabledBoards(modelContext: ModelContext) {
        let enabled = Set(TrelloConnectionsSettingsStore.shared.root.enabledBoardIds ?? [])
        guard TrelloConnectionsSettingsStore.shared.root.enabledBoardIds != nil else { return }
        purgeMirroredTasks(modelContext: modelContext) { item in
            guard let boardId = item.trelloBoardId else { return true }
            return !enabled.contains(boardId)
        }
    }

    private static func importOrRefresh(modelContext: ModelContext, deleteMissingMirrors: Bool) async {
        guard let token = TrelloConnectionKeychain.loadUserToken() else { return }

        do {
            let member = try await TrelloAPIClient.memberMe(token: token)
            TrelloConnectionsSettingsStore.shared.setMemberLabels(
                memberId: member.id,
                fullName: member.fullName,
                username: member.username
            )

            let boards = try await TrelloAPIClient.memberBoards(token: token).filter { $0.closed != true }
            let enabledBoardIds = enabledBoardIds(from: boards)
            guard !enabledBoardIds.isEmpty else {
                if deleteMissingMirrors {
                    purgeAllMirroredTasks(modelContext: modelContext)
                }
                return
            }

            var importedCardIds = Set<String>()
            for boardId in enabledBoardIds {
                let cards = try await TrelloAPIClient.openCards(boardId: boardId, token: token)
                for card in cards where isEligible(card, memberId: member.id, boardId: boardId) {
                    importedCardIds.insert(card.id)
                    upsert(card: card, boardId: boardId, modelContext: modelContext, allowNewCompletedCards: deleteMissingMirrors)
                }
            }

            if deleteMissingMirrors {
                purgeMirroredTasks(modelContext: modelContext) { item in
                    guard let cardId = item.trelloCardId else { return false }
                    guard let boardId = item.trelloBoardId else { return true }
                    return !enabledBoardIds.contains(boardId) || !importedCardIds.contains(cardId)
                }
            }

            try modelContext.save()
        } catch {
            print("[TrelloTaskSync] Import/refresh failed: \(error.localizedDescription)")
        }
    }

    private static func enabledBoardIds(from boards: [TrelloBoardAPIItem]) -> [String] {
        let openBoardIds = boards.map(\.id)
        guard let explicit = TrelloConnectionsSettingsStore.shared.root.enabledBoardIds else {
            return openBoardIds
        }
        let explicitSet = Set(explicit)
        return openBoardIds.filter { explicitSet.contains($0) }
    }

    private static func isEligible(_ card: TrelloCardAPIItem, memberId: String, boardId: String) -> Bool {
        guard card.closed != true else { return false }
        guard (card.idBoard ?? boardId) == boardId else { return false }
        return card.idMembers?.contains(memberId) == true
    }

    private static func upsert(card: TrelloCardAPIItem, boardId: String, modelContext: ModelContext, allowNewCompletedCards: Bool) {
        let allTasks = fetchAllTasks(modelContext: modelContext)
        let existing = allTasks.first { $0.trelloCardId == card.id }
        let dueDate = card.due ?? Date()
        let origin = originForCardDueDate(card.due)
        let isComplete = card.dueComplete == true

        if let existing {
            existing.title = card.name ?? "Trello card"
            existing.detail = card.desc ?? ""
            existing.dueDate = dueDate
            if existing.isDone != isComplete {
                existing.completedAt = isComplete ? Date() : nil
            }
            existing.isDone = isComplete
            existing.origin = origin
            existing.trelloBoardId = boardId
            existing.trelloListId = card.idList
            existing.trelloDateLastActivity = card.dateLastActivity
            syncToFirebase(existing)
        } else {
            guard !isComplete || allowNewCompletedCards else { return }
            let task = TodoItem(
                title: card.name ?? "Trello card",
                detail: card.desc ?? "",
                dueDate: dueDate,
                isDone: isComplete,
                origin: origin,
                trelloCardId: card.id,
                trelloBoardId: boardId,
                trelloListId: card.idList,
                trelloDateLastActivity: card.dateLastActivity
            )
            task.completedAt = isComplete ? Date() : nil
            modelContext.insert(task)
            syncToFirebase(task)
        }
    }

    private static func originForCardDueDate(_ dueDate: Date?) -> TaskOrigin {
        guard let dueDate else { return .master }
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        return dueDay <= today ? .today : .master
    }

    private static func purgeMirroredTasks(modelContext: ModelContext, shouldDelete: (TodoItem) -> Bool) {
        let tasksToDelete = fetchAllTasks(modelContext: modelContext).filter { item in
            item.trelloCardId != nil && shouldDelete(item)
        }
        guard !tasksToDelete.isEmpty else { return }
        let ids = tasksToDelete.map(\.localTaskId)
        for task in tasksToDelete {
            modelContext.delete(task)
        }
        FirebaseManager.shared.deleteTodoItems(localTaskIds: ids) { error in
            if let error {
                print("[TrelloTaskSync] Failed to delete purged tasks from Firebase: \(error.localizedDescription)")
            }
        }
        do {
            try modelContext.save()
        } catch {
            print("[TrelloTaskSync] Failed to save purged tasks: \(error.localizedDescription)")
        }
    }

    private static func fetchAllTasks(modelContext: ModelContext) -> [TodoItem] {
        do {
            return try modelContext.fetch(FetchDescriptor<TodoItem>())
        } catch {
            print("[TrelloTaskSync] Failed to fetch local tasks: \(error.localizedDescription)")
            return []
        }
    }

    private static func syncToFirebase(_ task: TodoItem) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let codable = TodoItemCodable(from: task, userId: userId)
        FirebaseManager.shared.saveTodoItem(codable) { error in
            if let error {
                print("[TrelloTaskSync] Failed to sync \(task.localTaskId) to Firebase: \(error.localizedDescription)")
            }
        }
    }
}
