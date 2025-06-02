import SwiftUI
import FirebaseCore
import Firebase
import FirebaseAuth
import GoogleSignIn
import SwiftData
import Network // For NWPathMonitor

@MainActor
class LoginViewModel: ObservableObject {
    // MARK: - Published Properties for UI State
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    @Published var isNetworkAvailable: Bool = true

    // MARK: - Published Properties for User Info
    @Published var userDisplayName: String? = nil
    @Published var userEmail: String? = nil

    // MARK: - Published Properties for Data Sync
    @Published var loadedPlayerStatsCodable: PlayerStatsCodable? = nil
    @Published private(set) var isProcessingFreshLogin: Bool = false

    // MARK: - Private Properties
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    private let firebaseManager = FirebaseManager()
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "NetworkMonitor")

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
                
                self.userDisplayName = user?.displayName
                self.userEmail = user?.email
                
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

    // MARK: - User Profile Management
    func updateUserDisplayName(newName: String, currentPlayerStats: PlayerStats?, completion: @escaping (Bool, String?) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false, "User not authenticated.")
            return
        }

        guard isNetworkAvailable else {
            completion(false, "No internet connection. Cannot update name.")
            return
        }

        let trimmedNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNewName.isEmpty {
            completion(false, "Display name cannot be empty.")
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
                // This completion is called after local data is updated from Firestore.
                // Reset the flag after all fresh login processing is done.
                self.isProcessingFreshLogin = false
                print("LoginViewModel: Finished processing fresh login data load sequence, isProcessingFreshLogin flag reset.")
            }
        } else {
            // This is a subsequent app open, not a fresh login.
            // The withering logic in ContentView will handle lastLoginDate updates.
            // We just ensure that if local stats exist, they are synced.
            if let existingLocalStats = localPlayerStats {
                print("LoginViewModel: handleUserSession - App launch, LOCAL PlayerStats EXIST (ID: \(existingLocalStats.id)). Syncing local to Firestore if needed.")
                // We don't forcibly update lastLoginDate here; ContentView's withering logic does that.
                // We sync whatever current local state is.
                self.loadedPlayerStatsCodable = PlayerStatsCodable(from: existingLocalStats) // Keep local cache updated
                syncLocalPlayerStatsToFirestore(playerStatsModel: existingLocalStats) { error in
                    if error == nil {
                        print("LoginViewModel: Successfully synced local stats to Firestore on app launch. Now updating leaderboard.")
                        self.updateLeaderboardFromLocalStats(playerStatsModel: existingLocalStats)
                    } else {
                        print("LoginViewModel: Failed to sync local stats to Firestore on app launch: \(error!.localizedDescription)")
                    }
                }
            } else {
                // This case (no local stats on a non-fresh login) should be rare if ContentView ensures stats exist.
                // If it happens, load from Firestore as a fallback.
                print("LoginViewModel: handleUserSession - App launch, NO local PlayerStats. Loading from Firestore as fallback.")
                initiatePlayerStatsLoadAndUpdateLocal(modelContext: modelContext, loginDateToSet: today, completion: nil)
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
                    // If Firebase load fails, try to use local or create new, ensuring lastLoginDate is set.
                    let statsToUse = PlayerStats() // Creates a new one with today as lastLoginDate by default
                    statsToUse.lastLoginDate = loginDateToSet // Explicitly set
                    self.updateOrCreateLocalPlayerStatsModel(from: PlayerStatsCodable(from: statsToUse), context: modelContext) { _ in completion?() }

                } else if var loadedStatsCodable = statsCodable {
                    // Successfully loaded from Firebase, now update its lastLoginDate before saving locally
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
                    // No stats in Firebase, create default, set lastLoginDate, save locally and to Firebase
                    print("LoginViewModel: No PlayerStats in Firebase. Creating default, setting lastLoginDate to \(loginDateToSet).")
                    var defaultCodableStats = PlayerStatsCodable()
                    defaultCodableStats.lastLoginDate = loginDateToSet
                    self.loadedPlayerStatsCodable = defaultCodableStats
                    self.updateOrCreateLocalPlayerStatsModel(from: defaultCodableStats, context: modelContext) { createdLocalStats in
                        if let localStats = createdLocalStats {
                            self.syncLocalPlayerStatsToFirestore(playerStatsModel: localStats) // Save new default to Firebase
                            self.updateLeaderboardFromLocalStats(playerStatsModel: localStats)
                        }
                        completion?()
                    }
                }
            }
        }
    }
    
    private func updateOrCreateLocalPlayerStatsModel(from codableStats: PlayerStatsCodable, context: ModelContext, completion: ((PlayerStats?) -> Void)? = nil) {
        let descriptor = FetchDescriptor<PlayerStats>() // Fetch any existing PlayerStats
        var localStatsToReturn: PlayerStats? = nil
        
        do {
            let fetchedStats = try context.fetch(descriptor)
            localStatsToReturn = fetchedStats.first // Assuming only one PlayerStats per user locally
        } catch {
            print("LoginViewModel: Error fetching local PlayerStats: \(error.localizedDescription)")
        }

        if var existingLocalStats = localStatsToReturn {
            print("LoginViewModel: Updating existing local PlayerStats (ID: \(existingLocalStats.id)) with data (Codable ID: \(codableStats.id)).")
            existingLocalStats.totalPoints = codableStats.totalPoints
            existingLocalStats.lastEvaluated = codableStats.lastEvaluated
            existingLocalStats.lastLoginDate = codableStats.lastLoginDate // Ensure this is correctly passed
            existingLocalStats.playerLevel = codableStats.playerLevel
            existingLocalStats.currentXP = codableStats.currentXP
            existingLocalStats.unplacedPlantsInventory = codableStats.unplacedPlantsInventory
            existingLocalStats.placedPlants = codableStats.placedPlants
            existingLocalStats.numberOfOwnedPlots = codableStats.numberOfOwnedPlots
            existingLocalStats.fertilizerCount = codableStats.fertilizerCount
            // gardenValue is part of codableStats, so it's updated. Then call updateGardenValue for local consistency.
            existingLocalStats.gardenValue = codableStats.gardenValue
            existingLocalStats.updateGardenValue() // Recalculate based on potentially updated plants
            localStatsToReturn = existingLocalStats
        } else {
            print("LoginViewModel: No local PlayerStats found. Creating new from data (Codable ID: \(codableStats.id)).")
            let newLocalStats = PlayerStats( // Use the initializer that takes all properties
                totalPoints: codableStats.totalPoints,
                lastEvaluated: codableStats.lastEvaluated,
                lastLoginDate: codableStats.lastLoginDate, // Ensure this is correctly passed
                playerLevel: codableStats.playerLevel,
                currentXP: codableStats.currentXP,
                unplacedPlantsInventory: codableStats.unplacedPlantsInventory,
                placedPlants: codableStats.placedPlants,
                numberOfOwnedPlots: codableStats.numberOfOwnedPlots,
                fertilizerCount: codableStats.fertilizerCount
            )
            // If the codableStats has a specific ID (e.g., from Firebase user ID mapping), use it.
            // Otherwise, PlayerStats @Model will generate its own UUID.
            // For consistency, if codableStats.id is meaningful, ensure PlayerStats @Model uses it.
            // newLocalStats.id = codableStats.id // This might conflict if PlayerStats.id is auto-generated and immutable after init.
            // It's generally better to fetch by a unique user identifier if multiple PlayerStats could exist.
            // For now, assuming a single PlayerStats locally.
            newLocalStats.gardenValue = codableStats.gardenValue // Set garden value from codable
            newLocalStats.updateGardenValue() // Recalculate
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
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let nameForLeaderboard = self.userDisplayName ?? Auth.auth().currentUser?.displayName ?? "Anonymous Gardener" // More thematic default
        
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

    private func clearViewModelDataOnLogout() {
        DispatchQueue.main.async {
            self.loadedPlayerStatsCodable = nil
            // self.firebaseManager.removeAllListeners() // Listeners should be managed per-view or via specific data managers
            self.isProcessingFreshLogin = false
            print("LoginViewModel: ViewModel's Firestore-related data and flags cleared.")
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
            self.signInToFirebase(with: credential)
        }
    }

    private func signInToFirebase(with credential: AuthCredential) {
        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            if let error = error {
                self.errorMessage = "Firebase Sign-In error: \(error.localizedDescription)"; self.isLoading = false; self.isProcessingFreshLogin = false; return
            }
            // AuthStateHandler will set isAuthenticated.
            // ContentView's .onChange(of: isAuthenticated) will call handleUserSession.
            // isProcessingFreshLogin is true, so handleUserSession will load from Firestore.
            print("LoginViewModel: Firebase sign-in successful for: \(authResult?.user.uid ?? "N/A")")
            // isLoading will be set to false after Firestore load in initiatePlayerStatsLoadAndUpdateLocal
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

    private func performFirebaseAndGoogleSignOut(completion: @escaping (_ didSignOut: Bool, _ errorMessage: String?) -> Void) {
        self.isProcessingFreshLogin = false // Reset this flag
        // firebaseManager.removeAllListeners() // This should be managed more carefully, perhaps not here.
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            print("LoginViewModel: Firebase and Google Sign-Out performed.")
            // AuthStateHandler will update isAuthenticated, which triggers UI changes.
            // isLoading will be reset by the calling view or if an error occurs.
            self.isLoading = false
            completion(true, nil)
        } catch let signOutError as NSError {
            let msg = "Sign out error: \(signOutError.localizedDescription)"
            self.errorMessage = msg; self.isLoading = false; completion(false, msg)
        }
    }
}
