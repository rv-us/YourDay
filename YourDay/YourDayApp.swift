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
            AppRestartView()
                .environmentObject(locationManager)
        }
        .modelContainer(for: [TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self])
    }
}

struct AppRestartView: View {
    @State private var viewId = UUID()
    @AppStorage("lastAppActiveDate") private var lastAppActiveDate: String = ""

    var body: some View {
        SplashScreenView()
            .id(viewId)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                let todayString = formattedDateString(from: Date())
                
                if !lastAppActiveDate.isEmpty && lastAppActiveDate != todayString {
                    viewId = UUID()
                }
                
                lastAppActiveDate = todayString
            }
    }
    
    private func formattedDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
