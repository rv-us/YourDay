//
//  NotificationSettingsView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/12/25.
//

import SwiftUI
import SwiftData
import UserNotifications

let morningReminderKey = "morningReminderTime"
let nightReminderKey = "nightReminderTime"
let notificationsEnabledKey = "notificationsEnabled"
let extraNotificationsKey = "extraNotificationCount"

struct NotificationSettingsView: View {
    @ObservedObject var todoViewModel: TodoViewModel
    @ObservedObject var loginViewModel: LoginViewModel

    @Environment(\.dismiss) var dismiss

    @State private var morningTime = Date()
    @State private var nightTime = Date()
    @State private var showMorningPicker = false
    @State private var showNightPicker = false
    @State private var notificationsEnabled = true
    @State private var showConfirmation = false
    @State private var isSaveButtonDisabled = false
    @State private var extraNotificationCount = 0
    @State private var showExtraPicker = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showConfirmation {
                    Text("Reminders scheduled successfully!")
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Form {
                    Section(header: Text("Account Information")) {
                        // Proper access to the @Published properties in LoginViewModel
                        if let displayName = loginViewModel.userDisplayName, !displayName.isEmpty {
                            HStack {
                                Text("Name:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(displayName)
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        if let email = loginViewModel.userEmail, !email.isEmpty {
                            HStack {
                                Text("Email:")
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(email)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    
                    Section {
                        Toggle("Enable Notifications", isOn: $notificationsEnabled)
                            .onChange(of: notificationsEnabled) { newValue in
                                UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey)
                                if !newValue {
                                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                                    print("🔕 Notifications disabled and cleared.")
                                }
                            }
                    }

                    if notificationsEnabled {
                        Section(header: Text("Morning Reminder")) {
                            Button(action: {
                                withAnimation {
                                    showMorningPicker.toggle()
                                }
                            }) {
                                HStack {
                                    Text("Scheduled at")
                                    Spacer()
                                    Text(morningTime.formatted(date: .omitted, time: .shortened))
                                        .foregroundColor(.gray)
                                }
                            }

                            if showMorningPicker {
                                DatePicker("", selection: $morningTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                            }
                        }

                        Section(header: Text("Night Reminder")) {
                            Button(action: {
                                withAnimation {
                                    showNightPicker.toggle()
                                }
                            }) {
                                HStack {
                                    Text("Scheduled at")
                                    Spacer()
                                    Text(nightTime.formatted(date: .omitted, time: .shortened))
                                        .foregroundColor(.gray)
                                }
                            }

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
                                    Text("\(extraNotificationCount)")
                                        .foregroundColor(.gray)
                                }

                                Slider(value: Binding(
                                    get: { Double(extraNotificationCount) },
                                    set: { newValue in
                                        extraNotificationCount = Int(newValue)
                                        UserDefaults.standard.set(extraNotificationCount, forKey: extraNotificationsKey)
                                    }
                                ), in: 0...10, step: 1)
                            }
                            .padding(.vertical, 4)
                        }

                        Section {
                            Button(action: {
                                saveAndScheduleNotifications()
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Save and Schedule")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(isSaveButtonDisabled ? Color.gray : Color.blue)
                            .cornerRadius(8)
                            .disabled(isSaveButtonDisabled)
                            .opacity(isSaveButtonDisabled ? 0.6 : 1.0)
                        }
                    }
                    
                    Section {
                        Button(action: {
                            loginViewModel.signOut()
                        }) {
                            HStack {
                                Spacer()
                                Text("Sign Out")
                                    .foregroundColor(.red)
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle("Settings")
            }
            .onAppear {
                loadSettings()
                // Refresh user data when view appears
                loginViewModel.checkAuthenticationState()
            }
        }
        .navigationViewStyle(.stack)
    }

    private func saveAndScheduleNotifications() {
        isSaveButtonDisabled = true
        
        UserDefaults.standard.set(morningTime, forKey: morningReminderKey)
        UserDefaults.standard.set(nightTime, forKey: nightReminderKey)
        UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey)
        UserDefaults.standard.set(extraNotificationCount, forKey: extraNotificationsKey)

        if notificationsEnabled {
            let calendar = Calendar.current
            let morningHour = calendar.component(.hour, from: morningTime)
            let morningMinute = calendar.component(.minute, from: morningTime)
            let nightHour = calendar.component(.hour, from: nightTime)
            let nightMinute = calendar.component(.minute, from: nightTime)

            print(
                String(
                    format: "✅ Times scheduled: %02d:%02d (morning), %02d:%02d (night), %d extra",
                    morningHour, morningMinute, nightHour, nightMinute, extraNotificationCount
                )
            )

            todoViewModel.scheduleDailyReminders(
                morningHour: morningHour,
                morningMinute: morningMinute,
                nightHour: nightHour,
                nightMinute: nightMinute,
                extraReminders: extraNotificationCount
            )

            withAnimation {
                showConfirmation = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showConfirmation = false
                }
            }
        } else {
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isSaveButtonDisabled = false
        }
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: notificationsEnabledKey) != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
        } else {
            notificationsEnabled = true
            UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey)
        }

        if let savedMorning = UserDefaults.standard.object(forKey: morningReminderKey) as? Date {
            morningTime = savedMorning
        } else {
            morningTime = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
        }

        if let savedNight = UserDefaults.standard.object(forKey: nightReminderKey) as? Date {
            nightTime = savedNight
        } else {
            nightTime = Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()
        }
        
        if UserDefaults.standard.object(forKey: extraNotificationsKey) != nil {
             extraNotificationCount = UserDefaults.standard.integer(forKey: extraNotificationsKey)
        } else {
            extraNotificationCount = 0
        }
    }
}
