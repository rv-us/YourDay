import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn
import UIKit
import UserNotifications

private let migrationValidationErrorCode = 134110

private func containsCocoaErrorCode(_ error: Error, code: Int) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain && nsError.code == code {
        return true
    }
    if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error,
       containsCocoaErrorCode(underlyingError, code: code) {
        return true
    }
    return false
}

private func resetDefaultSwiftDataStoreFiles() {
    let fileManager = FileManager.default
    guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }

    let storeFilenames = ["default.store", "default.store-shm", "default.store-wal"]
    for filename in storeFilenames {
        let fileURL = appSupportURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: fileURL.path) else { continue }
        do {
            try fileManager.removeItem(at: fileURL)
            print("App: Removed SwiftData store file at \(fileURL.path)")
        } catch {
            print("App: Failed to remove SwiftData store file at \(fileURL.path): \(error.localizedDescription)")
        }
    }
}

@main
struct YourDayApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var locationManager = LocationManager()
    
    private static var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self)
        } catch {
            guard containsCocoaErrorCode(error, code: migrationValidationErrorCode) else {
                fatalError("Unresolved error loading ModelContainer: \(error.localizedDescription)")
            }

            print("App: Detected CoreData migration validation error (\(migrationValidationErrorCode)). Resetting local SwiftData store and retrying.")
            resetDefaultSwiftDataStoreFiles()

            do {
                return try ModelContainer(for: TodoItem.self, NoteItem.self, PlayerStats.self, DailySummaryTask.self)
            } catch {
                fatalError("Unresolved error loading ModelContainer after reset: \(error.localizedDescription)")
            }
        }
    }()

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
        
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        NotificationManager.shared.requestPermissionIfNeeded()
        
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        
        appearance.backgroundColor = UIColor { _ in
            return UIColor(LightTheme.secondaryBackground)
        }
        
        let selectedColor = UIColor { _ in
            return UIColor.black
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
        .modelContainer(Self.sharedModelContainer)
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
