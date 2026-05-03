//
//  CalendarConnectionKeychain.swift
//  YourDay
//
//  Stores OAuth refresh tokens for linked Google accounts (read-only calendar).
//

import Foundation
import Security

enum CalendarConnectionKeychain {
    private static let service = "com.yourday.calendar.linkedRefresh"

    static func saveRefreshToken(_ token: String, accountKey: String) throws {
        print("[CalendarConnections] Keychain: save begin accountKey=\(accountKey) tokenLen=\(token.count)")
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            print("[CalendarConnections] Keychain: save FAIL SecItemAdd status=\(status) accountKey=\(accountKey)")
            throw NSError(domain: "CalendarConnectionKeychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain save failed (\(status))"])
        }
        print("[CalendarConnections] Keychain: save OK status=\(status)")
    }

    static func loadRefreshToken(accountKey: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            print("[CalendarConnections] Keychain: load MISS accountKey=\(accountKey) status=\(status)")
            return nil
        }
        let str = String(data: data, encoding: .utf8)
        print("[CalendarConnections] Keychain: load HIT accountKey=\(accountKey) dataLen=\(data.count) stringLen=\(str?.count ?? 0)")
        return str
    }

    static func deleteRefreshToken(accountKey: String) {
        print("[CalendarConnections] Keychain: delete accountKey=\(accountKey)")
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
