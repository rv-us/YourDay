import SwiftUI
import Firebase
import FirebaseAuth
import GoogleSignIn
import SwiftData
import Network // For NWPathMonitor

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
    private let firebaseManager = FirebaseManager() // Assumes FirebaseManager is from firebase_manager_swift_updated
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
    /// Updates the user's display name in Firebase Authentication AND updates their leaderboard entry.
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
                    self.userDisplayName = trimmedNewName // Update local ViewModel state

                    // Now, update the leaderboard entry
                    if let stats = currentPlayerStats {
                        let leaderboardEntry = LeaderboardEntry(
                            id: user.uid, // Use Firebase Auth UID as the ID for the leaderboard entry
                            displayName: trimmedNewName,
                            playerLevel: stats.playerLevel,
                            gardenValue: stats.gardenValue
                        )
                        self.firebaseManager.updateLeaderboardEntry(entry: leaderboardEntry) { leaderboardError in
                            self.isLoading = false // Ensure loading stops after leaderboard update attempt
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

        if isProcessingFreshLogin {
            print("LoginViewModel: handleUserSession - Processing FRESH LOGIN. Loading from Firestore.")
            initiatePlayerStatsLoadAndUpdateLocal(modelContext: modelContext, thenResetFreshLoginFlag: true)
        } else {
            if let existingLocalStats = localPlayerStats {
                print("LoginViewModel: handleUserSession - App launch, LOCAL PlayerStats EXIST (ID: \(existingLocalStats.id)). Syncing local to Firestore.")
                self.loadedPlayerStatsCodable = PlayerStatsCodable(from: existingLocalStats)
                syncLocalPlayerStatsToFirestore(playerStatsModel: existingLocalStats) { error in
                    if error == nil {
                        print("LoginViewModel: Successfully synced local stats to Firestore on app launch. Now updating leaderboard.")
                        self.updateLeaderboardFromLocalStats(playerStatsModel: existingLocalStats)
                    } else {
                        print("LoginViewModel: Failed to sync local stats to Firestore on app launch: \(error!.localizedDescription)")
                    }
                }
            } else {
                print("LoginViewModel: handleUserSession - App launch, NO local PlayerStats. Loading from Firestore.")
                initiatePlayerStatsLoadAndUpdateLocal(modelContext: modelContext, thenResetFreshLoginFlag: false)
            }
        }
    }
    
    private func initiatePlayerStatsLoadAndUpdateLocal(modelContext: ModelContext, thenResetFreshLoginFlag: Bool) {
        guard let userId = Auth.auth().currentUser?.uid else {
            if self.isLoading { self.isLoading = false }
            if thenResetFreshLoginFlag { self.isProcessingFreshLogin = false }
            return
        }
        
        print("LoginViewModel: Initiating PlayerStats load from Firestore for user \(userId). thenResetFreshLoginFlag: \(thenResetFreshLoginFlag)")
        self.isLoading = true
        self.errorMessage = nil

        firebaseManager.loadPlayerStats { [weak self] statsCodable, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                if let error = error {
                    self.errorMessage = "Failed to load player stats: \(error.localizedDescription)"
                } else if let loadedStatsCodable = statsCodable {
                    self.loadedPlayerStatsCodable = loadedStatsCodable
                    print("LoginViewModel: PlayerStatsCodable loaded/created from Firestore: ID \(loadedStatsCodable.id). Now updating local SwiftData.")
                    self.updateOrCreateLocalPlayerStatsModel(from: loadedStatsCodable, context: modelContext) { updatedLocalStats in
                        if let localStats = updatedLocalStats, thenResetFreshLoginFlag {
                            // After local stats are updated from a fresh login's Firestore data, update leaderboard
                            print("LoginViewModel: Fresh login, local stats updated. Now updating leaderboard.")
                            self.updateLeaderboardFromLocalStats(playerStatsModel: localStats)
                        }
                    }
                } else {
                    self.errorMessage = "Player stats not found, and default could not be established."
                }
                if thenResetFreshLoginFlag {
                    self.isProcessingFreshLogin = false
                    print("LoginViewModel: Finished processing fresh login data load sequence, isProcessingFreshLogin flag reset.")
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

        if var existingLocalStats = localStatsToReturn {
            print("LoginViewModel: Updating existing local PlayerStats (ID: \(existingLocalStats.id)) with Firestore data (Codable ID: \(codableStats.id)).")
            existingLocalStats.totalPoints = codableStats.totalPoints
            existingLocalStats.lastEvaluated = codableStats.lastEvaluated
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
            print("LoginViewModel: No local PlayerStats found. Creating new from Firestore data (Codable ID: \(codableStats.id)).")
            let newLocalStats = PlayerStats(
                totalPoints: codableStats.totalPoints,
                lastEvaluated: codableStats.lastEvaluated,
                playerLevel: codableStats.playerLevel,
                currentXP: codableStats.currentXP,
                unplacedPlantsInventory: codableStats.unplacedPlantsInventory,
                placedPlants: codableStats.placedPlants,
                numberOfOwnedPlots: codableStats.numberOfOwnedPlots,
                fertilizerCount: codableStats.fertilizerCount
            )
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

    func syncLocalPlayerStatsToFirestore(playerStatsModel: PlayerStats, completion: ((Error?) -> Void)? = nil) {
        guard let userId = Auth.auth().currentUser?.uid else {
            completion?(NSError(domain: "AppAuthError", code: 1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated."]))
            return
        }
        print("LoginViewModel: Syncing local PlayerStats (ID: \(playerStatsModel.id)) to Firestore for user \(userId)...")
        
        let playerStatsCodable = PlayerStatsCodable(from: playerStatsModel)
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
                    // After successful save of PlayerStats, update the leaderboard entry
                    self.updateLeaderboardFromLocalStats(playerStatsModel: playerStatsModel)
                }
                completion?(error)
            }
        }
    }

    /// Helper to update leaderboard from local stats.
    private func updateLeaderboardFromLocalStats(playerStatsModel: PlayerStats) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let nameForLeaderboard = self.userDisplayName ?? Auth.auth().currentUser?.displayName ?? "Anonymous"
        
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
                // Optionally set a non-critical error message
            } else {
                print("LoginViewModel: Leaderboard entry updated based on local stats sync.")
            }
        }
    }


    private func clearViewModelDataOnLogout() {
        DispatchQueue.main.async {
            self.loadedPlayerStatsCodable = nil
            self.firebaseManager.removeAllListeners()
            self.isProcessingFreshLogin = false
            print("LoginViewModel: ViewModel's Firestore-related data and flags cleared.")
        }
    }
    
    // MARK: - Sign-In and Sign-Out Methods
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
            // Since isProcessingFreshLogin is true, handleUserSession will load from Firestore,
            // which then calls updateOrCreateLocalPlayerStatsModel, which in turn updates the leaderboard.
            print("LoginViewModel: Firebase sign-in successful for: \(authResult?.user.uid ?? "N/A")")
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
                if let syncError = syncError {
                    let msg = "Failed to sync data: \(syncError.localizedDescription). Sign out aborted."
                    self.errorMessage = msg; self.isLoading = false; completion(false, msg)
                } else {
                    print("LoginViewModel: PlayerStats synced. Proceeding with sign out.")
                    self.performFirebaseAndGoogleSignOut(completion: completion)
                }
            }
        } else {
            print("LoginViewModel: No local PlayerStats to sync. Proceeding with sign out.")
            performFirebaseAndGoogleSignOut(completion: completion)
        }
    }

    private func performFirebaseAndGoogleSignOut(completion: @escaping (_ didSignOut: Bool, _ errorMessage: String?) -> Void) {
        self.isProcessingFreshLogin = false
        firebaseManager.removeAllListeners()
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
}
