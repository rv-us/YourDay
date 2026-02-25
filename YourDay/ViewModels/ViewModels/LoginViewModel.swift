import SwiftUI
import FirebaseCore
import Firebase
import FirebaseAuth
import GoogleSignIn
import SwiftData
import Network // For NWPathMonitor
import AuthenticationServices // Required for Apple Sign In
import CryptoKit // Required for SHA256 hashing

@MainActor
class LoginViewModel: ObservableObject {
    // MARK: - Published Properties for UI State
    @Published var isAuthenticated: Bool = false
    @Published var isGuest: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    @Published var isNetworkAvailable: Bool = true

    // MARK: - Published Properties for User Info
    @Published var userDisplayName: String? = nil
    @Published var userEmail: String? = nil
    @Published var guestDisplayName: String = ""

    // MARK: - Properties for Email/Password Auth
    @Published var email = ""
    @Published var password = ""
    @Published var displayNameForRegistration = ""

    // MARK: - Published Properties for Data Sync
    @Published var loadedPlayerStatsCodable: PlayerStatsCodable? = nil
    @Published private(set) var isProcessingFreshLogin: Bool = false

    /// When non-nil, the user is viewing the chat with this friend; used to suppress chat message notifications for that chat.
    @Published var currentChatFriendId: String? = nil

    // MARK: - Account Linking Properties
    /// When non-nil, the user needs to sign in with email/password to link this credential to their existing account.
    @Published var pendingLinkCredential: AuthCredential? = nil
    @Published var pendingLinkProviderName: String? = nil // "Apple" or "Google"

    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let firebaseManager = FirebaseManager()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var currentNonce: String? // For Apple Sign In

    // MARK: - Initialization and Deinitialization
    init() {
        print("LoginViewModel: Initializing.")
        
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let newNetworkStatus = path.status == .satisfied
                if self?.isNetworkAvailable != newNetworkStatus {
                    self?.isNetworkAvailable = newNetworkStatus
                    print("LoginViewModel: Network status changed to \(self?.isNetworkAvailable ?? false ? "Available" : "Unavailable").")
                }
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)

        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                let newAuthStatus = (user != nil)
                
                if self.isAuthenticated != newAuthStatus {
                    self.isAuthenticated = newAuthStatus
                    print("LoginViewModel: Auth status changed via listener to \(self.isAuthenticated).")
                }
                
                if newAuthStatus && !self.isGuest {
                    self.userDisplayName = user?.displayName
                    self.userEmail = user?.email
                }
                
                if !newAuthStatus {
                    print("LoginViewModel: User logged out (detected by listener). Clearing ViewModel data.")
                    self.clearViewModelDataOnLogout()
                    if self.isLoading { self.isLoading = false }
                }
            }
        }
        checkAuthenticationState()
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
        firebaseManager.removeAllListeners()
        networkMonitor.cancel()
        print("LoginViewModel: Deinitialized.")
    }

    // MARK: - Authentication State Management
    func checkAuthenticationState() {
        DispatchQueue.main.async {
            if let user = Auth.auth().currentUser {
                if !self.isAuthenticated { self.isAuthenticated = true }
                self.userDisplayName = user.displayName
                self.userEmail = user.email
                print("LoginViewModel: checkAuthenticationState - User \(user.uid) is authenticated.")
            } else {
                if self.isAuthenticated { self.isAuthenticated = false }
                print("LoginViewModel: checkAuthenticationState - No authenticated user.")
            }
        }
    }
    
    // MARK: - Guest Session Management
    func startGuestSession() {
        let trimmedName = guestDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a display name to continue as a guest."
            return
        }
        if DisplayNameValidator.containsProfanity(trimmedName) {
            errorMessage = "Display name contains inappropriate language."
            return
        }

        print("LoginViewModel: Starting guest session with display name: \(trimmedName).")
        self.userDisplayName = trimmedName
        self.isGuest = true
        self.isAuthenticated = false
        self.errorMessage = nil
    }

    // MARK: - Email/Password Authentication
    
    func createAccountWithEmailPassword() {
        isLoading = true
        errorMessage = nil
        
        guard !displayNameForRegistration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter a display name."
            isLoading = false
            return
        }
        let trimmedDisplayName = displayNameForRegistration.trimmingCharacters(in: .whitespacesAndNewlines)
        if DisplayNameValidator.containsProfanity(trimmedDisplayName) {
            errorMessage = "Display name contains inappropriate language."
            isLoading = false
            return
        }
        
        firebaseManager.checkDisplayNameExists(displayName: displayNameForRegistration) { [weak self] exists, error in
            guard let self = self else { return }
            
            if let error = error {
                self.errorMessage = "Error checking display name: \(error.localizedDescription)"
                self.isLoading = false
                return
            }
            
            if exists {
                self.errorMessage = "This display name is already taken. Please choose another."
                self.isLoading = false
                return
            }
            
            Auth.auth().createUser(withEmail: self.email, password: self.password) { [weak self] authResult, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.errorMessage = "Failed to create account: \(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                
                guard let user = authResult?.user else {
                    self.errorMessage = "Failed to get user after creation."
                    self.isLoading = false
                    return
                }
                
                let changeRequest = user.createProfileChangeRequest()
                changeRequest.displayName = self.displayNameForRegistration
                changeRequest.commitChanges { [weak self] error in
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        self.errorMessage = "Account created, but failed to set display name: \(error.localizedDescription)"
                    } else {
                        print("Account created and display name set successfully.")
                        self.userDisplayName = self.displayNameForRegistration
                        self.isProcessingFreshLogin = true
                    }
                }
            }
        }
    }

    func signInWithEmailPassword() {
        isLoading = true
        errorMessage = nil
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                self.isLoading = false
                self.errorMessage = "Sign-in failed: \(error.localizedDescription)"
                return
            }
            
            // If there's a pending link credential, link it to the account now
            if let credential = self.pendingLinkCredential, let providerName = self.pendingLinkProviderName {
                self.linkCredentialToCurrentUser(credential: credential, providerName: providerName)
            } else {
                self.isLoading = false
                print("Sign-in successful.")
                self.isProcessingFreshLogin = true
            }
        }
    }
    
    private func linkCredentialToCurrentUser(credential: AuthCredential, providerName: String) {
        guard let user = Auth.auth().currentUser else {
            self.isLoading = false
            self.errorMessage = "Failed to link account: User not signed in."
            self.pendingLinkCredential = nil
            self.pendingLinkProviderName = nil
            return
        }
        
        user.link(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            self.isLoading = false
            
            if let error = error {
                let nsError = error as NSError
                // If credential is already linked (shouldn't happen but handle gracefully)
                if nsError.code == 17012 { // AuthErrorCode.credentialAlreadyInUse
                    self.errorMessage = "This \(providerName) account is already linked to your account."
                } else {
                    self.errorMessage = "Failed to link \(providerName) account: \(error.localizedDescription)"
                }
                self.pendingLinkCredential = nil
                self.pendingLinkProviderName = nil
                return
            }
            
            // Successfully linked
            print("LoginViewModel: Successfully linked \(providerName) credential to existing account.")
            self.pendingLinkCredential = nil
            self.pendingLinkProviderName = nil
            self.errorMessage = nil
            self.isProcessingFreshLogin = true
        }
    }
    
    // MARK: - Apple Sign In
    
    func handleAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        self.isLoading = true
        self.errorMessage = nil
        self.isProcessingFreshLogin = true
        
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential else {
                self.errorMessage = "Apple Authorization failed: Invalid credential"
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }

            guard let nonce = currentNonce else {
                self.errorMessage = "Apple Authorization failed: Invalid state."
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }

            guard let appleIDToken = appleIDCredential.identityToken else {
                self.errorMessage = "Apple Authorization failed: Unable to fetch identity token."
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                self.errorMessage = "Apple Authorization failed: Unable to serialize token."
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }

            let credential = OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce)
            
            // For new users, extract the name and save it.
            // This is only provided on the first authorization.
            if let fullName = appleIDCredential.fullName {
                let nameFormatter = PersonNameComponentsFormatter()
                self.userDisplayName = nameFormatter.string(from: fullName)
            }
            
            signInToFirebase(with: credential, providerName: "Apple")

        case .failure(let error):
            // Handle error, user cancellation, etc.
            self.errorMessage = "Apple Sign-In error: \(error.localizedDescription)"
            self.isLoading = false
            self.isProcessingFreshLogin = false
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        return hashString
    }


    // MARK: - User Profile Management
    func updateUserDisplayName(newName: String, currentPlayerStats: PlayerStats?, completion: @escaping (Bool, String?) -> Void) {
        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNewName.isEmpty {
            completion(false, "Display name cannot be empty.")
            return
        }
        if DisplayNameValidator.containsProfanity(trimmedNewName) {
            completion(false, "Display name contains inappropriate language.")
            return
        }
        if isGuest {
            self.userDisplayName = trimmedNewName
            completion(true, "Guest name updated locally.")
            return
        }
        
        guard let user = Auth.auth().currentUser else {
            completion(false, "User not authenticated.")
            return
        }

        guard isNetworkAvailable else {
            completion(false, "No internet connection. Cannot update name.")
            return
        }
        
        if trimmedNewName == user.displayName {
            completion(true, "Display name is already set to this value.")
            return
        }

        self.isLoading = true
        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmedNewName
        changeRequest.commitChanges { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion(false, "Internal error.")
                    return
                }
                if let error = error {
                    self.isLoading = false
                    print("LoginViewModel: Error updating Firebase Auth display name - \(error.localizedDescription)")
                    completion(false, "Failed to update display name in Auth: \(error.localizedDescription)")
                } else {
                    print("LoginViewModel: Firebase Auth display name updated successfully to '\(trimmedNewName)'.")
                    self.userDisplayName = trimmedNewName

                    if let stats = currentPlayerStats {
                        let leaderboardEntry = LeaderboardEntry(
                            id: user.uid,
                            displayName: trimmedNewName,
                            playerLevel: stats.playerLevel,
                            gardenValue: stats.gardenValue
                        )
                        self.firebaseManager.updateLeaderboardEntry(entry: leaderboardEntry) { leaderboardError in
                            self.isLoading = false
                            if let leaderboardError = leaderboardError {
                                print("LoginViewModel: Display name updated in Auth, but failed to update leaderboard: \(leaderboardError.localizedDescription)")
                                completion(true, "Name updated, but leaderboard sync failed: \(leaderboardError.localizedDescription)")
                            } else {
                                print("LoginViewModel: Display name and leaderboard entry updated successfully.")
                                completion(true, nil)
                            }
                        }
                    } else {
                        self.isLoading = false
                        print("LoginViewModel: Display name updated in Auth, but no PlayerStats provided to update leaderboard.")
                        completion(true, "Name updated, but leaderboard could not be synced without player stats.")
                    }
                }
            }
        }
    }

    // MARK: - Data Orchestration
    func handleUserSession(localPlayerStats: PlayerStats?, modelContext: ModelContext) {
        if isGuest {
            print("LoginViewModel: Handling session for a GUEST user.")
            if localPlayerStats == nil {
                print("LoginViewModel: No local data for guest, creating new PlayerStats.")
                let newLocalStats = PlayerStats()
                modelContext.insert(newLocalStats)
                do {
                    try modelContext.save()
                    print("LoginViewModel: Saved initial local data for guest.")
                } catch {
                    print("LoginViewModel: Failed to save initial local data for guest: \(error.localizedDescription)")
                }
            }
            return
        }

        guard isAuthenticated, let currentFirebaseUser = Auth.auth().currentUser else {
            print("LoginViewModel: handleUserSession - User not authenticated. Aborting.")
            self.isProcessingFreshLogin = false
            return
        }
        print("LoginViewModel: handleUserSession for user \(currentFirebaseUser.uid). isProcessingFreshLogin: \(isProcessingFreshLogin)")

        let today = Calendar.current.startOfDay(for: Date())

        if isProcessingFreshLogin {
            print("LoginViewModel: handleUserSession - Processing FRESH LOGIN. Loading from Firestore.")
            initiatePlayerStatsLoadAndUpdateLocal(modelContext: modelContext, loginDateToSet: today) {
                // After PlayerStats sync, sync tasks and notes
                self.syncTasksAndNotesOnLogin(modelContext: modelContext) {
                    self.isProcessingFreshLogin = false
                    print("LoginViewModel: Finished processing fresh login data load sequence, isProcessingFreshLogin flag reset.")
                }
            }
        } else {
            if let existingLocalStats = localPlayerStats {
                print("LoginViewModel: handleUserSession - App launch, LOCAL PlayerStats EXIST (ID: \(existingLocalStats.id)). Syncing local to Firestore if needed.")
                self.loadedPlayerStatsCodable = PlayerStatsCodable(from: existingLocalStats)
                syncLocalPlayerStatsToFirestore(playerStatsModel: existingLocalStats) { error in
                    if error == nil {
                        print("LoginViewModel: Successfully synced local stats to Firestore on app launch. Now updating leaderboard.")
                        self.updateLeaderboardFromLocalStats(playerStatsModel: existingLocalStats)
                    } else {
                        print("LoginViewModel: Failed to sync local stats to Firestore on app launch: \(error!.localizedDescription)")
                    }
                }
                // Also sync tasks and notes on app launch
                self.syncTasksAndNotesOnLogin(modelContext: modelContext, completion: nil)
            } else {
                print("LoginViewModel: handleUserSession - App launch, NO local PlayerStats. Loading from Firestore as fallback.")
                initiatePlayerStatsLoadAndUpdateLocal(modelContext: modelContext, loginDateToSet: today) {
                    // After PlayerStats sync, sync tasks and notes
                    self.syncTasksAndNotesOnLogin(modelContext: modelContext, completion: nil)
                }
            }
        }
    }
    
    private func initiatePlayerStatsLoadAndUpdateLocal(modelContext: ModelContext, loginDateToSet: Date, completion: (() -> Void)?) {
        guard let userId = Auth.auth().currentUser?.uid else {
            if self.isLoading { self.isLoading = false }
            completion?()
            return
        }
        
        print("LoginViewModel: Initiating PlayerStats load from Firestore for user \(userId).")
        self.isLoading = true
        self.errorMessage = nil

        firebaseManager.loadPlayerStats { [weak self] statsCodable, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to load player stats: \(error.localizedDescription)"
                    let statsToUse = PlayerStats()
                    statsToUse.lastLoginDate = loginDateToSet
                    self.updateOrCreateLocalPlayerStatsModel(from: PlayerStatsCodable(from: statsToUse), context: modelContext) { _ in completion?() }

                } else if var loadedStatsCodable = statsCodable {
                    loadedStatsCodable.lastLoginDate = loginDateToSet
                    self.loadedPlayerStatsCodable = loadedStatsCodable
                    print("LoginViewModel: PlayerStatsCodable loaded from Firestore: ID \(loadedStatsCodable.id). Updating lastLoginDate to \(loginDateToSet) and then local SwiftData.")
                    self.updateOrCreateLocalPlayerStatsModel(from: loadedStatsCodable, context: modelContext) { updatedLocalStats in
                        if let localStats = updatedLocalStats {
                            self.updateLeaderboardFromLocalStats(playerStatsModel: localStats)
                        }
                        completion?()
                    }
                } else {
                    print("LoginViewModel: No PlayerStats in Firebase. Creating default, setting lastLoginDate to \(loginDateToSet).")
                    var defaultCodableStats = PlayerStatsCodable()
                    defaultCodableStats.lastLoginDate = loginDateToSet
                    self.loadedPlayerStatsCodable = defaultCodableStats
                    self.updateOrCreateLocalPlayerStatsModel(from: defaultCodableStats, context: modelContext) { createdLocalStats in
                        if let localStats = createdLocalStats {
                            self.syncLocalPlayerStatsToFirestore(playerStatsModel: localStats)
                            self.updateLeaderboardFromLocalStats(playerStatsModel: localStats)
                        }
                        completion?()
                    }
                }
            }
        }
    }
    
    private func updateOrCreateLocalPlayerStatsModel(from codableStats: PlayerStatsCodable, context: ModelContext, completion: ((PlayerStats?) -> Void)? = nil) {
        let descriptor = FetchDescriptor<PlayerStats>()
        var localStatsToReturn: PlayerStats? = nil
        
        do {
            let fetchedStats = try context.fetch(descriptor)
            localStatsToReturn = fetchedStats.first
        } catch {
            print("LoginViewModel: Error fetching local PlayerStats: \(error.localizedDescription)")
        }

        if let existingLocalStats = localStatsToReturn {
            print("LoginViewModel: Updating existing local PlayerStats (ID: \(existingLocalStats.id)) with data (Codable ID: \(codableStats.id)).")
            existingLocalStats.totalPoints = codableStats.totalPoints
            existingLocalStats.lastEvaluated = codableStats.lastEvaluated
            existingLocalStats.lastLoginDate = codableStats.lastLoginDate
            existingLocalStats.lastDailyPointsEarned = codableStats.lastDailyPointsEarned
            existingLocalStats.lastDailyCompletedTasks = codableStats.lastDailyCompletedTasks
            existingLocalStats.lastDailyTotalTasks = codableStats.lastDailyTotalTasks
            existingLocalStats.taskCompletionStreak = codableStats.taskCompletionStreak
            existingLocalStats.playerLevel = codableStats.playerLevel
            existingLocalStats.currentXP = codableStats.currentXP
            existingLocalStats.unplacedPlantsInventory = codableStats.unplacedPlantsInventory
            existingLocalStats.placedPlants = codableStats.placedPlants
            existingLocalStats.numberOfOwnedPlots = codableStats.numberOfOwnedPlots
            existingLocalStats.fertilizerCount = codableStats.fertilizerCount
            existingLocalStats.gardenValue = codableStats.gardenValue
            existingLocalStats.updateGardenValue()
            localStatsToReturn = existingLocalStats
        } else {
            print("LoginViewModel: No local PlayerStats found. Creating new from data (Codable ID: \(codableStats.id)).")
            let newLocalStats = PlayerStats(
                totalPoints: codableStats.totalPoints,
                lastEvaluated: codableStats.lastEvaluated,
                lastLoginDate: codableStats.lastLoginDate,
                lastDailyPointsEarned: codableStats.lastDailyPointsEarned,
                lastDailyCompletedTasks: codableStats.lastDailyCompletedTasks,
                lastDailyTotalTasks: codableStats.lastDailyTotalTasks,
                taskCompletionStreak: codableStats.taskCompletionStreak,
                playerLevel: codableStats.playerLevel,
                currentXP: codableStats.currentXP,
                unplacedPlantsInventory: codableStats.unplacedPlantsInventory,
                placedPlants: codableStats.placedPlants,
                numberOfOwnedPlots: codableStats.numberOfOwnedPlots,
                fertilizerCount: codableStats.fertilizerCount
            )
            newLocalStats.gardenValue = codableStats.gardenValue
            newLocalStats.updateGardenValue()
            context.insert(newLocalStats)
            localStatsToReturn = newLocalStats
        }

        do {
            try context.save()
            print("LoginViewModel: Local PlayerStats (SwiftData) saved/updated successfully.")
            completion?(localStatsToReturn)
        } catch {
            print("LoginViewModel: Error saving ModelContext after PlayerStats update: \(error.localizedDescription)")
            self.errorMessage = "Failed to save local player data."
            completion?(nil)
        }
    }

    func syncLocalPlayerStatsToFirestore(playerStatsModel: PlayerStats?, completion: ((Error?) -> Void)? = nil) {
        guard !isGuest else {
            completion?(nil)
            return
        }
        guard let statsModel = playerStatsModel else {
            print("LoginViewModel: No PlayerStats model provided to sync.")
            completion?(NSError(domain: "AppError", code: -1, userInfo: [NSLocalizedDescriptionKey: "PlayerStats model is nil."]))
            return
        }
        guard let userId = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "AppAuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]))
            return
        }
        print("LoginViewModel: Syncing local PlayerStats (ID: \(statsModel.id), LastLogin: \(String(describing: statsModel.lastLoginDate))) to Firestore for user \(userId)...")
        
        let playerStatsCodable = PlayerStatsCodable(from: statsModel)
        self.loadedPlayerStatsCodable = playerStatsCodable

        firebaseManager.savePlayerStats(playerStatsCodable) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion?(NSError(domain: "AppError", code: -2, userInfo: [NSLocalizedDescriptionKey: "ViewModel deallocated."]))
                    return
                }
                if let error = error {
                    self.errorMessage = "Failed to sync player stats to Firestore: \(error.localizedDescription)"
                    print("LoginViewModel: Error syncing PlayerStats to Firestore - \(error.localizedDescription)")
                } else {
                    print("LoginViewModel: Local PlayerStats successfully synced to Firestore. Now updating leaderboard.")
                    self.updateLeaderboardFromLocalStats(playerStatsModel: statsModel)
                }
                completion?(error)
            }
        }
    }

    private func updateLeaderboardFromLocalStats(playerStatsModel: PlayerStats) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else { return }

        let nameForLeaderboard = self.userDisplayName ?? Auth.auth().currentUser?.displayName ?? "Anonymous Gardener"

        print("LoginViewModel: Updating leaderboard for user \(userId) with Name: \(nameForLeaderboard), Level: \(playerStatsModel.playerLevel), GardenValue: \(playerStatsModel.gardenValue)")

        let leaderboardEntry = LeaderboardEntry(
            id: userId,
            displayName: nameForLeaderboard,
            playerLevel: playerStatsModel.playerLevel,
            gardenValue: playerStatsModel.gardenValue
        )
        self.firebaseManager.updateLeaderboardEntry(entry: leaderboardEntry) { error in
            if let error = error {
                print("LoginViewModel: Failed to update leaderboard from local stats sync: \(error.localizedDescription)")
            } else {
                print("LoginViewModel: Leaderboard entry updated based on local stats sync.")
            }
        }
    }

    // MARK: - Tasks and Notes Sync

    /// Syncs tasks and notes between local SwiftData and Firebase on login
    private func syncTasksAndNotesOnLogin(modelContext: ModelContext, completion: (() -> Void)?) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else {
            completion?()
            return
        }

        let isFreshLogin = isProcessingFreshLogin
        print("LoginViewModel: Starting tasks and notes sync for user \(userId) (isFreshLogin: \(isFreshLogin))")

        let group = DispatchGroup()

        // Sync TodoItems
        group.enter()
        syncTodoItemsOnLogin(modelContext: modelContext, userId: userId, isFreshLogin: isFreshLogin) {
            group.leave()
        }

        // Sync NoteItems
        group.enter()
        syncNoteItemsOnLogin(modelContext: modelContext, userId: userId, isFreshLogin: isFreshLogin) {
            group.leave()
        }

        group.notify(queue: .main) {
            print("LoginViewModel: Finished syncing tasks and notes")
            completion?()
        }
    }

    /// Deduplicates local tasks by keeping the first occurrence of each localTaskId
    private func deduplicateTasks(_ tasks: [TodoItem]) -> [TodoItem] {
        var seen = Set<String>()
        var result: [TodoItem] = []
        for task in tasks {
            if !seen.contains(task.localTaskId) {
                seen.insert(task.localTaskId)
                result.append(task)
            } else {
                print("LoginViewModel: ⚠️ Duplicate local task found with ID: \(task.localTaskId) - skipping")
            }
        }
        return result
    }
    
    /// Deduplicates cloud tasks by keeping the most recently updated version of each localTaskId
    private func deduplicateCloudTasks(_ tasks: [TodoItemCodable]) -> [TodoItemCodable] {
        var taskMap: [String: TodoItemCodable] = [:]
        for task in tasks {
            if let existing = taskMap[task.localTaskId] {
                // Keep the one with the most recent updatedAt
                if task.updatedAt > existing.updatedAt {
                    print("LoginViewModel: ⚠️ Duplicate cloud task found with ID: \(task.localTaskId) - keeping newer version (updatedAt: \(task.updatedAt))")
                    taskMap[task.localTaskId] = task
                } else {
                    print("LoginViewModel: ⚠️ Duplicate cloud task found with ID: \(task.localTaskId) - keeping existing version (updatedAt: \(existing.updatedAt))")
                }
            } else {
                taskMap[task.localTaskId] = task
            }
        }
        return Array(taskMap.values)
    }

    /// Syncs TodoItems between local SwiftData and Firebase
    private func syncTodoItemsOnLogin(modelContext: ModelContext, userId: String, isFreshLogin: Bool, completion: @escaping () -> Void) {
        // Fetch local tasks
        let localDescriptor = FetchDescriptor<TodoItem>()
        var localTasks: [TodoItem] = []
        do {
            localTasks = try modelContext.fetch(localDescriptor)
        } catch {
            print("LoginViewModel: Error fetching local TodoItems: \(error.localizedDescription)")
        }

        if isFreshLogin {
            // Fresh login: Cloud is source of truth, merge cloud into local
            // Fetch cloud tasks
            firebaseManager.fetchTodoItems { [weak self] cloudItems, error in
                guard let self = self else {
                    completion()
                    return
                }

                if let error = error {
                    print("LoginViewModel: Error fetching cloud TodoItems: \(error.localizedDescription)")
                    // If cloud fetch fails, push local items to cloud
                    self.pushLocalTasksToCloud(localTasks: localTasks, userId: userId, completion: completion)
                    return
                }

                let cloudTasks = cloudItems ?? []
                print("LoginViewModel: [Fresh Login] Found \(localTasks.count) local tasks and \(cloudTasks.count) cloud tasks")

                // Deduplicate tasks before creating maps (keep the most recent version)
                let deduplicatedLocalTasks = deduplicateTasks(localTasks)
                let deduplicatedCloudTasks = deduplicateCloudTasks(cloudTasks)
                
                if deduplicatedLocalTasks.count != localTasks.count {
                    print("LoginViewModel: ⚠️ Found and removed \(localTasks.count - deduplicatedLocalTasks.count) duplicate local tasks")
                }
                if deduplicatedCloudTasks.count != cloudTasks.count {
                    print("LoginViewModel: ⚠️ Found and removed \(cloudTasks.count - deduplicatedCloudTasks.count) duplicate cloud tasks")
                }

                // Create lookup maps (now safe from duplicates)
                let localTasksMap = Dictionary(uniqueKeysWithValues: deduplicatedLocalTasks.map { ($0.localTaskId, $0) })
                let cloudTasksMap = Dictionary(uniqueKeysWithValues: deduplicatedCloudTasks.map { ($0.localTaskId, $0) })

                var tasksToCreateLocally: [TodoItemCodable] = []
                var tasksToUpdateLocally: [TodoItemCodable] = []
                var tasksToPushToCloud: [TodoItem] = []

                // Find tasks that exist only in cloud -> create locally
                for (cloudId, cloudTask) in cloudTasksMap {
                    if localTasksMap[cloudId] == nil {
                        tasksToCreateLocally.append(cloudTask)
                    } else if let localTask = localTasksMap[cloudId] {
                        // Task exists in both - use cloud data (cloud wins based on updatedAt)
                        tasksToUpdateLocally.append(cloudTask)
                    }
                }

                // Find tasks that exist only locally -> push to cloud
                for (localId, localTask) in localTasksMap {
                    if cloudTasksMap[localId] == nil {
                        tasksToPushToCloud.append(localTask)
                    }
                }

                // Apply changes
                DispatchQueue.main.async {
                    // Create local tasks from cloud
                    for cloudTask in tasksToCreateLocally {
                        // Double-check that task doesn't already exist (safety check after deduplication)
                        if localTasksMap[cloudTask.localTaskId] == nil {
                            let props = cloudTask.toTodoItemProperties()
                            let newTask = TodoItem(
                                localTaskId: props.localTaskId,
                                title: props.title,
                                detail: props.detail,
                                dueDate: props.dueDate,
                                isDone: props.isDone,
                                subtasks: props.subtasks,
                                position: props.position,
                                origin: props.origin,
                                sharedTaskId: props.sharedTaskId,
                                isSharedPending: props.isSharedPending,
                                proofPostId: props.proofPostId
                            )
                            newTask.completedAt = props.completedAt
                            modelContext.insert(newTask)
                        } else {
                            print("LoginViewModel: ⚠️ Task with ID \(cloudTask.localTaskId) already exists locally, skipping creation")
                        }
                    }

                    // Update local tasks from cloud
                    for cloudTask in tasksToUpdateLocally {
                        if let localTask = localTasksMap[cloudTask.localTaskId] {
                            let props = cloudTask.toTodoItemProperties()
                            localTask.title = props.title
                            localTask.detail = props.detail
                            localTask.dueDate = props.dueDate
                            localTask.isDone = props.isDone
                            localTask.subtasks = props.subtasks
                            localTask.completedAt = props.completedAt
                            localTask.origin = props.origin
                            localTask.position = props.position
                            localTask.sharedTaskId = props.sharedTaskId
                            localTask.isSharedPending = props.isSharedPending
                            localTask.proofPostId = props.proofPostId
                        }
                    }

                    do {
                        try modelContext.save()
                        print("LoginViewModel: [Fresh Login] Saved \(tasksToCreateLocally.count) new tasks and updated \(tasksToUpdateLocally.count) tasks locally")
                    } catch {
                        print("LoginViewModel: Error saving TodoItems to local: \(error.localizedDescription)")
                    }

                    // Push local-only tasks to cloud
                    if !tasksToPushToCloud.isEmpty {
                        let codableTasks = tasksToPushToCloud.map { TodoItemCodable(from: $0, userId: userId) }
                        self.firebaseManager.saveTodoItems(codableTasks) { error in
                            if let error = error {
                                print("LoginViewModel: Error pushing local tasks to cloud: \(error.localizedDescription)")
                            } else {
                                print("LoginViewModel: Pushed \(tasksToPushToCloud.count) local tasks to cloud")
                            }
                            completion()
                        }
                    } else {
                        completion()
                    }
                }
            }
        } else {
            // Normal app launch: Local is source of truth, replace cloud with local
            print("LoginViewModel: [Normal Launch] Found \(localTasks.count) local tasks - pushing to cloud and cleaning up")
            
            // Deduplicate local tasks
            let deduplicatedLocalTasks = deduplicateTasks(localTasks)
            if deduplicatedLocalTasks.count != localTasks.count {
                print("LoginViewModel: ⚠️ Found and removed \(localTasks.count - deduplicatedLocalTasks.count) duplicate local tasks")
            }
            
            // Push all local tasks to cloud
            let localTaskIds = Set(deduplicatedLocalTasks.map { $0.localTaskId })
            let codableTasks = deduplicatedLocalTasks.map { TodoItemCodable(from: $0, userId: userId) }
            
            firebaseManager.saveTodoItems(codableTasks) { [weak self] error in
                guard let self = self else {
                    completion()
                    return
                }
                
                if let error = error {
                    print("LoginViewModel: Error pushing local tasks to cloud: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                print("LoginViewModel: [Normal Launch] Pushed \(codableTasks.count) local tasks to cloud")
                
                // Delete cloud tasks that don't exist locally
                self.firebaseManager.deleteCloudTasksNotInLocal(localTaskIds: localTaskIds) { error in
                    if let error = error {
                        print("LoginViewModel: Error cleaning up cloud tasks: \(error.localizedDescription)")
                    } else {
                        print("LoginViewModel: [Normal Launch] Cleaned up cloud tasks (local is now source of truth)")
                    }
                    completion()
                }
            }
        }
    }

    /// Pushes all local tasks to cloud (used when cloud fetch fails)
    private func pushLocalTasksToCloud(localTasks: [TodoItem], userId: String, completion: @escaping () -> Void) {
        guard !localTasks.isEmpty else {
            completion()
            return
        }

        let codableTasks = localTasks.map { TodoItemCodable(from: $0, userId: userId) }
        firebaseManager.saveTodoItems(codableTasks) { error in
            if let error = error {
                print("LoginViewModel: Error pushing all local tasks to cloud: \(error.localizedDescription)")
            } else {
                print("LoginViewModel: Pushed \(localTasks.count) local tasks to cloud")
            }
            completion()
        }
    }

    /// Deduplicates local notes by keeping the first occurrence of each UUID
    private func deduplicateNotes(_ notes: [NoteItem]) -> [NoteItem] {
        var seen = Set<UUID>()
        var result: [NoteItem] = []
        for note in notes {
            if !seen.contains(note.id) {
                seen.insert(note.id)
                result.append(note)
            } else {
                print("LoginViewModel: ⚠️ Duplicate local note found with ID: \(note.id) - skipping")
            }
        }
        return result
    }
    
    /// Deduplicates cloud notes by keeping the most recently updated version of each localNoteId
    private func deduplicateCloudNotes(_ notes: [NoteItemCodable]) -> [NoteItemCodable] {
        var noteMap: [String: NoteItemCodable] = [:]
        for note in notes {
            if let existing = noteMap[note.localNoteId] {
                // Keep the one with the most recent updatedAt
                if note.updatedAt > existing.updatedAt {
                    print("LoginViewModel: ⚠️ Duplicate cloud note found with ID: \(note.localNoteId) - keeping newer version (updatedAt: \(note.updatedAt))")
                    noteMap[note.localNoteId] = note
                } else {
                    print("LoginViewModel: ⚠️ Duplicate cloud note found with ID: \(note.localNoteId) - keeping existing version (updatedAt: \(existing.updatedAt))")
                }
            } else {
                noteMap[note.localNoteId] = note
            }
        }
        return Array(noteMap.values)
    }

    /// Syncs NoteItems between local SwiftData and Firebase
    private func syncNoteItemsOnLogin(modelContext: ModelContext, userId: String, isFreshLogin: Bool, completion: @escaping () -> Void) {
        // Fetch local notes
        let localDescriptor = FetchDescriptor<NoteItem>()
        var localNotes: [NoteItem] = []
        do {
            localNotes = try modelContext.fetch(localDescriptor)
        } catch {
            print("LoginViewModel: Error fetching local NoteItems: \(error.localizedDescription)")
        }

        if isFreshLogin {
            // Fresh login: Cloud is source of truth, merge cloud into local
            // Fetch cloud notes
            firebaseManager.fetchNoteItems { [weak self] cloudItems, error in
                guard let self = self else {
                    completion()
                    return
                }

                if let error = error {
                    print("LoginViewModel: Error fetching cloud NoteItems: \(error.localizedDescription)")
                    // If cloud fetch fails, push local items to cloud
                    self.pushLocalNotesToCloud(localNotes: localNotes, userId: userId, completion: completion)
                    return
                }

                let cloudNotes = cloudItems ?? []
                print("LoginViewModel: [Fresh Login] Found \(localNotes.count) local notes and \(cloudNotes.count) cloud notes")

                // Deduplicate notes before creating maps
                let deduplicatedLocalNotes = deduplicateNotes(localNotes)
                let deduplicatedCloudNotes = deduplicateCloudNotes(cloudNotes)
                
                if deduplicatedLocalNotes.count != localNotes.count {
                    print("LoginViewModel: ⚠️ Found and removed \(localNotes.count - deduplicatedLocalNotes.count) duplicate local notes")
                }
                if deduplicatedCloudNotes.count != cloudNotes.count {
                    print("LoginViewModel: ⚠️ Found and removed \(cloudNotes.count - deduplicatedCloudNotes.count) duplicate cloud notes")
                }

                // Create lookup maps using localNoteId (UUID string) for both to ensure proper matching
                let localNotesMap = Dictionary(uniqueKeysWithValues: deduplicatedLocalNotes.map { ($0.id.uuidString, $0) })
                let cloudNotesMap = Dictionary(uniqueKeysWithValues: deduplicatedCloudNotes.map { ($0.localNoteId, $0) })

                var notesToCreateLocally: [NoteItemCodable] = []
                var notesToUpdateLocally: [NoteItemCodable] = []
                var notesToPushToCloud: [NoteItem] = []

                // Find notes that exist only in cloud -> create locally
                for (cloudId, cloudNote) in cloudNotesMap {
                    if localNotesMap[cloudId] == nil {
                        notesToCreateLocally.append(cloudNote)
                    } else {
                        // Note exists in both - use cloud data (cloud wins)
                        notesToUpdateLocally.append(cloudNote)
                    }
                }

                // Find notes that exist only locally -> push to cloud
                for (localId, localNote) in localNotesMap {
                    if cloudNotesMap[localId] == nil {
                        notesToPushToCloud.append(localNote)
                    }
                }

                // Apply changes
                DispatchQueue.main.async {
                    // Create local notes from cloud (preserving the UUID from cloud)
                    for cloudNote in notesToCreateLocally {
                        let props = cloudNote.toNoteItemProperties()
                        // Check if note with this ID already exists (shouldn't happen after deduplication, but safety check)
                        if localNotesMap[cloudNote.localNoteId] == nil {
                            let newNote = NoteItem(id: props.id, content: props.content, createdAt: props.createdAt, fontSize: props.fontSize)
                            modelContext.insert(newNote)
                        } else {
                            print("LoginViewModel: ⚠️ Note with ID \(cloudNote.localNoteId) already exists locally, skipping creation")
                        }
                    }

                    // Update local notes from cloud
                    for cloudNote in notesToUpdateLocally {
                        if let localNote = localNotesMap[cloudNote.localNoteId] {
                            let props = cloudNote.toNoteItemProperties()
                            localNote.content = props.content
                            localNote.fontSize = props.fontSize
                        }
                    }

                    do {
                        try modelContext.save()
                        print("LoginViewModel: [Fresh Login] Saved \(notesToCreateLocally.count) new notes and updated \(notesToUpdateLocally.count) notes locally")
                    } catch {
                        print("LoginViewModel: Error saving NoteItems to local: \(error.localizedDescription)")
                    }

                    // Push local-only notes to cloud
                    if !notesToPushToCloud.isEmpty {
                        let codableNotes = notesToPushToCloud.map { NoteItemCodable(from: $0, userId: userId) }
                        self.firebaseManager.saveNoteItems(codableNotes) { error in
                            if let error = error {
                                print("LoginViewModel: Error pushing local notes to cloud: \(error.localizedDescription)")
                            } else {
                                print("LoginViewModel: Pushed \(notesToPushToCloud.count) local notes to cloud")
                            }
                            completion()
                        }
                    } else {
                        completion()
                    }
                }
            }
        } else {
            // Normal app launch: Local is source of truth, replace cloud with local
            print("LoginViewModel: [Normal Launch] Found \(localNotes.count) local notes - pushing to cloud and cleaning up")
            
            // Deduplicate local notes
            let deduplicatedLocalNotes = deduplicateNotes(localNotes)
            if deduplicatedLocalNotes.count != localNotes.count {
                print("LoginViewModel: ⚠️ Found and removed \(localNotes.count - deduplicatedLocalNotes.count) duplicate local notes")
            }
            
            // Push all local notes to cloud
            let localNoteIds = Set(deduplicatedLocalNotes.map { $0.id.uuidString })
            let codableNotes = deduplicatedLocalNotes.map { NoteItemCodable(from: $0, userId: userId) }
            
            firebaseManager.saveNoteItems(codableNotes) { [weak self] error in
                guard let self = self else {
                    completion()
                    return
                }
                
                if let error = error {
                    print("LoginViewModel: Error pushing local notes to cloud: \(error.localizedDescription)")
                    completion()
                    return
                }
                
                print("LoginViewModel: [Normal Launch] Pushed \(codableNotes.count) local notes to cloud")
                
                // Delete cloud notes that don't exist locally
                self.firebaseManager.deleteCloudNotesNotInLocal(localNoteIds: localNoteIds) { error in
                    if let error = error {
                        print("LoginViewModel: Error cleaning up cloud notes: \(error.localizedDescription)")
                    } else {
                        print("LoginViewModel: [Normal Launch] Cleaned up cloud notes (local is now source of truth)")
                    }
                    completion()
                }
            }
        }
    }

    /// Pushes all local notes to cloud (used when cloud fetch fails)
    private func pushLocalNotesToCloud(localNotes: [NoteItem], userId: String, completion: @escaping () -> Void) {
        guard !localNotes.isEmpty else {
            completion()
            return
        }

        let codableNotes = localNotes.map { NoteItemCodable(from: $0, userId: userId) }
        firebaseManager.saveNoteItems(codableNotes) { error in
            if let error = error {
                print("LoginViewModel: Error pushing all local notes to cloud: \(error.localizedDescription)")
            } else {
                print("LoginViewModel: Pushed \(localNotes.count) local notes to cloud")
            }
            completion()
        }
    }

    // MARK: - Public Sync Methods for Views

    /// Syncs a single TodoItem to Firebase (call after creating/updating a task)
    func syncTodoItemToFirebase(_ task: TodoItem) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else { return }

        let codableTask = TodoItemCodable(from: task, userId: userId)
        firebaseManager.saveTodoItem(codableTask) { error in
            if let error = error {
                print("LoginViewModel: Failed to sync task '\(task.title)' to Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Syncs multiple TodoItems to Firebase (call after batch updates)
    func syncTodoItemsToFirebase(_ tasks: [TodoItem]) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else { return }

        let codableTasks = tasks.map { TodoItemCodable(from: $0, userId: userId) }
        firebaseManager.saveTodoItems(codableTasks) { error in
            if let error = error {
                print("LoginViewModel: Failed to sync \(tasks.count) tasks to Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes a TodoItem from Firebase (call after deleting locally)
    func deleteTodoItemFromFirebase(localTaskId: String) {
        guard !isGuest else { return }

        firebaseManager.deleteTodoItem(localTaskId: localTaskId) { error in
            if let error = error {
                print("LoginViewModel: Failed to delete task from Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes multiple TodoItems from Firebase (call after batch deletes)
    func deleteTodoItemsFromFirebase(localTaskIds: [String]) {
        guard !isGuest else { return }

        firebaseManager.deleteTodoItems(localTaskIds: localTaskIds) { error in
            if let error = error {
                print("LoginViewModel: Failed to delete \(localTaskIds.count) tasks from Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Syncs a single NoteItem to Firebase (call after creating/updating a note)
    func syncNoteItemToFirebase(_ note: NoteItem) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else { return }

        let codableNote = NoteItemCodable(from: note, userId: userId)
        firebaseManager.saveNoteItem(codableNote) { error in
            if let error = error {
                print("LoginViewModel: Failed to sync note to Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Syncs multiple NoteItems to Firebase (call after batch updates)
    func syncNoteItemsToFirebase(_ notes: [NoteItem]) {
        guard !isGuest, let userId = Auth.auth().currentUser?.uid else { return }

        let codableNotes = notes.map { NoteItemCodable(from: $0, userId: userId) }
        firebaseManager.saveNoteItems(codableNotes) { error in
            if let error = error {
                print("LoginViewModel: Failed to sync \(notes.count) notes to Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes a NoteItem from Firebase (call after deleting locally)
    func deleteNoteItemFromFirebase(localNoteId: String) {
        guard !isGuest else { return }

        firebaseManager.deleteNoteItem(localNoteId: localNoteId) { error in
            if let error = error {
                print("LoginViewModel: Failed to delete note from Firebase: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes multiple NoteItems from Firebase (call after batch deletes)
    func deleteNoteItemsFromFirebase(localNoteIds: [String]) {
        guard !isGuest else { return }

        firebaseManager.deleteNoteItems(localNoteIds: localNoteIds) { error in
            if let error = error {
                print("LoginViewModel: Failed to delete \(localNoteIds.count) notes from Firebase: \(error.localizedDescription)")
            }
        }
    }

    private func clearViewModelDataOnLogout() {
        DispatchQueue.main.async {
            self.loadedPlayerStatsCodable = nil
            self.isProcessingFreshLogin = false
            self.isGuest = false
            self.guestDisplayName = ""
            self.userDisplayName = nil
            self.userEmail = nil
            self.email = ""
            self.password = ""
            self.displayNameForRegistration = ""
            print("LoginViewModel: ViewModel's user data and flags cleared.")
        }
    }
    
    internal func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        var currentViewController = rootViewController
        while let presentedController = currentViewController.presentedViewController {
            currentViewController = presentedController
        }
        return currentViewController
    }

    func signInWithGoogle() {
        print("LoginViewModel: signInWithGoogle initiated.")
        self.isLoading = true
        self.errorMessage = nil
        self.isProcessingFreshLogin = true

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            self.errorMessage = "Firebase client ID not found."; self.isLoading = false; self.isProcessingFreshLogin = false; return
        }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let presentingViewController = getRootViewController() else {
            self.errorMessage = "Could not find presenting view controller."; self.isLoading = false; self.isProcessingFreshLogin = false; return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] signInResult, error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Google Sign-In error: \(error.localizedDescription)"; self.isLoading = false; self.isProcessingFreshLogin = false; return
            }
            guard let result = signInResult, let idToken = result.user.idToken?.tokenString else {
                self.errorMessage = "Google ID token not found."; self.isLoading = false; self.isProcessingFreshLogin = false; return
            }
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            print("LoginViewModel: Google Sign-In successful, proceeding to Firebase sign-in.")
            self.signInToFirebase(with: credential, providerName: "Google")
        }
    }

    private func signInToFirebase(with credential: AuthCredential, providerName: String = "provider") {
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            
            if let error = error {
                let nsError = error as NSError
                let errorCode = nsError.code
                
                // Check if this credential/email is already associated with another account
                // 17012 = AuthErrorCode.credentialAlreadyInUse
                // 17025 = AuthErrorCode.emailAlreadyInUse (though this is usually for createUser)
                // 17007 = AuthErrorCode.userNotFound (email doesn't exist yet - not our case)
                // 17020 = AuthErrorCode.accountExistsWithDifferentCredential
                
                if errorCode == 17012 || errorCode == 17020 {
                    // Credential is already linked to another account
                    // Store the credential and prompt user to sign in with email/password to link
                    self.pendingLinkCredential = credential
                    self.pendingLinkProviderName = providerName
                    self.errorMessage = "This email is already registered. Sign in with your email and password to add \(providerName) sign-in to your account."
                    self.isLoading = false
                    self.isProcessingFreshLogin = false
                    return
                }
                
                // Other errors - show generic message
                self.errorMessage = "Firebase Sign-In error: \(error.localizedDescription)"
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }
            
            guard let user = authResult?.user else {
                self.errorMessage = "Failed to get user after sign in."
                self.isLoading = false
                self.isProcessingFreshLogin = false
                return
            }

            // If the user's display name in Firebase is empty,
            // try to set it from the information we got from Apple Sign In.
            if user.displayName == nil || user.displayName?.isEmpty == true {
                if let name = self.userDisplayName, !name.isEmpty {
                    let changeRequest = user.createProfileChangeRequest()
                    changeRequest.displayName = name
                    changeRequest.commitChanges { [weak self] error in
                        if let error = error {
                            // This is not a fatal error, so we just log it.
                            print("LoginViewModel: Signed in, but failed to update display name: \(error.localizedDescription)")
                        } else {
                            print("LoginViewModel: Display name updated successfully after sign-in.")
                        }
                        // Continue with the login process regardless
                        self?.isProcessingFreshLogin = true
                        self?.isLoading = false
                    }
                } else {
                    // Name was not available, proceed without it.
                    self.isProcessingFreshLogin = true
                    self.isLoading = false
                }
            } else {
                // User already has a display name, so we just proceed.
                self.isProcessingFreshLogin = true
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Sign Out & Account Deletion
    
    func requestSignOut(currentPlayerStatsToSync: PlayerStats?, completion: @escaping (Bool, String?) -> Void) {
        if isGuest {
            DispatchQueue.main.async {
                print("LoginViewModel: Ending guest session.")
                self.clearViewModelDataOnLogout()
                completion(true, nil)
            }
        } else {
            attemptAuthenticatedSignOut(currentPlayerStatsToSync: currentPlayerStatsToSync, completion: completion)
        }
    }

    private func attemptAuthenticatedSignOut(currentPlayerStatsToSync: PlayerStats?, completion: @escaping (_ didSignOut: Bool, _ errorMessage: String?) -> Void) {
        print("LoginViewModel: attemptSignOut initiated.")
        self.isLoading = true
        self.errorMessage = nil

        guard isNetworkAvailable else {
            let offlineMessage = "No internet connection. Please connect to sync data and sign out."
            self.errorMessage = offlineMessage; self.isLoading = false; completion(false, offlineMessage); return
        }

        if let statsToSync = currentPlayerStatsToSync {
            print("LoginViewModel: Network available. Syncing PlayerStats before sign out.")
            syncLocalPlayerStatsToFirestore(playerStatsModel: statsToSync) { [weak self] syncError in
                guard let self = self else { completion(false, "Internal error."); return }
                if let syncError = syncError {
                    print("LoginViewModel: Failed to sync data: \(syncError.localizedDescription). Proceeding with sign out anyway.")
                } else {
                    print("LoginViewModel: PlayerStats synced. Proceeding with sign out.")
                }
                self.performFirebaseAndGoogleSignOut(completion: completion)
            }
        } else {
            print("LoginViewModel: No local PlayerStats to sync. Proceeding with sign out.")
            performFirebaseAndGoogleSignOut(completion: completion)
        }
    }

    private func performFirebaseAndGoogleSignOut(completion: @escaping (_ didSignOut: Bool, _ errorMessage: String?) -> Void) {
        self.isProcessingFreshLogin = false
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            print("LoginViewModel: Firebase and Google Sign-Out performed.")
            self.isLoading = false
            completion(true, nil)
        } catch let signOutError as NSError {
            let msg = "Sign out error: \(signOutError.localizedDescription)"
            self.errorMessage = msg; self.isLoading = false; completion(false, msg)
        }
    }
    func attemptSignOut(currentPlayerStatsToSync: PlayerStats?, completion: @escaping (_ didSignOut: Bool, _ errorMessage: String?) -> Void) {
            print("LoginViewModel: attemptSignOut initiated.")
            self.isLoading = true
            self.errorMessage = nil

            guard isNetworkAvailable else {
                let offlineMessage = "No internet connection. Please connect to sync data and sign out."
                self.errorMessage = offlineMessage; self.isLoading = false; completion(false, offlineMessage); return
            }

            if let statsToSync = currentPlayerStatsToSync {
                print("LoginViewModel: Network available. Syncing PlayerStats before sign out.")
                syncLocalPlayerStatsToFirestore(playerStatsModel: statsToSync) { [weak self] syncError in
                    guard let self = self else { completion(false, "Internal error."); return }
                    // Proceed with sign out even if sync fails, but notify user.
                    if let syncError = syncError {
                        print("LoginViewModel: Failed to sync data: \(syncError.localizedDescription). Proceeding with sign out anyway.")
                        // Optionally inform user about sync failure but still allow sign out.
                        // self.errorMessage = "Data sync failed, but signing out."
                    } else {
                        print("LoginViewModel: PlayerStats synced. Proceeding with sign out.")
                    }
                    self.performFirebaseAndGoogleSignOut(completion: completion)
                }
            } else {
                print("LoginViewModel: No local PlayerStats to sync. Proceeding with sign out.")
                performFirebaseAndGoogleSignOut(completion: completion)
            }
        }
    func sendPasswordResetEmail() {
        errorMessage = nil
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email address to reset your password."
            return
        }
        isLoading = true
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to send password reset email: \(error.localizedDescription)"
                } else {
                    self.errorMessage = "A password reset email has been sent."
                }
            }
        }
    }

    func deleteAccount(completion: @escaping (Bool, String?) -> Void) {
        guard !isGuest, let user = Auth.auth().currentUser else {
            completion(false, "No authenticated user to delete.")
            return
        }

        guard isNetworkAvailable else {
            completion(false, "No internet connection. Cannot delete account.")
            return
        }

        self.isLoading = true
        
        firebaseManager.deleteAllUserData { [weak self] error in
            guard let self = self else {
                completion(false, "An internal error occurred.")
                return
            }
            
            if let error = error {
                self.isLoading = false
                let message = "Could not delete user data from the server. Please try again. Error: \(error.localizedDescription)"
                self.errorMessage = message
                completion(false, message)
                return
            }
            
            print("LoginViewModel: Firestore data deleted. Now deleting Auth user.")
            user.delete { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self else {
                        completion(false, "An internal error occurred.")
                        return
                    }
                    self.isLoading = false
                    if let error = error {
                        let message = "Failed to delete account. This can happen if you haven't signed in recently. Please sign out and sign back in to complete this action. Error: \(error.localizedDescription)"
                        self.errorMessage = message
                        completion(false, message)
                    } else {
                        print("LoginViewModel: Firebase Auth user deleted successfully.")
                        completion(true, nil)
                    }
                }
            }
        }
    }
}
