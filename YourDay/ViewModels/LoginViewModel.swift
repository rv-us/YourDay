import SwiftUI
import Firebase // Make sure FirebaseCore is configured
import FirebaseAuth
import GoogleSignIn
// GoogleSignInSwift is not directly needed here if GIDSignInButton is only in LoginView

class LoginViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isLoading: Bool = false
    @Published var userDisplayName: String? = nil
    @Published var userEmail: String? = nil

    private var authStateHandler: AuthStateDidChangeListenerHandle?

    init() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            DispatchQueue.main.async {
                self?.isAuthenticated = (user != nil)
                // Update user information when auth state changes
                self?.userDisplayName = user?.displayName
                self?.userEmail = user?.email
                // isLoading should be set to false when the auth state changes,
                // especially after a sign-in attempt (success or failure).
                if self?.isLoading == true { // Only change if it was actively loading
                    self?.isLoading = false
                }
                if user == nil {
                    print("User is not authenticated.")
                } else {
                    print("User is authenticated: \(user?.uid ?? "No UID")")
                }
            }
        }
        
        // Immediately set user info if user is already signed in
        if let currentUser = Auth.auth().currentUser {
            self.userDisplayName = currentUser.displayName
            self.userEmail = currentUser.email
        }
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }

    func checkAuthenticationState() {
        DispatchQueue.main.async {
             self.isAuthenticated = (Auth.auth().currentUser != nil)
             if let currentUser = Auth.auth().currentUser {
                 self.userDisplayName = currentUser.displayName
                 self.userEmail = currentUser.email
             }
        }
    }
    
    internal func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("Error: Could not get root view controller.")
            return nil
        }
        var currentViewController = rootViewController
        while let presentedController = currentViewController.presentedViewController {
            currentViewController = presentedController
        }
        return currentViewController
    }

    // Consolidated method to handle Google Sign-In and Firebase authentication
    func signInWithGoogle() {
        self.isLoading = true
        self.errorMessage = nil

        // 1. Get Firebase Client ID
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            self.errorMessage = "Firebase client ID not found."
            self.isLoading = false
            return
        }

        // 2. Create GIDConfiguration
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        // 3. Get Root View Controller
        guard let presentingViewController = getRootViewController() else {
            self.errorMessage = "Could not find a presenting view controller."
            self.isLoading = false
            return
        }
        
        // 4. Start Google Sign-In
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { [weak self] signInResult, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                self.isLoading = false
                return
            }

            guard let result = signInResult else {
                self.errorMessage = "Google Sign-In result is unexpectedly nil."
                self.isLoading = false
                return
            }
            
            guard let idToken = result.user.idToken?.tokenString else {
                self.errorMessage = "Could not get Google ID token."
                self.isLoading = false
                return
            }
            
            let accessToken = result.user.accessToken.tokenString

            // 5. Create Firebase credential
            let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                             accessToken: accessToken)
            
            // 6. Sign in to Firebase
            self.signInToFirebase(with: credential)
        }
    }

    // This method is now primarily called by signInWithGoogle()
    private func signInToFirebase(with credential: AuthCredential) {
        // isLoading is already true from signInWithGoogle()
        // errorMessage might have been cleared or set by signInWithGoogle()

        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            guard let self = self else { return }
            // isLoading will be set to false by the authStateHandler's observation
            // or explicitly if there's an error here.
            if let error = error {
                self.errorMessage = "Firebase Sign-In failed: \(error.localizedDescription)"
                self.isLoading = false // Explicitly set here for Firebase-specific error
                return
            }
            // Successfully signed into Firebase.
            // isAuthenticated will be updated by the authStateHandler.
            // isLoading will also be handled by authStateHandler.
            print("Successfully signed into Firebase with Google: \(authResult?.user.uid ?? "No UID")")
        }
    }

    func signOut() {
        isLoading = true
        errorMessage = nil
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            self.userDisplayName = nil
            self.userEmail = nil
            print("Successfully signed out.")
        } catch let signOutError as NSError {
            errorMessage = "Error signing out: \(signOutError.localizedDescription)"
        }
        // isLoading will be reset by the authStateListener.
        // If not, uncomment: self.isLoading = false
    }
}
