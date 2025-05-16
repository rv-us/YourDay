//
//  NotificationSettingsView.swift
//  YourDay
//
//  Created by Ruthwika Gajjala on 5/12/25.
//

import SwiftUI
import SwiftData

let morningReminderKey = "morningReminderTime"
let nightReminderKey = "nightReminderTime"
let notificationsEnabledKey = "notificationsEnabled"
let extraNotificationsKey = "extraNotificationCount"

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: TodoViewModel
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
                                isSaveButtonDisabled = true
                                saveReminderTimes()

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

                                viewModel.scheduleDailyReminders(
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
                                        isSaveButtonDisabled = false
                                    }
                                }
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
                }
                .navigationTitle("Notification Settings")
            }
            .onAppear {
                loadReminderTimes()
                notificationsEnabled = UserDefaults.standard.bool(forKey: notificationsEnabledKey)
                extraNotificationCount = UserDefaults.standard.integer(forKey: extraNotificationsKey)
            }
        }
    }

    private func saveReminderTimes() {
        UserDefaults.standard.set(morningTime, forKey: morningReminderKey)
        UserDefaults.standard.set(nightTime, forKey: nightReminderKey)
    }

    private func loadReminderTimes() {
        if let savedMorning = UserDefaults.standard.object(forKey: morningReminderKey) as? Date {
            morningTime = savedMorning
        } else {
            morningTime = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
        }

        if let savedNight = UserDefaults.standard.object(forKey: nightReminderKey) as? Date {
            nightTime = savedNight
        } else {
            nightTime = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
        }
    }
}
