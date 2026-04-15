//
//  AppDelegate.swift
//  YourDay
//
//  Bridges APNs device tokens to FirebaseMessaging and registers for remote notifications.
//

import UIKit
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register for remote notifications (APNs device token handoff to FCM)
        application.registerForRemoteNotifications()
        // Activate FCMTokenManager so it becomes the MessagingDelegate
        _ = FCMTokenManager.shared
        return true
    }

    // MARK: - APNs token handoff

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("AppDelegate: APNs token received – \(tokenString.prefix(20))...")
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("AppDelegate: ❌ Failed to register for remote notifications – \(error.localizedDescription)")
    }
}
