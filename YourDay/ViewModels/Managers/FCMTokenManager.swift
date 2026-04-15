//
//  FCMTokenManager.swift
//  YourDay
//
//  Manages FCM registration token lifecycle: saves to Firestore on refresh,
//  deletes on sign-out so stale devices don't keep receiving pushes.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

final class FCMTokenManager: NSObject, MessagingDelegate {
    static let shared = FCMTokenManager()

    private let db = Firestore.firestore()

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        // Only save if APNs token is already set — avoids persisting a token
        // that Firebase issued before the APNs handshake completed.
        guard Messaging.messaging().apnsToken != nil else {
            print("FCMTokenManager: Skipping token save — APNs token not yet set")
            return
        }
        saveToken(token)
    }

    // MARK: - Token persistence

    func saveToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users")
            .document(uid)
            .collection("fcmTokens")
            .document(token)
            .setData(["updatedAt": FieldValue.serverTimestamp()], merge: true) { error in
                if let error {
                    print("FCMTokenManager: Failed to save token – \(error.localizedDescription)")
                } else {
                    print("FCMTokenManager: Token saved for uid \(uid)")
                }
            }
    }

    /// Fetches the current FCM token and saves it. Call this after sign-in so the
    /// token is persisted even when the MessagingDelegate callback fired before auth.
    func saveCurrentToken() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self, let token, error == nil else { return }
            self.saveToken(token)
        }
    }

    func deleteCurrentToken(completion: (() -> Void)? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        Messaging.messaging().token { [weak self] token, error in
            guard let self, let token, error == nil else {
                completion?()
                return
            }

            self.db.collection("users")
                .document(uid)
                .collection("fcmTokens")
                .document(token)
                .delete { error in
                    if let error {
                        print("FCMTokenManager: Failed to delete token – \(error.localizedDescription)")
                    } else {
                        print("FCMTokenManager: Token deleted for uid \(uid)")
                    }
                    completion?()
                }
        }
    }
}
