//
//  GoogleCalendarEventFetchService.swift
//  YourDay
//
//  Calendar list + merged event reads for primary GID user and linked read-only accounts.
//

import Foundation
import GoogleSignIn
import FirebaseCore

// MARK: - Calendar list API

struct GoogleCalendarListAPIItem: Codable {
    let id: String?
    let summary: String?
    let primary: Bool?
    let selected: Bool?
    let accessRole: String?
}

private struct GoogleCalendarListAPIResponse: Codable {
    let items: [GoogleCalendarListAPIItem]?
    let nextPageToken: String?
}

// MARK: - Linked account token refresh

private struct GoogleOAuthTokenResponse: Decodable {
    let access_token: String
}

enum GoogleLinkedOAuthTokenRefresher {
    static func accessToken(refreshToken: String, clientId: String) async throws -> String {
        print("[CalendarConnections] TokenRefresh: POST oauth2 token refreshLen=\(refreshToken.count) clientIdPrefix=\(clientId.prefix(20))…")
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[CalendarConnections] TokenRefresh: FAIL non-HTTP response")
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(200)) } ?? ""
            print("[CalendarConnections] TokenRefresh: FAIL http=\(http.statusCode) bodySnippet=\(snippet)")
            throw URLError(.userAuthenticationRequired)
        }
        let decoded = try JSONDecoder().decode(GoogleOAuthTokenResponse.self, from: data)
        print("[CalendarConnections] TokenRefresh: OK access_token len=\(decoded.access_token.count)")
        return decoded.access_token
    }
}

// MARK: - Fetch service

enum GoogleCalendarEventFetchService {
    private static let queryISOFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let readableRoles: Set<String> = ["owner", "writer", "reader"]

    /// Records the signed-in Google user in connection settings (for calendar toggles).
    @MainActor
    static func syncPrimaryAccountRecordIfNeeded() {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            print("[CalendarConnections] FetchService: syncPrimary skip (no GID currentUser)")
            return
        }
        guard let key = user.userID, !key.isEmpty else {
            print("[CalendarConnections] FetchService: syncPrimary skip (empty userID)")
            return
        }
        print("[CalendarConnections] FetchService: syncPrimary upsert key=\(key) email=\(user.profile?.email ?? "nil")")
        CalendarConnectionsSettingsStore.shared.upsertPrimaryGIDAccount(
            accountKey: key,
            email: user.profile?.email
        )
    }

    /// Fetches `calendarList` for the bearer token (all pages).
    static func fetchCalendarList(accessToken: String) async throws -> [GoogleCalendarListAPIItem] {
        print("[CalendarConnections] FetchService: fetchCalendarList start tokenLen=\(accessToken.count)")
        var all: [GoogleCalendarListAPIItem] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
            var items = [URLQueryItem(name: "minAccessRole", value: "reader")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items
            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let snippet = String(data: data, encoding: .utf8).map { String($0.prefix(160)) } ?? ""
                print("[CalendarConnections] FetchService: calendarList page non-200 http=\(code) snippet=\(snippet)")
                break
            }
            let decoded = try JSONDecoder().decode(GoogleCalendarListAPIResponse.self, from: data)
            if let batch = decoded.items { all.append(contentsOf: batch) }
            pageToken = decoded.nextPageToken
        } while pageToken != nil
        print("[CalendarConnections] FetchService: fetchCalendarList done totalItems=\(all.count)")
        return all
    }

    /// Events in `[start, end)` from one calendar.
    static func fetchEvents(
        accessToken: String,
        calendarId: String,
        start: Date,
        end: Date,
        sourceAccountKey: String
    ) async throws -> [GoogleCalendarEvent] {
        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var components = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events"
        )!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: queryISOFormatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: queryISOFormatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(GoogleCalendarResponse.self, from: data) else {
            return []
        }
        let items = decoded.items ?? []
        return items.map { item in
            var e = item
            e.sourceCalendarId = calendarId
            e.sourceAccountKey = sourceAccountKey
            return e
        }
    }

    private static func filterCalendarIds(
        list: [GoogleCalendarListAPIItem],
        accountKey: String
    ) async -> [String] {
        let readableIds = list.compactMap { item -> String? in
            guard let id = item.id, !id.isEmpty else { return nil }
            guard let role = item.accessRole, readableRoles.contains(role) else { return nil }
            return id
        }
        let explicit = await MainActor.run {
            CalendarConnectionsSettingsStore.shared.enabledCalendarIds(forAccountKey: accountKey)
        }
        guard let explicit else { return readableIds }
        if explicit.isEmpty { return [] }
        return readableIds.filter { explicit.contains($0) }
    }

    private static func fetchEventsForAccount(
        accessToken: String,
        accountKey: String,
        start: Date,
        end: Date
    ) async throws -> [GoogleCalendarEvent] {
        let list = try await fetchCalendarList(accessToken: accessToken)
        let calendarIds = await filterCalendarIds(list: list, accountKey: accountKey)
        var merged: [GoogleCalendarEvent] = []
        merged.reserveCapacity(64)
        for calId in calendarIds {
            let batch = try await fetchEvents(
                accessToken: accessToken,
                calendarId: calId,
                start: start,
                end: end,
                sourceAccountKey: accountKey
            )
            merged.append(contentsOf: batch)
        }
        merged.sort { a, b in
            let da = a.start.startDate ?? .distantFuture
            let db = b.start.startDate ?? .distantFuture
            if da != db { return da < db }
            return a.id < b.id
        }
        return merged
    }

    /// Merged events from primary GID (full calendar scope) and linked read-only OAuth accounts.
    static func fetchMergedVisibleEvents(start: Date, end: Date) async throws -> [GoogleCalendarEvent] {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "GoogleCalendarEventFetchService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Google client ID missing"])
        }

        var all: [GoogleCalendarEvent] = []

        if let user = GIDSignIn.sharedInstance.currentUser {
            let calendarScope = "https://www.googleapis.com/auth/calendar"
            if user.grantedScopes?.contains(calendarScope) == true {
                let refreshed: GIDGoogleUser = try await withCheckedThrowingContinuation { cont in
                    user.refreshTokensIfNeeded { u, err in
                        if let u { cont.resume(returning: u) }
                        else { cont.resume(throwing: err ?? URLError(.userAuthenticationRequired)) }
                    }
                }
                let token = refreshed.accessToken.tokenString
                if let accountKey = refreshed.userID, !accountKey.isEmpty {
                    let batch = try await fetchEventsForAccount(
                        accessToken: token,
                        accountKey: accountKey,
                        start: start,
                        end: end
                    )
                    all.append(contentsOf: batch)
                }
            }
        }

        let linkedKeys = await MainActor.run {
            CalendarConnectionsSettingsStore.shared.linkedReadOnlyAccounts.map(\.accountKey)
        }

        for accountKey in linkedKeys {
            guard let refresh = CalendarConnectionKeychain.loadRefreshToken(accountKey: accountKey) else { continue }
            let access = try await GoogleLinkedOAuthTokenRefresher.accessToken(
                refreshToken: refresh,
                clientId: clientID
            )
            let batch = try await fetchEventsForAccount(
                accessToken: access,
                accountKey: accountKey,
                start: start,
                end: end
            )
            all.append(contentsOf: batch)
        }

        all.sort { a, b in
            let da = a.start.startDate ?? .distantFuture
            let db = b.start.startDate ?? .distantFuture
            if da != db { return da < db }
            return a.id < b.id
        }
        return all
    }
}
