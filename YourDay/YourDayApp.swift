//
//  YourDayApp.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData

@main
struct YourDayApp: App {
    var body: some Scene {
        WindowGroup {
            Todoview()
        }
        .modelContainer(for: TodoItem.self)
    }
}

