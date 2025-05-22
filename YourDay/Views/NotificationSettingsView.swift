//
//  NotificationSettingsView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/12/25.
//
import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation

// Global keys
let morningReminderKey = "morningReminderTime"
let nightReminderKey = "nightReminderTime"
let notificationsEnabledKey = "notificationsEnabled"
let extraNotificationsKey = "extraNotificationCount"
let locationRemindersEnabledKey = "locationRemindersEnabled"

// Identifiers to remove only scheduled reminders
let scheduledReminderIDs: [String] = ["morningReminder", "nightReminder"] + (1...10).map { "extraReminder\($0)" }

struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var todoViewModel: TodoViewModel
    @ObservedObject var loginViewModel: LoginViewModel
    @AppStorage(locationRemindersEnabledKey) private var locationRemindersEnabled = true
    var onSignOutRequested: () -> Void

    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? { playerStatsList.first }

    @Environment(\.dismiss) var dismiss

    @State private var morningTime = Date()
    @State private var nightTime = Date()
    @State private var showMorningPicker = false
    @State private var showNightPicker = false
    @State private var notificationsEnabled = true
    @State private var showNotificationSaveConfirmation = false
    @State private var isNotificationSaveButtonDisabled = false
    @State private var extraNotificationCount = 0

    @State private var editableDisplayName: String = ""
    @State private var showNameChangeStatusMessage = false
    @State private var nameChangeMessageText = ""
    @State private var nameChangeWasSuccessful = false
    @State private var isSavingName = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showNotificationSaveConfirmation {
                    Text("Reminders scheduled successfully!")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showNameChangeStatusMessage {
                    Text(nameChangeMessageText)
                        .foregroundColor(nameChangeWasSuccessful ? .green : .red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Form {
                    Section(header: Text("Account Information")) {
                        HStack {
                            Text("Email:").fontWeight(.semibold)
                            Spacer()
                            Text(loginViewModel.userEmail ?? "Not available").foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading) {
                            Text("Display Name:").fontWeight(.semibold)
                            TextField("Enter display name", text: $editableDisplayName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!loginViewModel.isNetworkAvailable || isSavingName)
                                .textContentType(.name)
                                .autocapitalization(.words)

                            if loginViewModel.isNetworkAvailable {
                                Button(action: saveNewDisplayName) {
                                    HStack {
                                        Spacer()
                                        if isSavingName {
                                            ProgressView()
                                        } else {
                                            Text("Save Name")
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(.top, 5)
                                .disabled(editableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                          editableDisplayName == (loginViewModel.userDisplayName ?? "") ||
                                          isSavingName)
                            } else {
                                Text("Connect to internet to change display name.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 5)
                    }

                    Section(header: Text("General Notification Settings")) {
                        Toggle("Enable Scheduled Notifications", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
                                if !newValue {
                                    UNUserNotificationCenter.current()
                                        .removePendingNotificationRequests(withIdentifiers: scheduledReminderIDs)
                                }
                            }

                        Toggle("Enable Location-Based Reminders", isOn: $locationRemindersEnabled)
                            .onChange(of: locationRemindersEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: locationRemindersEnabledKey)
                            }
                    }

                    if notificationsEnabled {
                        Section(header: Text("Morning Reminder")) {
                            Button(action: { withAnimation { showMorningPicker.toggle() } }) {
                                HStack {
                                    Text("Scheduled at")
                                    Spacer()
                                    Text(morningTime.formatted(date: .omitted, time: .shortened)).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if showMorningPicker {
                                DatePicker("", selection: $morningTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                            }
                        }

                        Section(header: Text("Night Reminder")) {
                            Button(action: { withAnimation { showNightPicker.toggle() } }) {
                                HStack {
                                    Text("Scheduled at")
                                    Spacer()
                                    Text(nightTime.formatted(date: .omitted, time: .shortened)).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if showNightPicker {
                                DatePicker("", selection: $nightTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                            }
                        }

                        Section(header: Text("Additional Task Reminders")) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Reminders per day")
                                    Spacer()
                                    Text("\(extraNotificationCount)").foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { Double(extraNotificationCount) },
                                    set: { extraNotificationCount = Int($0) }),
                                       in: 0...10, step: 1)
                            }
                            .padding(.vertical, 4)
                        }

                        Section {
                            Button(action: saveAndScheduleNotifications) {
                                HStack {
                                    Spacer()
                                    Text("Save Reminder Settings")
                                    Spacer()
                                }
                            }
                            .listRowBackground(isNotificationSaveButtonDisabled || !notificationsEnabled ? Color.gray.opacity(0.5) : Color.blue)
                            .foregroundColor(.white)
                            .disabled(isNotificationSaveButtonDisabled || !notificationsEnabled)
                        }
                    }

                    Section {
                        Button(role: .destructive, action: {
                            print("NotificationSettingsView: Sign Out button tapped.")
                            onSignOutRequested()
                        }) {
                            HStack {
                                Spacer()
                                Text("Sign Out").fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle("Settings & Account")
            }
            .onAppear {
                loadNotificationSettings()
                editableDisplayName = loginViewModel.userDisplayName ?? ""
            }
            .onChange(of: loginViewModel.userDisplayName) { _, newName in
                if editableDisplayName != (newName ?? "") {
                    editableDisplayName = newName ?? ""
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveNewDisplayName() {
        let trimmed = editableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameChangeMessageText = "Display name cannot be empty."
            nameChangeWasSuccessful = false
            showTempStatusMessage()
            return
        }

        guard trimmed != (loginViewModel.userDisplayName ?? "") else {
            nameChangeMessageText = "Name is already set to this."
            nameChangeWasSuccessful = true
            showTempStatusMessage()
            return
        }

        isSavingName = true
        loginViewModel.updateUserDisplayName(newName: trimmed, currentPlayerStats: currentPlayerStats) { success, message in
            isSavingName = false
            nameChangeMessageText = message ?? (success ? "Display name updated successfully!" : "Failed to update display name.")
            nameChangeWasSuccessful = success
            showTempStatusMessage()
        }
    }

    private func showTempStatusMessage() {
        withAnimation { showNameChangeStatusMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { showNameChangeStatusMessage = false }
        }
    }

    private func saveAndScheduleNotifications() {
        isNotificationSaveButtonDisabled = true

        UserDefaults.standard.set(morningTime, forKey: morningReminderKey)
        UserDefaults.standard.set(nightTime, forKey: nightReminderKey)
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey)
        UserDefaults.standard.set(extraNotificationCount, forKey: extraNotificationsKey)
        UserDefaults.standard.set(locationRemindersEnabled, forKey: locationRemindersEnabledKey)

        if notificationsEnabled {
            let calendar = Calendar.current
            let morningHour = calendar.component(.hour, from: morningTime)
            let morningMinute = calendar.component(.minute, from: morningTime)
            let nightHour = calendar.component(.hour, from: nightTime)
            let nightMinute = calendar.component(.minute, from: nightTime)

            todoViewModel.scheduleDailyReminders(
                morningHour: morningHour,
                morningMinute: morningMinute,
                nightHour: nightHour,
                nightMinute: nightMinute,
                extraReminders: extraNotificationCount
            )

            withAnimation { showNotificationSaveConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showNotificationSaveConfirmation = false }
            }
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: scheduledReminderIDs)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isNotificationSaveButtonDisabled = false
        }
    }

    private func loadNotificationSettings() {
        notificationsEnabled = UserDefaults.standard.object(forKey: notificationsEnabledKey) as? Bool ?? true
        morningTime = UserDefaults.standard.object(forKey: morningReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
        nightTime = UserDefaults.standard.object(forKey: nightReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
        extraNotificationCount = UserDefaults.standard.object(forKey: extraNotificationsKey) as? Int ?? 0
        locationRemindersEnabled = UserDefaults.standard.object(forKey: locationRemindersEnabledKey) as? Bool ?? true
    }
}
