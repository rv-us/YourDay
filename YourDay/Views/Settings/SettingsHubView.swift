import SwiftUI

struct SettingsHubView: View {
    @ObservedObject var todoViewModel: TodoViewModel
    @ObservedObject var loginViewModel: LoginViewModel
    var onSignOutRequested: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        NotificationSettingsView(
                            todoViewModel: todoViewModel,
                            loginViewModel: loginViewModel,
                            onSignOutRequested: onSignOutRequested
                        )
                    } label: {
                        settingsRow(
                            icon: "bell.fill",
                            title: "Notifications & Account",
                            subtitle: "Reminders, location alerts, profile"
                        )
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)

                    NavigationLink {
                        ScreenTimeSettingsView()
                    } label: {
                        settingsRow(
                            icon: "shield.lefthalf.filled",
                            title: "Focus Blocker",
                            subtitle: "Soft-block distracting apps"
                        )
                    }
                    .listRowBackground(dynamicSecondaryBackgroundColor)
                } header: {
                    Text("Settings")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                }
            }
            .scrollContentBackground(.hidden)
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder
    private func settingsRow(icon: String, title: String, subtitle: String) -> some View {
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
