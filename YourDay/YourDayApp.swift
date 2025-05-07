//
//  YourDayApp.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData
import FirebaseCore

@main
struct YourDayApp: App {
    
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TodoItem.self, NoteItem.self, PlayerStats.self,DailySummaryTask.self])
    }
}
