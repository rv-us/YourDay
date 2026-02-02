//
//  ModificationContext.swift
//  YourDay
//
//  Model for tracking session modifications
//

import Foundation

struct ModificationContext: Identifiable {
    let id = UUID()
    let tasks: [String]
    let originalTasks: [String]
    let addedTasks: [String]
    let removedTasks: [String]
    let originalTime: String
    let modifiedTime: String
    let dayOfWeek: String
    var reason: String?
    var isReviewed: Bool = false
}


