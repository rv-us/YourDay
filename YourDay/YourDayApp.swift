//
//  YourDayApp.swift
//  YourDay
//
//  Created by Rachit Verma on 4/8/25.
//

import SwiftUI
import SwiftData
import FirebaseCore
import UIKit

@main
struct YourDayApp: App {
    @StateObject private var locationManager = LocationManager()

    init() {
        FirebaseApp.configure()
        let appearance = UITabBarAppearance()
        appearance.backgroundColor = UIColor(plantLightMintGreen)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = UIColor(plantDarkGreen)
        appearance.stackedLayoutAppearance.normal.iconColor = UIColor(plantDustyBlue)
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor(plantDustyBlue)]
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(locationManager)
//                .onAppear {
//                    locationManager.requestPermissions()
//                }
        }
        .modelContainer(for: [TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self])
    }
}
