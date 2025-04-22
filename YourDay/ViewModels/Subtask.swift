//
//  Subtask.swift
//  YourDay
//
//  Created by Rachit Verma on 4/21/25.
//
import Foundation

struct Subtask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone: Bool = false
}
