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
        appearance.configureWithOpaqueBackground()
        
        appearance.backgroundColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(DarkTheme.secondaryBackground) : UIColor(LightTheme.secondaryBackground)
        }
        
        let selectedColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(DarkTheme.primary) : UIColor(LightTheme.primary)
        }
        
        let unselectedColor = UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(DarkTheme.secondaryText) : UIColor(LightTheme.secondaryText)
        }
        
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        
        appearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselectedColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selectedColor
    }

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(locationManager)
        }
        .modelContainer(for: [TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self])
    }
}
