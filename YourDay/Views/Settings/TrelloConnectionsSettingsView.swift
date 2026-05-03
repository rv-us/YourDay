//
//  TrelloConnectionsSettingsView.swift
//  YourDay
//

import AuthenticationServices
import SwiftUI
import SwiftData
import UIKit

struct TrelloConnectionsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var store = TrelloConnectionsSettingsStore.shared

    @State private var boardRows: [TrelloBoardAPIItem] = []
    @State private var isLoadingBoards = false
    @State private var listLoadError: String?
    @State private var isConnecting = false
    @State private var isImportingTasks = false
    @State private var oauthBanner: String?
    @State private var importBanner: String?

    var body: some View {
        List {
            Section {
                Text("Linking lets YourDay read and write Trello on your behalf. After connecting, choose which boards YourDay may use.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .listRowBackground(dynamicSecondaryBackgroundColor)

                if TrelloConnectionKeychain.loadUserToken() != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                        Text(memberDisplayTitle)
                            .foregroundColor(dynamicTextColor)
                            .font(.body.weight(.semibold))
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)

                    Button("Disconnect Trello", role: .destructive) {
                        disconnect()
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } else {
                    Button {
                        startConnectTrello()
                    } label: {
                        if isConnecting {
                            HStack {
                                ProgressView()
                                Text("Opening Trello…")
                            }
                        } else {
                            Text("Connect Trello")
                        }
                    }
                    .disabled(isConnecting)
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                if let oauthBanner {
                    Text(oauthBanner)
                        .font(.caption)
                        .foregroundColor(dynamicDestructiveColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            } header: {
                Text("Account")
                    .foregroundColor(dynamicTextColor)
            }

            if TrelloConnectionKeychain.loadUserToken() != nil {
                Section {
                    Button {
                        startManualImport()
                    } label: {
                        if isImportingTasks {
                            HStack {
                                ProgressView()
                                Text("Importing Trello tasks…")
                            }
                        } else {
                            Label("Import Trello tasks now", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isImportingTasks)
                    .listRowBackground(dynamicSecondaryBackgroundColor)

                    if let importBanner {
                        Text(importBanner)
                            .font(.caption)
                            .foregroundColor(dynamicSecondaryTextColor)
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                } header: {
                    Text("Manual import")
                        .foregroundColor(dynamicTextColor)
                } footer: {
                    Text("Imports open cards from enabled boards that are assigned to you, then updates matching Trello tasks already in YourDay.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                }
            }

            Section {
                if TrelloConnectionKeychain.loadUserToken() == nil {
                    Text("Connect Trello to choose boards.")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                } else if isLoadingBoards {
                    HStack {
                        ProgressView()
                        Text("Loading boards…")
                            .foregroundColor(dynamicSecondaryTextColor)
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } else if let listLoadError {
                    Text(listLoadError)
                        .font(.caption)
                        .foregroundColor(dynamicDestructiveColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }

                if !boardRows.isEmpty {
                    Text("Boards YourDay can use")
                        .font(.caption)
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)

                    ForEach(boardRows.filter { $0.closed != true }) { item in
                        let boardId = item.id
                        let allIds = boardRows.filter { $0.closed != true }.map(\.id)
                        Toggle(
                            isOn: Binding(
                                get: {
                                    store.isBoardEnabled(boardId: boardId, allBoardIds: allIds)
                                },
                                set: { on in
                                    store.applyBoardToggle(boardId: boardId, isOn: on, allBoardIds: allIds)
                                    if !on {
                                        TrelloTaskSyncService.purgeMirroredTasksNotInEnabledBoards(modelContext: modelContext)
                                    }
                                }
                            )
                        ) {
                            Text(item.name ?? boardId)
                                .foregroundColor(dynamicTextColor)
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }

                    if boardRows.allSatisfy({ $0.closed == true }) {
                        Text("No open boards found.")
                            .foregroundColor(dynamicSecondaryTextColor)
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                } else if TrelloConnectionKeychain.loadUserToken() != nil, !isLoadingBoards, listLoadError == nil {
                    Text("No boards returned.")
                        .foregroundColor(dynamicSecondaryTextColor)
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                }
            } header: {
                Text("Boards")
                    .foregroundColor(dynamicTextColor)
            } footer: {
                Text("Closed boards are hidden. YourDay only loads data for boards you leave enabled.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .navigationTitle("Trello")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await reloadBoardsIfLinked()
        }
    }

    private var memberDisplayTitle: String {
        if let name = store.root.memberFullName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let u = store.root.memberUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            return "@\(u)"
        }
        return "Trello account"
    }

    private func disconnect() {
        TrelloTaskSyncService.purgeAllMirroredTasks(modelContext: modelContext)
        TrelloConnectionKeychain.deleteUserToken()
        store.clearAllPreferences()
        boardRows = []
        listLoadError = nil
        oauthBanner = nil
        importBanner = nil
    }

    private func startConnectTrello() {
        oauthBanner = nil
        guard let anchor = presentationAnchor() else {
            oauthBanner = "Could not open sign-in."
            return
        }
        isConnecting = true
        TrelloOAuthCoordinator.shared.start(presentationAnchor: anchor) { result in
            Task { @MainActor in
                isConnecting = false
                switch result {
                case .success(let token):
                    do {
                        try TrelloConnectionKeychain.saveUserToken(token)
                        await reloadBoardsIfLinked()
                    } catch {
                        oauthBanner = error.localizedDescription
                    }
                case .failure(let error):
                    if let te = error as? TrelloOAuthError {
                        switch te {
                        case .userCancelled:
                            oauthBanner = nil
                        default:
                            oauthBanner = te.localizedDescription
                        }
                    } else {
                        oauthBanner = error.localizedDescription
                    }
                }
            }
        }
    }

    private func presentationAnchor() -> ASPresentationAnchor? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    }

    private func startManualImport() {
        importBanner = nil
        isImportingTasks = true
        Task { @MainActor in
            await TrelloTaskSyncService.refreshTrelloMirroredTasks(modelContext: modelContext)
            isImportingTasks = false
            importBanner = "Trello tasks imported. Today and Master List are up to date."
        }
    }

    @MainActor
    private func reloadBoardsIfLinked() async {
        listLoadError = nil
        guard let token = TrelloConnectionKeychain.loadUserToken() else {
            boardRows = []
            return
        }
        isLoadingBoards = true
        defer { isLoadingBoards = false }
        do {
            let member = try await TrelloAPIClient.memberMe(token: token)
            store.setMemberLabels(memberId: member.id, fullName: member.fullName, username: member.username)
            let boards = try await TrelloAPIClient.memberBoards(token: token)
            boardRows = boards
        } catch {
            listLoadError = error.localizedDescription
        }
    }
}
