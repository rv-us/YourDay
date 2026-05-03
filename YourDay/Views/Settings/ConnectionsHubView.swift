//
//  ConnectionsHubView.swift
//  YourDay
//

import SwiftUI

struct ConnectionsHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    CalendarConnectionsSettingsView()
                } label: {
                    connectionRow(
                        icon: "calendar",
                        title: "Google Calendar",
                        subtitle: "Primary account, visibility, linked calendars"
                    )
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)

                NavigationLink {
                    TrelloConnectionsSettingsView()
                } label: {
                    connectionRow(
                        icon: "rectangle.on.rectangle.angled",
                        title: "Trello",
                        subtitle: "Link account, choose boards"
                    )
                }
                .listRowBackground(dynamicSecondaryBackgroundColor)
            } header: {
                Text("Integrations")
                    .foregroundColor(dynamicTextColor)
            } footer: {
                Text("YourDay only uses Trello boards you enable after connecting.")
                    .font(.caption)
                    .foregroundColor(dynamicSecondaryTextColor)
            }
        }
        .scrollContentBackground(.hidden)
        .background(dynamicBackgroundColor.ignoresSafeArea())
        .listStyle(.insetGrouped)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder
    private func connectionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(dynamicSecondaryColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(dynamicTextColor)
                    .font(.body)
                Text(subtitle)
                    .foregroundColor(dynamicSecondaryTextColor)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}
