//
//  CalendarConnectionsSettingsView.swift
//  YourDay
//
//  Google Calendar: primary sign-in, per-account calendar visibility, linked read-only accounts.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore
import UIKit

struct CalendarConnectionsSettingsView: View {
    @ObservedObject private var store = CalendarConnectionsSettingsStore.shared

    @State private var primaryCalendarRows: [GoogleCalendarListAPIItem] = []
    @State private var linkedCalendarRows: [String: [GoogleCalendarListAPIItem]] = [:]
    @State private var isLoadingLists = false
    @State private var listLoadError: String?
    @State private var isAddingLinkedAccount = false
    @State private var oauthBanner: String?

    private let calendarWriteScope = "https://www.googleapis.com/auth/calendar"

    var body: some View {
        List {
            Section {
                if let user = GIDSignIn.sharedInstance.currentUser {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Signed in")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(user.profile?.email ?? "Google account")
                            .foregroundColor(dynamicTextColor)
                            .font(.body.weight(.semibold))
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)

                    if user.grantedScopes?.contains(calendarWriteScope) != true {
                        Button("Grant calendar access") {
                            requestPrimaryCalendarAccess()
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }

                    Button("Sign out of Google", role: .destructive) {
                        GIDSignIn.sharedInstance.signOut()
                        GoogleCalendarEventFetchService.syncPrimaryAccountRecordIfNeeded()
                        primaryCalendarRows = []
                        oauthBanner = nil
                        Task { await reloadCalendarLists() }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } else {
                    Text("Sign in with your main Google account to create events and manage your primary calendars.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)

                    Button("Sign in with Google") {
                        requestPrimaryCalendarAccess()
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            } header: {
                Text("Primary Google account")
                    .foregroundColor(dynamicTextColor)
            }

            Section {
                if isLoadingLists {
                    HStack {
                        ProgressView()
                        Text("Loading calendars…")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } else if let listLoadError {
                    Text(listLoadError)
                        .font(.caption)
                        .foregroundColor(dynamicDestructiveColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                if !primaryCalendarRows.isEmpty {
                    Text("Calendars to show (primary)")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)

                    ForEach(primaryCalendarRows.compactMap { item -> (String, GoogleCalendarListAPIItem)? in
                        guard let id = item.id, !id.isEmpty else { return nil }
                        return (id, item)
                    }, id: \.0) { pair in
                        let calendarId = pair.0
                        let item = pair.1
                        let readable = readableCalendarAccess(item.accessRole)
                        let accountKey = GIDSignIn.sharedInstance.currentUser?.userID ?? ""
                        Toggle(
                            isOn: Binding(
                                get: {
                                    guard !accountKey.isEmpty else { return true }
                                    let allIds = primaryCalendarRows.compactMap(\.id).filter { !$0.isEmpty }
                                    return store.isCalendarEnabled(
                                        accountKey: accountKey,
                                        calendarId: calendarId,
                                        allReadableCalendarIds: allIds
                                    )
                                },
                                set: { on in
                                    guard !accountKey.isEmpty else { return }
                                    let allIds = primaryCalendarRows.compactMap(\.id).filter { !$0.isEmpty }
                                    store.applyCalendarToggle(
                                        accountKey: accountKey,
                                        calendarId: calendarId,
                                        isOn: on,
                                        allReadableCalendarIds: allIds
                                    )
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.summary ?? calendarId)
                                    .foregroundColor(dynamicTextColor)
                                if item.primary == true {
                                    Text("Primary")
                                        .font(.caption2)
                                        .foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                        }
                        .disabled(!readable || accountKey.isEmpty)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                } else if GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(calendarWriteScope) == true,
                          !isLoadingLists, listLoadError == nil {
                    Text("No calendars returned.")
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            } header: {
                Text("Visible calendars")
                    .foregroundColor(dynamicTextColor)
            }

            Section {
                if let oauthBanner {
                    Text(oauthBanner)
                        .font(.caption)
                        .foregroundColor(dynamicDestructiveColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                ForEach(store.linkedReadOnlyAccounts) { account in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.connectionsDisplayTitle)
                                    .foregroundColor(dynamicTextColor)
                                    .font(.subheadline.weight(.semibold))
                                Text("Read-only")
                                    .font(.caption2)
                                    .foregroundColor(dynamicSecondaryTextColor)
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                CalendarConnectionKeychain.deleteRefreshToken(accountKey: account.accountKey)
                                store.removeLinkedAccount(accountKey: account.accountKey)
                                linkedCalendarRows[account.accountKey] = nil
                                Task { await reloadCalendarLists() }
                            }
                            .font(.caption)
                        }

                        let rows = linkedCalendarRows[account.accountKey] ?? []
                        if !rows.isEmpty {
                            ForEach(rows.compactMap { item -> (String, GoogleCalendarListAPIItem)? in
                                guard let id = item.id, !id.isEmpty else { return nil }
                                return (id, item)
                            }, id: \.0) { pair in
                                let calendarId = pair.0
                                let item = pair.1
                                let readable = readableCalendarAccess(item.accessRole)
                                let allIds = rows.compactMap(\.id).filter { !$0.isEmpty }
                                Toggle(
                                    isOn: Binding(
                                        get: {
                                            store.isCalendarEnabled(
                                                accountKey: account.accountKey,
                                                calendarId: calendarId,
                                                allReadableCalendarIds: allIds
                                            )
                                        },
                                        set: { on in
                                            store.applyCalendarToggle(
                                                accountKey: account.accountKey,
                                                calendarId: calendarId,
                                                isOn: on,
                                                allReadableCalendarIds: allIds
                                            )
                                        }
                                    )
                                ) {
                                    Text(item.summary ?? calendarId)
                                        .foregroundColor(dynamicTextColor)
                                }
                                .disabled(!readable)
                            }
                        }
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                Button {
                    startAddLinkedAccount()
                } label: {
                    if isAddingLinkedAccount {
                        HStack {
                            ProgressView()
                            Text("Opening Google…")
                        }
                    } else {
                        Label("Add Google account (read-only)", systemImage: "person.badge.plus")
                    }
                }
                .disabled(isAddingLinkedAccount)
                .listRowBackground(dynamicSecondaryBackgroundColor)
            } header: {
                Text("Other Google accounts")
                    .foregroundColor(dynamicTextColor)
            } footer: {
                Text("Additional accounts can display on your schedule but cannot receive events created from YourDay.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .navigationTitle("Google Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            print("[CalendarConnections] UI: .task appeared → reloadCalendarLists")
            await reloadCalendarLists()
        }
    }

    private func readableCalendarAccess(_ role: String?) -> Bool {
        guard let role else { return false }
        return ["owner", "writer", "reader"].contains(role)
    }

    private func requestPrimaryCalendarAccess() {
        GoogleCalendarManager.shared.ensureCalendarWriteAccess { result in
            Task { @MainActor in
                switch result {
                case .success:
                    GoogleCalendarEventFetchService.syncPrimaryAccountRecordIfNeeded()
                    await reloadCalendarLists()
                case .failure(let err):
                    listLoadError = err.localizedDescription
                }
            }
        }
    }

    private func startAddLinkedAccount() {
        oauthBanner = nil
        print("[CalendarConnections] UI: startAddLinkedAccount tapped")
        guard let presenting = rootViewController() else {
            print("[CalendarConnections] UI: FAIL rootViewController nil")
            oauthBanner = "Could not present sign-in."
            return
        }
        isAddingLinkedAccount = true
        GoogleCalendarLinkedOAuthCoordinator.shared.signInReadOnlyLinkedAccount(presenting: presenting) { result in
            Task { @MainActor in
                isAddingLinkedAccount = false
                switch result {
                case .success:
                    print("[CalendarConnections] UI: OAuth completion success → yield + reloadCalendarLists")
                    await Task.yield()
                    await reloadCalendarLists()
                    print("[CalendarConnections] UI: reloadCalendarLists finished after OAuth")
                case .failure(let error):
                    print("[CalendarConnections] UI: OAuth completion FAILURE \(error.localizedDescription)")
                    oauthBanner = error.localizedDescription
                }
            }
        }
    }

    private func rootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = windowScene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    @MainActor
    private func reloadCalendarLists() async {
        print("[CalendarConnections] UI: reloadCalendarLists BEGIN")
        isLoadingLists = true
        listLoadError = nil
        defer {
            isLoadingLists = false
            print("[CalendarConnections] UI: reloadCalendarLists END isLoadingLists=false linkedRowKeys=\(linkedCalendarRows.keys.sorted()) primaryCount=\(primaryCalendarRows.count) error=\(listLoadError ?? "nil")")
        }

        GoogleCalendarEventFetchService.syncPrimaryAccountRecordIfNeeded()

        primaryCalendarRows = []
        linkedCalendarRows = [:]

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            listLoadError = "Google client ID is missing."
            print("[CalendarConnections] UI: reload abort no clientID")
            return
        }

        let linkedPrefs = store.linkedReadOnlyAccounts
        print("[CalendarConnections] UI: linked accounts from store count=\(linkedPrefs.count) keys=\(linkedPrefs.map(\.accountKey))")

        // Load linked accounts first so a stuck primary GID refresh never blocks showing them.
        var linked: [String: [GoogleCalendarListAPIItem]] = [:]
        for account in linkedPrefs {
            guard let refresh = CalendarConnectionKeychain.loadRefreshToken(accountKey: account.accountKey) else {
                print("[CalendarConnections] UI: linked loop SKIP no keychain token key=\(account.accountKey)")
                ConnectionReauthorizationNotifier.requestGoogleCalendar(
                    accountKey: account.accountKey,
                    displayName: account.connectionsDisplayTitle,
                    reason: "Missing saved Google refresh token."
                )
                if listLoadError == nil {
                    listLoadError = "Missing saved token for \(account.connectionsDisplayTitle). Tap Remove, then add the account again."
                }
                continue
            }
            do {
                print("[CalendarConnections] UI: linked fetch token+list key=\(account.accountKey)")
                let access = try await GoogleLinkedOAuthTokenRefresher.accessToken(
                    refreshToken: refresh,
                    clientId: clientID
                )
                let emailMissing = (account.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
                if emailMissing {
                    let fetched = await GoogleOAuth2UserInfoClient.fetchSubAndEmail(accessToken: access)
                    if let e = fetched.email?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty {
                        store.upsertLinkedAccount(accountKey: account.accountKey, email: e)
                        print("[CalendarConnections] UI: backfilled linked email for key=\(account.accountKey)")
                    }
                }
                let list = try await GoogleCalendarEventFetchService.fetchCalendarList(accessToken: access)
                let filtered = list.filter { readableCalendarAccess($0.accessRole) }
                linked[account.accountKey] = filtered
                print("[CalendarConnections] UI: linked list OK key=\(account.accountKey) calendars=\(filtered.count)")
            } catch {
                print("[CalendarConnections] UI: linked list FAIL key=\(account.accountKey) \(error.localizedDescription)")
                if ConnectionAuthFailureDetector.isGoogleAuthFailure(error) {
                    ConnectionReauthorizationNotifier.requestGoogleCalendar(
                        accountKey: account.accountKey,
                        displayName: account.connectionsDisplayTitle,
                        reason: error.localizedDescription
                    )
                }
                if listLoadError == nil {
                    listLoadError = "Could not load calendars for \(account.connectionsDisplayTitle): \(error.localizedDescription)"
                }
            }
        }
        linkedCalendarRows = linked

        if let user = GIDSignIn.sharedInstance.currentUser,
           user.grantedScopes?.contains(calendarWriteScope) == true {
            print("[CalendarConnections] UI: primary fetch begin (GID refresh + calendarList)")
            do {
                let refreshed = try await refreshGIDUserWithTimeout(user, seconds: 15)
                print("[CalendarConnections] UI: primary GID refresh OK")
                let list = try await GoogleCalendarEventFetchService.fetchCalendarList(
                    accessToken: refreshed.accessToken.tokenString
                )
                let filtered = list.filter { readableCalendarAccess($0.accessRole) }
                primaryCalendarRows = filtered
                print("[CalendarConnections] UI: primary calendarList OK count=\(filtered.count)")
            } catch is GIDRefreshTimeoutError {
                print("[CalendarConnections] UI: primary GID refresh TIMEOUT")
                if listLoadError == nil {
                    listLoadError = "Primary Google calendar list timed out. Pull to refresh or reopen Connections. Linked accounts above are up to date."
                }
            } catch {
                print("[CalendarConnections] UI: primary fetch FAIL \(error.localizedDescription)")
                if ConnectionAuthFailureDetector.isGoogleAuthFailure(error) {
                    ConnectionReauthorizationNotifier.requestGoogleCalendar(
                        displayName: user.profile?.email,
                        reason: error.localizedDescription
                    )
                }
                if listLoadError == nil {
                    listLoadError = error.localizedDescription
                }
            }
        } else {
            print("[CalendarConnections] UI: primary fetch skipped (no GID or no calendar write scope)")
        }
    }

    private struct GIDRefreshTimeoutError: Error {}

    /// Avoids hanging forever if `refreshTokensIfNeeded` never calls back (can happen after external OAuth flows).
    private func refreshGIDUserWithTimeout(_ user: GIDGoogleUser, seconds: TimeInterval) async throws -> GIDGoogleUser {
        print("[CalendarConnections] UI: refreshGIDUserWithTimeout start seconds=\(seconds)")
        return try await withThrowingTaskGroup(of: Result<GIDGoogleUser, Error>.self) { group in
            group.addTask {
                do {
                    return .success(try await self.refreshGIDUser(user))
                } catch {
                    return .failure(error)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return .failure(GIDRefreshTimeoutError())
            }
            guard let first = try await group.next() else {
                throw GIDRefreshTimeoutError()
            }
            group.cancelAll()
            switch first {
            case .success(let user):
                print("[CalendarConnections] UI: refreshGIDUserWithTimeout winner=refresh success")
                return user
            case .failure(let error):
                print("[CalendarConnections] UI: refreshGIDUserWithTimeout winner=\(error)")
                throw error
            }
        }
    }

    private func refreshGIDUser(_ user: GIDGoogleUser) async throws -> GIDGoogleUser {
        print("[CalendarConnections] UI: refreshGIDUser calling refreshTokensIfNeeded…")
        return try await withCheckedThrowingContinuation { cont in
            user.refreshTokensIfNeeded { u, err in
                if let u {
                    print("[CalendarConnections] UI: refreshGIDUser callback OK")
                    cont.resume(returning: u)
                } else {
                    print("[CalendarConnections] UI: refreshGIDUser callback FAIL \(err?.localizedDescription ?? "nil")")
                    cont.resume(throwing: err ?? URLError(.userAuthenticationRequired))
                }
            }
        }
    }
}
