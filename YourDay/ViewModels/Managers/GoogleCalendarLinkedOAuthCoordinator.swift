//
//  GoogleCalendarLinkedOAuthCoordinator.swift
//  YourDay
//
//  Adds read-only Google Calendar access for additional accounts (AppAuth + Keychain).
//

import UIKit
import Foundation
import FirebaseCore
import GoogleSignIn
import AppAuth

enum GoogleCalendarLinkedOAuthError: LocalizedError {
    case missingClientID
    case noRefreshToken
    case missingIDToken
    case cannotParseAccount
    case sameAsPrimaryAccount
    case keychainSaveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Google client ID is not configured."
        case .noRefreshToken: return "Google did not return a refresh token. Try again and ensure you grant access."
        case .missingIDToken: return "Could not read account from Google sign-in response."
        case .cannotParseAccount: return "Could not determine your Google account id."
        case .sameAsPrimaryAccount: return "This account is already your primary Google sign-in. Use Calendars under Primary to choose calendars."
        case .keychainSaveFailed(let e): return "Could not save credentials: \(e.localizedDescription)"
        }
    }
}

enum GoogleOAuthRedirectBuilder {
    /// iOS OAuth client id `XXXX.apps.googleusercontent.com` → custom scheme redirect used by Google Sign-In.
    static func redirectURL(iOSClientId: String) -> URL {
        let prefix = iOSClientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return URL(string: "com.googleusercontent.apps.\(prefix):/oauth2redirect/google")!
    }
}

enum GoogleIDTokenPayload {
    static func subAndEmail(from idToken: String?) -> (sub: String?, email: String?) {
        guard let idToken, let payload = jwtPayloadJSON(idToken) else { return (nil, nil) }
        return (payload["sub"] as? String, payload["email"] as? String)
    }

    private static func jwtPayloadJSON(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let data = base64URLDecode(String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func base64URLDecode(_ segment: String) -> Data? {
        var s = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 { s += String(repeating: "=", count: pad) }
        return Data(base64Encoded: s)
    }
}

/// Resolves `sub` / `email` from Google’s userinfo endpoint (used when JWT omits fields and for Connections backfill).
enum GoogleOAuth2UserInfoClient {
    static func fetchSubAndEmail(accessToken: String) async -> (sub: String?, email: String?) {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo") else { return (nil, nil) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard (200 ..< 300).contains(status) else {
                print("[CalendarConnections] LinkedOAuth: userinfo HTTP status=\(status)")
                return (nil, nil)
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let sub = obj?["sub"] as? String
            let email = obj?["email"] as? String
            return (sub, email)
        } catch {
            print("[CalendarConnections] LinkedOAuth: userinfo fetch ERROR \(error.localizedDescription)")
            return (nil, nil)
        }
    }
}

final class GoogleCalendarLinkedOAuthCoordinator {
    static let shared = GoogleCalendarLinkedOAuthCoordinator()

    /// AppAuth session for in-flight linked-account OAuth; must receive the redirect via `resumeLinkedOAuthIfOpenURL`.
    private var pendingExternalUserAgentSession: OIDExternalUserAgentSession?

    private init() {}

    /// Call from SwiftUI `onOpenURL` **before** `GIDSignIn.sharedInstance.handle(_:)` so AppAuth receives the redirect.
    @discardableResult
    func resumeLinkedOAuthIfOpenURL(_ url: URL) -> Bool {
        guard let session = pendingExternalUserAgentSession else {
            return false
        }
        let handled = session.resumeExternalUserAgentFlow(with: url)
        print("[CalendarConnections] LinkedOAuth: openURL resumeExternalUserAgentFlow handled=\(handled) scheme=\(url.scheme ?? "?")")
        return handled
    }

    private func clearPendingSession() {
        pendingExternalUserAgentSession = nil
    }

    /// Presents Google OAuth for `calendar.readonly` and stores refresh token + preferences.
    func signInReadOnlyLinkedAccount(
        presenting: UIViewController,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        print("[CalendarConnections] LinkedOAuth: begin signInReadOnlyLinkedAccount")
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("[CalendarConnections] LinkedOAuth: FAIL missing Firebase clientID")
            completion(.failure(GoogleCalendarLinkedOAuthError.missingClientID))
            return
        }

        let redirectURL = GoogleOAuthRedirectBuilder.redirectURL(iOSClientId: clientID)
        print("[CalendarConnections] LinkedOAuth: redirectURL=\(redirectURL.absoluteString)")
        let config = OIDServiceConfiguration(
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!
        )

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: clientID,
            scopes: [
                OIDScopeOpenID,
                "https://www.googleapis.com/auth/userinfo.email",
                "https://www.googleapis.com/auth/calendar.readonly"
            ],
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: [
                "access_type": "offline",
                "prompt": "consent"
            ]
        )

        clearPendingSession()

        let externalSession = OIDAuthState.authState(byPresenting: request, presenting: presenting) { authState, error in
            defer { self.clearPendingSession() }
            if let error {
                print("[CalendarConnections] LinkedOAuth: AppAuth callback ERROR \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let authState else {
                print("[CalendarConnections] LinkedOAuth: AppAuth callback authState=nil")
                DispatchQueue.main.async { completion(.failure(GoogleCalendarLinkedOAuthError.noRefreshToken)) }
                return
            }
            func nonEmpty(_ s: String?) -> String? {
                guard let s, !s.isEmpty else { return nil }
                return s
            }
            let fromState = nonEmpty(authState.refreshToken)
            let fromTokenResponse = nonEmpty(authState.lastTokenResponse?.refreshToken)
            let rsDesc = fromState.map { "yes(len=\($0.count))" } ?? "no"
            let rtDesc = fromTokenResponse.map { "yes(len=\($0.count))" } ?? "no"
            print("[CalendarConnections] LinkedOAuth: refreshToken from authState=\(rsDesc) from lastTokenResponse=\(rtDesc)")
            let refresh = fromState ?? fromTokenResponse
            guard let refresh else {
                print("[CalendarConnections] LinkedOAuth: FAIL no refresh token from Google response")
                DispatchQueue.main.async { completion(.failure(GoogleCalendarLinkedOAuthError.noRefreshToken)) }
                return
            }

            Task {
                let idFromAuth = authState.lastAuthorizationResponse.idToken
                let idFromToken = authState.lastTokenResponse?.idToken
                let idToken = idFromAuth ?? idFromToken
                var (sub, email) = GoogleIDTokenPayload.subAndEmail(from: idToken)
                print("[CalendarConnections] LinkedOAuth: idToken authRsp=\(idFromAuth != nil) tokenRsp=\(idFromToken != nil) sub=\(sub ?? "nil") email=\(email ?? "nil")")

                if let access = authState.lastTokenResponse?.accessToken, !access.isEmpty {
                    let needSub = sub == nil || (sub?.isEmpty ?? true)
                    let needEmail = email == nil || (email?.isEmpty ?? true)
                    if needSub || needEmail {
                        let fetched = await GoogleOAuth2UserInfoClient.fetchSubAndEmail(accessToken: access)
                        if needSub, let s = fetched.sub, !s.isEmpty { sub = s }
                        if needEmail, let e = fetched.email, !e.isEmpty { email = e }
                        print("[CalendarConnections] LinkedOAuth: userinfo enrich sub=\(sub ?? "nil") email=\(email ?? "nil")")
                    }
                }

                guard let sub, !sub.isEmpty else {
                    print("[CalendarConnections] LinkedOAuth: FAIL cannot determine Google account id")
                    await MainActor.run {
                        completion(.failure(GoogleCalendarLinkedOAuthError.cannotParseAccount))
                    }
                    return
                }

                let primaryID = await MainActor.run { GIDSignIn.sharedInstance.currentUser?.userID }
                if let primaryID, primaryID == sub {
                    print("[CalendarConnections] LinkedOAuth: FAIL linked sub matches primary GID userID=\(primaryID)")
                    await MainActor.run {
                        completion(.failure(GoogleCalendarLinkedOAuthError.sameAsPrimaryAccount))
                    }
                    return
                }

                do {
                    try CalendarConnectionKeychain.saveRefreshToken(refresh, accountKey: sub)
                    print("[CalendarConnections] LinkedOAuth: Keychain save OK accountKey=\(sub) refreshLen=\(refresh.count)")
                } catch {
                    print("[CalendarConnections] LinkedOAuth: Keychain save FAIL \(error.localizedDescription)")
                    await MainActor.run {
                        completion(.failure(GoogleCalendarLinkedOAuthError.keychainSaveFailed(error)))
                    }
                    return
                }

                await MainActor.run {
                    print("[CalendarConnections] LinkedOAuth: upsertLinkedAccount on MainActor sub=\(sub)")
                    CalendarConnectionsSettingsStore.shared.upsertLinkedAccount(accountKey: sub, email: email)
                    let linkedCount = CalendarConnectionsSettingsStore.shared.linkedReadOnlyAccounts.count
                    print("[CalendarConnections] LinkedOAuth: SUCCESS linked accounts in store count=\(linkedCount)")
                    completion(.success(()))
                }
            }
        }

        if let session = externalSession as? OIDExternalUserAgentSession {
            pendingExternalUserAgentSession = session
            print("[CalendarConnections] LinkedOAuth: stored pending OIDExternalUserAgentSession for openURL resume")
        } else {
            print("[CalendarConnections] LinkedOAuth: WARN authState() return type=\(String(describing: Swift.type(of: externalSession)))")
        }
    }
}
