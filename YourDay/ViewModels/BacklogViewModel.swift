//
//  BacklogViewModel.swift
//  YourDay
//
//  ViewModel for managing backlog items
//

import Foundation
import SwiftData
import SwiftUI
import FirebaseAuth

enum BacklogItemSource {
    case firebase(BacklogItem)
    case todoItem(TodoItem)
}

struct UnifiedBacklogItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let source: BacklogItemSource
    let priority: Int
    let estimatedDuration: Int?
    let createdAt: Date
    
    init(from backlogItem: BacklogItem) {
        self.id = backlogItem.id ?? UUID().uuidString
        self.title = backlogItem.title
        self.description = backlogItem.description
        self.source = .firebase(backlogItem)
        self.priority = backlogItem.priority
        self.estimatedDuration = backlogItem.estimatedDuration
        self.createdAt = backlogItem.createdAt
    }
    
    init(from todoItem: TodoItem) {
        self.id = todoItem.persistentModelID.hashValue.description
        self.title = todoItem.title
        self.description = todoItem.detail
        self.source = .todoItem(todoItem)
        self.priority = 0 // TodoItems don't have priority yet
        self.estimatedDuration = nil
        self.createdAt = todoItem.dueDate // Use dueDate as fallback
    }
}

class BacklogViewModel: ObservableObject {
    @Published var backlogItems: [UnifiedBacklogItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let firebaseManager = FirebaseManager.shared
    
    func fetchBacklogItems(todoItems: [TodoItem]) {
        isLoading = true
        errorMessage = nil
        
        // Fetch Firebase backlog items
        firebaseManager.fetchBacklogItems { [weak self] items, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to fetch backlog items: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                
                // Combine Firebase backlog items and TodoItems
                var unifiedItems: [UnifiedBacklogItem] = []
                
                // Add Firebase backlog items
                if let firebaseItems = items {
                    unifiedItems.append(contentsOf: firebaseItems.map { UnifiedBacklogItem(from: $0) })
                }
                
                // Add TodoItems (both .today and .master origin)
                let todoBacklogItems = todoItems
                    .filter { !$0.isDone } // Only include incomplete tasks
                    .map { UnifiedBacklogItem(from: $0) }
                unifiedItems.append(contentsOf: todoBacklogItems)
                
                // Sort by priority (higher first) then by creation date
                unifiedItems.sort { item1, item2 in
                    if item1.priority != item2.priority {
                        return item1.priority > item2.priority
                    }
                    return item1.createdAt > item2.createdAt
                }
                
                self.backlogItems = unifiedItems
                self.isLoading = false
            }
        }
    }
    
    func addBacklogItem(title: String, description: String, priority: Int = 0, estimatedDuration: Int? = nil, completion: @escaping (Error?) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion(NSError(domain: "BacklogViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"]))
            return
        }
        
        let newItem = BacklogItem(
            title: title,
            description: description,
            createdAt: Date(),
            userId: userId,
            priority: priority,
            estimatedDuration: estimatedDuration
        )
        
        firebaseManager.saveBacklogItem(newItem) { [weak self] error in
            if let error = error {
                completion(error)
                return
            }
            
            // Refresh backlog items
            self?.fetchBacklogItems(todoItems: [])
            completion(nil)
        }
    }
    
    func deleteBacklogItem(_ item: UnifiedBacklogItem, completion: @escaping (Error?) -> Void) {
        switch item.source {
        case .firebase(let backlogItem):
            guard let itemId = backlogItem.id else {
                completion(NSError(domain: "BacklogViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Item ID is missing"]))
                return
            }
            
            firebaseManager.deleteBacklogItem(itemId) { [weak self] error in
                if let error = error {
                    completion(error)
                    return
                }
                
                // Refresh backlog items
                self?.fetchBacklogItems(todoItems: [])
                completion(nil)
            }
            
        case .todoItem:
            // Can't delete TodoItems from backlog view - they should be managed in TodoView
            completion(NSError(domain: "BacklogViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot delete TodoItem from backlog view"]))
        }
    }
    
    func isFirebaseItem(_ item: UnifiedBacklogItem) -> Bool {
        if case .firebase = item.source {
            return true
        }
        return false
    }
}
