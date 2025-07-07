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
    @State private var showDeleteConfirmationAlert = false // For account deletion
    
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

    // Define dynamic colors for better readability, assuming you have an asset catalog or extension for this
    private var dynamicTextColor: Color { .primary }
    private var dynamicSecondaryTextColor: Color { .secondary }
    private var dynamicBackgroundColor: Color { Color(.systemGroupedBackground) }
    private var dynamicPrimaryColor: Color { .blue }
    private var dynamicSecondaryColor: Color { .green }
    private var dynamicSecondaryBackgroundColor: Color { Color(.secondarySystemGroupedBackground) }
    private var dynamicDestructiveColor: Color { .red }
    private var dynamicAccentColor: Color { .purple }

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
                        if loginViewModel.isGuest {
                            Text("You are currently in Guest Mode. Your data is stored locally on this device. Sign in to save your progress online.")
                                .foregroundColor(.secondary)
                        } else {
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

                    // MARK: Account Management Section
                    if !loginViewModel.isGuest {
                         Section(header: Text("Account Management")) {
                            Button(role: .destructive, action: {
                                print("NotificationSettingsView: Delete Account button tapped.")
                                showDeleteConfirmationAlert = true
                            }) {
                                HStack {
                                    Spacer()
                                    Text("Delete Account Permanently")
                                    Spacer()
                                }
                            }
                        }
                    }

                    Section {
                        Button(action: {
                            print("NotificationSettingsView: Sign Out/Exit Guest Mode button tapped.")
                            onSignOutRequested()
                        }) {
                            HStack {
                                Spacer()
                                Text(loginViewModel.isGuest ? "Exit Guest Mode" : "Sign Out")
                                    .fontWeight(.medium)
                                    .foregroundColor(loginViewModel.isGuest ? .primary : .red)
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
            .alert("Are You Absolutely Sure?", isPresented: $showDeleteConfirmationAlert) {
                Button("Delete My Account", role: .destructive) {
                    loginViewModel.deleteAccount { success, message in
                        if success {
                            // The auth state listener will handle UI changes,
                            // so we can just dismiss this view.
                            dismiss()
                        } else {
                            // Show an error message if deletion fails.
                            nameChangeMessageText = message ?? "An unknown error occurred."
                            nameChangeWasSuccessful = false
                            showTempStatusMessage()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action is permanent and cannot be undone. All your online data, including progress and leaderboard entries, will be erased forever.")
            }
            .onAppear {
                loadNotificationSettings()
                tempLocationToggle = locationRemindersEnabled
                if !loginViewModel.isGuest {
                    editableDisplayName = loginViewModel.userDisplayName ?? ""
                }
                if !hasCompletedNotificationsTutorial {
                    showNotificationsTutorial = true // Uncomment to re-enable tutorial logic
                }
            }
            .onChange(of: loginViewModel.userDisplayName) { _, newName in
                if !isSavingName && editableDisplayName != (newName ?? "") {
                    editableDisplayName = newName ?? ""
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
                    // Optional: any action on successful name change
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

// NOTE: The NotificationsTutorialStep enum and NotificationsTutorialOverlay view are assumed to exist elsewhere in your project.
// If they don't, you may need to comment out the .overlay and related .onChange modifiers to avoid compilation errors.
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
