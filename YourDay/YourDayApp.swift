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
    @StateObject private var locationManager = LocationManager()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(locationManager)
                .onAppear {
                    locationManager.requestPermissions()
                }
        }
        .modelContainer(for: [TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self])
    }
}
