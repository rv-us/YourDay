//
//  Subtask.swift
//  YourDay
//
//  Created by Rachit Verma on 4/21/25.
//
import Foundation

struct Subtask: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var isDone: Bool = false {
        didSet {
            if isDone {
                completedAt = Date()
            } else {
                completedAt = nil
            }
        }
    }
    var completedAt: Date? = nil
}

