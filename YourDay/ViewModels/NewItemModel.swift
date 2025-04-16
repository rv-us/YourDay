//
//  NewItemModel.swift
//  YourDay
//
//  Created by Rachit Verma on 4/16/25.
//
import Foundation

class NewItemModel: ObservableObject {
    @Published var title = ""
    @Published var description = ""
    @Published var donebye = Date()
    @Published var showAlert = false
    init() {}
    
    func add() {
        
    }
    
    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        
        guard donebye >= Date().addingTimeInterval(-86400) else {
            return false
        }
        return true
    }
}
