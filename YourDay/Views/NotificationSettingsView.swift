import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation

let morningReminderKey = "morningReminderTime"
let nightReminderKey = "nightReminderTime"
let notificationsEnabledKey = "notificationsEnabled"
let extraNotificationsKey = "extraNotificationCount"
let locationRemindersEnabledKey = "locationRemindersEnabled"

let scheduledReminderIDs: [String] = ["morningReminder", "nightReminder"] + (1...10).map { "extraReminder\($0)" }

let profanityList: [String] = ["badword", "curse", "profane"]

struct NotificationSettingsView: View {
    @AppStorage("hasCompletedNotificationsTutorial") private var hasCompletedNotificationsTutorial = false
    @State private var showNotificationsTutorial = false
    @State private var currentNotificationTutorialStep: NotificationsTutorialStep = .welcome
    @State private var acknowledgedSteps: Set<NotificationsTutorialStep> = []
    @State private var tempLocationToggle = false
    @State private var showPermissionDeniedAlert = false
    
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var todoViewModel: TodoViewModel
    @ObservedObject var loginViewModel: LoginViewModel
    @EnvironmentObject var locationManager: LocationManager
    @AppStorage(locationRemindersEnabledKey) private var locationRemindersEnabled = true
    var onSignOutRequested: () -> Void

    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? { playerStatsList.first }

    @Environment(\.dismiss) var dismiss
    private let firebaseManager = FirebaseManager()

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
    
    private let displayNameCharacterLimit = 20

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if showNotificationSaveConfirmation {
                    Text("Reminders scheduled successfully!")
                        .foregroundColor(dynamicSecondaryColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(dynamicSecondaryBackgroundColor.opacity(0.3))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if showNameChangeStatusMessage {
                    Text(nameChangeMessageText)
                        .foregroundColor(nameChangeWasSuccessful ? dynamicSecondaryColor : dynamicDestructiveColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(dynamicSecondaryBackgroundColor.opacity(0.3))
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
                            Text("Display Name: (\(editableDisplayName.count)/\(displayNameCharacterLimit))").fontWeight(.semibold)
                            TextField("Enter display name", text: $editableDisplayName)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!loginViewModel.isNetworkAvailable || isSavingName)
                                .textContentType(.name)
                                .autocapitalization(.words)
                                .onChange(of: editableDisplayName) { _, newValue in
                                    if newValue.count > displayNameCharacterLimit {
                                        editableDisplayName = String(newValue.prefix(displayNameCharacterLimit))
                                    }
                                }

                            if loginViewModel.isNetworkAvailable {
                                Button(action: validateAndSaveDisplayName) {
                                    HStack {
                                        Spacer()
                                        if isSavingName {
                                            ProgressView().scaleEffect(0.8)
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
                                    .foregroundColor(dynamicAccentColor)
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

                        Toggle("Enable Location-Based Reminders", isOn: $tempLocationToggle)
                            .onChange(of: tempLocationToggle) { _, newValue in
                                if newValue {
                                    locationManager.requestPermissions { granted in
                                        DispatchQueue.main.async {
                                            if granted {
                                                locationRemindersEnabled = true
                                                UserDefaults.standard.set(true, forKey: locationRemindersEnabledKey)
                                            } else {
                                                locationRemindersEnabled = false
                                                UserDefaults.standard.set(false, forKey: locationRemindersEnabledKey)
                                                tempLocationToggle = false
                                                showPermissionDeniedAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    locationRemindersEnabled = false
                                    UserDefaults.standard.set(false, forKey: locationRemindersEnabledKey)
                                }
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
                            .listRowBackground(isNotificationSaveButtonDisabled || !notificationsEnabled ? Color.gray.opacity(0.5) : dynamicPrimaryColor)
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
            .alert("Location Access Denied", isPresented: $showPermissionDeniedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Please enable location access in Settings to receive smart reminders.")
            }
            .onAppear {
                loadNotificationSettings()
                tempLocationToggle = locationRemindersEnabled
                editableDisplayName = loginViewModel.userDisplayName ?? ""
                if !hasCompletedNotificationsTutorial {
                }
            }
            .onChange(of: notificationsEnabled) { _, newVal in
                if currentNotificationTutorialStep == .toggleScheduled &&
                   newVal && acknowledgedSteps.contains(.toggleScheduled) {
                    currentNotificationTutorialStep = .toggleLocation
                }
            }
            .onChange(of: locationRemindersEnabled) { _, newVal in
                if currentNotificationTutorialStep == .toggleLocation &&
                   newVal && acknowledgedSteps.contains(.toggleLocation) {
                    currentNotificationTutorialStep = .setTimes
                }
            }
            .onChange(of: morningTime) { _, _ in
                if currentNotificationTutorialStep == .setTimes &&
                   acknowledgedSteps.contains(.setTimes) {
                    currentNotificationTutorialStep = .extraReminders
                }
            }
            .onChange(of: extraNotificationCount) { _, _ in
                if currentNotificationTutorialStep == .extraReminders &&
                   acknowledgedSteps.contains(.extraReminders) {
                    currentNotificationTutorialStep = .finished
                }
            }
            .overlay(
                Group {
                    if showNotificationsTutorial {
                        NotificationsTutorialOverlay(
                            currentStep: $currentNotificationTutorialStep,
                            isActive: $showNotificationsTutorial,
                            hasCompletedTutorial: $hasCompletedNotificationsTutorial
                        )
                    }
                }
            )
            .onChange(of: loginViewModel.userDisplayName) { _, newName in
                if !isSavingName && editableDisplayName != (newName ?? "") {
                    editableDisplayName = newName ?? ""
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func containsProfanity(_ text: String) -> Bool {
        let lowercasedText = text.lowercased()
        for word in profanityList {
            if lowercasedText.contains(word.lowercased()) {
                return true
            }
        }
        return false
    }

    private func validateAndSaveDisplayName() {
        let trimmedName = editableDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            nameChangeMessageText = "Display name cannot be empty."
            nameChangeWasSuccessful = false
            showTempStatusMessage()
            return
        }

        guard trimmedName.count <= displayNameCharacterLimit else {
            nameChangeMessageText = "Display name cannot exceed \(displayNameCharacterLimit) characters."
            nameChangeWasSuccessful = false
            showTempStatusMessage()
            return
        }

        if containsProfanity(trimmedName) {
            nameChangeMessageText = "Display name contains inappropriate language."
            nameChangeWasSuccessful = false
            showTempStatusMessage()
            return
        }

        guard trimmedName != (loginViewModel.userDisplayName ?? "") else {
            nameChangeMessageText = "This is already your display name."
            nameChangeWasSuccessful = true
            showTempStatusMessage()
            return
        }

        isSavingName = true
        nameChangeMessageText = ""

        firebaseManager.checkDisplayNameExists(displayName: trimmedName) { exists, error in
            if let error = error {
                nameChangeMessageText = "Error checking name: \(error.localizedDescription)"
                nameChangeWasSuccessful = false
                isSavingName = false
                showTempStatusMessage()
                return
            }

            if exists {
                nameChangeMessageText = "This display name is already taken. Please choose another."
                nameChangeWasSuccessful = false
                isSavingName = false
                showTempStatusMessage()
                return
            }

            loginViewModel.updateUserDisplayName(newName: trimmedName, currentPlayerStats: currentPlayerStats) { success, message in
                isSavingName = false
                nameChangeMessageText = message ?? (success ? "Display name updated successfully!" : "Failed to update display name.")
                nameChangeWasSuccessful = success
                showTempStatusMessage()
                if success {
                }
            }
        }
    }


    private func showTempStatusMessage() {
        withAnimation { showNameChangeStatusMessage = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
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

enum NotificationsTutorialStep: Int, CaseIterable {
    case welcome, toggleScheduled, toggleLocation, setTimes, extraReminders, finished

    var title: String {
        switch self {
        case .welcome: return "Customize Notifications"
        case .toggleScheduled: return "Enable Daily Reminders"
        case .toggleLocation: return "Enable Location Reminders"
        case .setTimes: return "Set Morning & Night Times"
        case .extraReminders: return "Adjust Extra Reminders"
        case .finished: return "You're All Set!"
        }
    }

    var message: String {
        switch self {
        case .welcome: return "Set up notifications to stay on track with your tasks."
        case .toggleScheduled: return "Use this switch to enable your morning and night task reminders."
        case .toggleLocation: return "Turn this on to receive reminders based on where you are."
        case .setTimes: return "Pick times for your morning and night reminders."
        case .extraReminders: return "Slide to add extra check-ins throughout the day."
        case .finished: return "Notifications are now configured to support your productivity!"
        }
    }

    var nextButtonText: String {
        self == .finished ? "Done" : "Next"
    }

    var requiresUserAction: Bool {
        switch self {
        case .toggleScheduled, .toggleLocation, .setTimes, .extraReminders:
            return true
        default:
            return false
        }
    }
}
