import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation
import PhotosUI
import UniformTypeIdentifiers

private struct PickedImageData: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedImageData(data: data)
        }
    }
}

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
    @AppStorage(NotificationManager.locationRemindersEnabledKey) private var locationRemindersEnabled = true
    var onSignOutRequested: () -> Void

    @Query(sort: \PlayerStats.playerLevel) private var playerStatsList: [PlayerStats]
    private var currentPlayerStats: PlayerStats? { playerStatsList.first }

    @Environment(\.dismiss) var dismiss
    private let firebaseManager = FirebaseManager()

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isUploadingPhoto = false
    @State private var showRemovePhotoConfirm = false

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

    // Use global dynamic colors for consistency
    // Note: These are imported from Shopview.swift where they're defined

    var body: some View {
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
                    Section(header: Text("Account Information")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                    ) {
                        if loginViewModel.isGuest {
                            Text("You are currently in Guest Mode. Your data is stored locally on this device. Sign in to save your progress online.")
                                .foregroundColor(dynamicSecondaryTextColor)
                                .listRowBackground(dynamicSecondaryBackgroundColor)
                        } else {
                            // Profile Photo
                            VStack(spacing: 12) {
                                if let photoURL = loginViewModel.userProfilePhotoURL, let url = URL(string: photoURL) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Image(systemName: "person.crop.circle.fill")
                                                .resizable().scaledToFit()
                                                .foregroundColor(dynamicPrimaryColor)
                                        }
                                    }
                                    .frame(width: 90, height: 90)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(dynamicPrimaryColor, lineWidth: 2))
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable().scaledToFit()
                                        .frame(width: 90, height: 90)
                                        .foregroundColor(dynamicPrimaryColor.opacity(0.5))
                                }

                                HStack(spacing: 16) {
                                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                        Label(loginViewModel.userProfilePhotoURL != nil ? "Change Photo" : "Add Photo",
                                              systemImage: "photo.on.rectangle.angled")
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(dynamicPrimaryColor)
                                    }
                                    .disabled(isUploadingPhoto)

                                    if loginViewModel.userProfilePhotoURL != nil {
                                        Button(role: .destructive) {
                                            showRemovePhotoConfirm = true
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                                .font(.subheadline.weight(.medium))
                                        }
                                        .disabled(isUploadingPhoto)
                                    }
                                }

                                if isUploadingPhoto {
                                    ProgressView("Uploading…").scaleEffect(0.8)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                            .onChange(of: selectedPhotoItem) { _, newItem in
                                guard let newItem = newItem else {
                                    print("ProfilePhoto: selectedPhotoItem was nil")
                                    return
                                }
                                print("ProfilePhoto: photo selected, starting load...")
                                isUploadingPhoto = true
                                Task {
                                    do {
                                        if let picked = try await newItem.loadTransferable(type: PickedImageData.self) {
                                            print("ProfilePhoto: loaded \(picked.data.count) bytes, compressing...")
                                            let compressed = compressProfileImage(picked.data)
                                            print("ProfilePhoto: compressed to \(compressed.count) bytes, uploading...")
                                            loginViewModel.uploadProfilePhoto(imageData: compressed) { success, errorMsg in
                                                print("ProfilePhoto: upload result — success=\(success), error=\(errorMsg ?? "none")")
                                                isUploadingPhoto = false
                                            }
                                        } else {
                                            print("ProfilePhoto: loadTransferable returned nil (PickedImageData)")
                                            isUploadingPhoto = false
                                        }
                                    } catch {
                                        print("ProfilePhoto: loadTransferable threw error: \(error)")
                                        isUploadingPhoto = false
                                    }
                                    selectedPhotoItem = nil
                                }
                            }
                            .alert("Remove Profile Photo?", isPresented: $showRemovePhotoConfirm) {
                                Button("Cancel", role: .cancel) { }
                                Button("Remove", role: .destructive) {
                                    loginViewModel.deleteProfilePhoto { _, _ in }
                                }
                            }

                            HStack {
                                Text("Email:").fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                                Spacer()
                                Text(loginViewModel.userEmail ?? "Not available").foregroundColor(dynamicSecondaryTextColor)
                            }
                            .listRowBackground(dynamicSecondaryBackgroundColor)

                            VStack(alignment: .leading) {
                                Text("Display Name: (\(editableDisplayName.count)/\(displayNameCharacterLimit))").fontWeight(.semibold)
                                    .foregroundColor(dynamicTextColor)
                                AppTextField(placeholder: "Enter display name", text: $editableDisplayName)
                                    .padding(8)
                                    .background(dynamicSecondaryBackgroundColor)
                                    .cornerRadius(8)
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
                                                    .foregroundColor(.white)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .padding(.top, 5)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(dynamicPrimaryColor)
                                    .cornerRadius(8)
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
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                        }
                    }

                    Section(header: Text("General Notification Settings")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                    ) {
                        Toggle("Enable Scheduled Notifications", isOn: $notificationsEnabled)
                            .foregroundColor(dynamicTextColor)
                            .onChange(of: notificationsEnabled) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: NotificationManager.notificationsEnabledKey)
                                if !newValue {
                                    UNUserNotificationCenter.current()
                                        .removePendingNotificationRequests(withIdentifiers: NotificationManager.scheduledReminderIDs)
                                    NotificationManager.shared.cancelAllJournalPromptNotifications()
                                    NotificationManager.shared.cancelAllPreTaskNotifications()
                                }
                            }
                            .listRowBackground(dynamicSecondaryBackgroundColor)

                        Toggle("Enable Location-Based Reminders", isOn: $tempLocationToggle)
                            .foregroundColor(dynamicTextColor)
                            .onChange(of: tempLocationToggle) { _, newValue in
                                if newValue {
                                    locationManager.requestPermissions { granted in
                                        DispatchQueue.main.async {
                                            if granted {
                                                locationRemindersEnabled = true
                                                UserDefaults.standard.set(true, forKey: NotificationManager.locationRemindersEnabledKey)
                                            } else {
                                                locationRemindersEnabled = false
                                                UserDefaults.standard.set(false, forKey: NotificationManager.locationRemindersEnabledKey)
                                                tempLocationToggle = false
                                                showPermissionDeniedAlert = true
                                            }
                                        }
                                    }
                                } else {
                                    locationRemindersEnabled = false
                                    UserDefaults.standard.set(false, forKey: NotificationManager.locationRemindersEnabledKey)
                                    GeofenceManager.shared.clearAllGeofences()
                                }
                            }
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                    }

                    if notificationsEnabled {
                        Section(header: Text("Morning Reminder")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                    ) {
                            Button(action: { withAnimation { showMorningPicker.toggle() } }) {
                                HStack {
                                    Text("Scheduled at")
                                        .foregroundColor(dynamicTextColor)
                                    Spacer()
                                    Text(morningTime.formatted(date: .omitted, time: .shortened)).foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(dynamicSecondaryBackgroundColor)

                            if showMorningPicker {
                                DatePicker("", selection: $morningTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .accentColor(dynamicPrimaryColor)
                                    .listRowBackground(dynamicSecondaryBackgroundColor)
                                    .colorScheme(.light)
                            }
                        }

                        Section(header: Text("Night Reminder")
                            .foregroundColor(dynamicTextColor)
                            .font(.headline)
                        ) {
                            Button(action: { withAnimation { showNightPicker.toggle() } }) {
                                HStack {
                                    Text("Scheduled at")
                                        .foregroundColor(dynamicTextColor)
                                    Spacer()
                                    Text(nightTime.formatted(date: .omitted, time: .shortened)).foregroundColor(dynamicSecondaryTextColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(dynamicSecondaryBackgroundColor)

                            if showNightPicker {
                                DatePicker("", selection: $nightTime, displayedComponents: [.hourAndMinute])
                                    .datePickerStyle(.wheel)
                                    .labelsHidden()
                                    .accentColor(dynamicPrimaryColor)
                                    .listRowBackground(dynamicSecondaryBackgroundColor)
                                    .colorScheme(.light)
                            }
                        }

                        Section(header: Text("Additional Task Reminders")
                            .foregroundColor(dynamicTextColor)
                            .font(.headline)
                        ) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("Reminders per day")
                                        .foregroundColor(dynamicTextColor)
                                    Spacer()
                                    Text("\(extraNotificationCount)").foregroundColor(dynamicSecondaryTextColor)
                                }
                                Slider(value: Binding(
                                    get: { Double(extraNotificationCount) },
                                    set: { extraNotificationCount = Int($0) }),
                                       in: 0...10, step: 1)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(dynamicSecondaryBackgroundColor)
                        }

                        Section {
                            Button(action: saveAndScheduleNotifications) {
                                HStack {
                                    Spacer()
                                    Text("Save Reminder Settings")
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                            }
                            .listRowBackground(isNotificationSaveButtonDisabled || !notificationsEnabled ? Color.gray.opacity(0.5) : dynamicPrimaryColor)
                            .disabled(isNotificationSaveButtonDisabled || !notificationsEnabled)
                        }
                    }

                    // MARK: Account Management Section
                    if !loginViewModel.isGuest {
                         Section(header: Text("Account Management")
                        .foregroundColor(dynamicTextColor)
                        .font(.headline)
                    ) {
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
                            .listRowBackground(dynamicSecondaryBackgroundColor)
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
                                    .foregroundColor(loginViewModel.isGuest ? dynamicTextColor : dynamicDestructiveColor)
                                Spacer()
                            }
                        }
                        .listRowBackground(dynamicSecondaryBackgroundColor)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(dynamicBackgroundColor)
                .listStyle(PlainListStyle())
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(dynamicSecondaryBackgroundColor, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Settings & Account")
                            .fontWeight(.bold)
                            .foregroundColor(dynamicTextColor)
                    }
                }
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
            .background(dynamicBackgroundColor.edgesIgnoringSafeArea(.all))
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

        UserDefaults.standard.set(morningTime, forKey: NotificationManager.morningReminderKey)
        UserDefaults.standard.set(nightTime, forKey: NotificationManager.nightReminderKey)
        UserDefaults.standard.set(notificationsEnabled, forKey: NotificationManager.notificationsEnabledKey)
        UserDefaults.standard.set(extraNotificationCount, forKey: NotificationManager.extraNotificationsKey)
        UserDefaults.standard.set(locationRemindersEnabled, forKey: NotificationManager.locationRemindersEnabledKey)

        if notificationsEnabled {
            let calendar = Calendar.current
            let morningHour = calendar.component(.hour, from: morningTime)
            let morningMinute = calendar.component(.minute, from: morningTime)
            let nightHour = calendar.component(.hour, from: nightTime)
            let nightMinute = calendar.component(.minute, from: nightTime)

            NotificationManager.shared.scheduleDailyReminders(
                morningHour: morningHour,
                morningMinute: morningMinute,
                nightHour: nightHour,
                nightMinute: nightMinute,
                extraReminders: extraNotificationCount,
                context: modelContext
            )

            withAnimation { showNotificationSaveConfirmation = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showNotificationSaveConfirmation = false }
            }
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: NotificationManager.scheduledReminderIDs)
            NotificationManager.shared.cancelAllJournalPromptNotifications()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isNotificationSaveButtonDisabled = false
        }
    }

    private func loadNotificationSettings() {
        notificationsEnabled = UserDefaults.standard.object(forKey: NotificationManager.notificationsEnabledKey) as? Bool ?? true
        morningTime = UserDefaults.standard.object(forKey: NotificationManager.morningReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
        nightTime = UserDefaults.standard.object(forKey: NotificationManager.nightReminderKey) as? Date ?? Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
        extraNotificationCount = UserDefaults.standard.object(forKey: NotificationManager.extraNotificationsKey) as? Int ?? 0
        locationRemindersEnabled = UserDefaults.standard.object(forKey: NotificationManager.locationRemindersEnabledKey) as? Bool ?? true
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

// MARK: - Profile Image Compression

private func compressProfileImage(_ data: Data, maxDimension: CGFloat = 400, quality: CGFloat = 0.8) -> Data {
    guard let uiImage = UIImage(data: data) else { return data }
    let size = uiImage.size
    let scale = min(maxDimension / max(size.width, size.height), 1.0)
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: newSize)
    let resized = renderer.image { _ in uiImage.draw(in: CGRect(origin: .zero, size: newSize)) }
    return resized.jpegData(compressionQuality: quality) ?? data
}
