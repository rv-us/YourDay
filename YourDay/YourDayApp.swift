import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn
import UIKit


@main
struct YourDayApp: App {
    @StateObject private var locationManager = LocationManager()

    init() {
        // Add crash prevention before any other initialization
        setupCrashPrevention()
        
        FirebaseApp.configure()
        
        // Configure Google Sign-In early to enable token persistence
        if let clientID = FirebaseApp.app()?.options.clientID {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }
        
        // Initialize GoogleCalendarManager to restore sign-in state
        _ = GoogleCalendarManager.shared
        
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        appearance.backgroundColor = UIColor { _ in
            return UIColor(LightTheme.secondaryBackground)
        }
        
        let selectedColor = UIColor { _ in
            return UIColor(LightTheme.primary)
        }
        
        let unselectedColor = UIColor { _ in
            return UIColor(LightTheme.secondaryText)
        }
        
        appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: selectedColor]
        
        appearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: unselectedColor]
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selectedColor
    }
    
    private func setupCrashPrevention() {
        // Clear potentially corrupted UserDefaults data that could cause crashes
        let dateKeys = [
            "lastSummaryDate",
            "lastAppOpenDateForWitheringCheck", 
            "lastAppActiveDate"
        ]
        
        for key in dateKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                if !isValidDateString(value, forKey: key) {
                    print("App: Clearing invalid date data for key: \(key)")
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        
        // Clear tutorial states if they might be corrupted
        let tutorialKeys = [
            "hasCompletedTodoTutorial",
            "hasCompletedNotesTutorial",
            "hasCompletedNotificationsTutorial",
            "hasCompletedGardenTutorial_v1"
        ]
        
        for key in tutorialKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                if !(value is Bool) {
                    print("App: Clearing invalid tutorial data for key: \(key)")
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }
    
    private func isValidDateString(_ value: Any, forKey key: String) -> Bool {
        guard let stringValue = value as? String else { return false }
        
        // Check if it's a valid date string format
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let _ = formatter.date(from: stringValue) {
            return true
        }
        
        // If it's not a valid date, it might be an old format - clear it
        return false
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
