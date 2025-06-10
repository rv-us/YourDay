import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices // Import for Apple Sign In

// MARK: - Login View
struct LoginView: View {

    @StateObject var viewModel: LoginViewModel
    
    // State for managing focus on different text fields
    private enum Field: Int, Hashable {
        case displayName, email, password, guestName
    }
    @FocusState private var focusedField: Field?
    
    @State private var isRegistering = false

    var body: some View {
        NavigationView {
            // Using a ZStack allows us to place a tappable background
            // behind the content, resolving the gesture conflict.
            ZStack {
                // This is the tappable background.
                LightTheme.background
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Dismiss the keyboard when the background is tapped.
                        focusedField = nil
                    }
                
                // All UI content goes inside a ScrollView for smaller devices.
                ScrollView {
                    VStack(spacing: 15) {
                        Spacer(minLength: 50)

                        Text("Welcome to YourDay")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(LightTheme.text)
                            .multilineTextAlignment(.center)

                        Text("Sign in to save your progress online or continue as a guest.")
                            .font(.headline)
                            .foregroundColor(LightTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        if viewModel.isLoading {
                            ProgressView("Please Wait...")
                                .progressViewStyle(CircularProgressViewStyle(tint: LightTheme.accent))
                                .scaleEffect(1.5)
                                .padding(.vertical, 50)
                        } else {
                            // MARK: Email/Password Form
                            VStack {
                                Picker("Login or Register", selection: $isRegistering) {
                                    Text("Sign In").tag(false)
                                    Text("Create Account").tag(true)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .padding(.bottom)
                                .onAppear {
                                     UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(LightTheme.accent)
                                     UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(LightTheme.secondaryBackground)], for: .selected)
                                     UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(LightTheme.text)], for: .normal)
                                 }

                                if isRegistering {
                                    TextField("Display Name", text: $viewModel.displayNameForRegistration)
                                        .textContentType(.nickname)
                                        .autocapitalization(.words)
                                        .focused($focusedField, equals: .displayName)
                                }

                                TextField("Email", text: $viewModel.email)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .focused($focusedField, equals: .email)
                                
                                SecureField("Password", text: $viewModel.password)
                                    .textContentType(isRegistering ? .newPassword : .password)
                                    .focused($focusedField, equals: .password)

                                Button(action: {
                                    focusedField = nil // Dismiss keyboard on button press
                                    if isRegistering {
                                        viewModel.createAccountWithEmailPassword()
                                    } else {
                                        viewModel.signInWithEmailPassword()
                                    }
                                }) {
                                    Text(isRegistering ? "Create Account" : "Sign In")
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(LightTheme.accent)
                                        .foregroundColor(LightTheme.secondaryBackground)
                                        .cornerRadius(8)
                                }
                                .padding(.top, 5)
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding(.horizontal)

                            // MARK: Divider
                            HStack {
                                VStack { Divider() }
                                Text("OR")
                                VStack { Divider() }
                            }
                            .foregroundColor(LightTheme.secondaryText)
                            .padding()

                            // MARK: Social & Guest Logins
                            
                            // Apple Sign In Button
                            SignInWithAppleButton(
                                .signIn,
                                onRequest: viewModel.handleAppleSignInRequest,
                                onCompletion: viewModel.handleAppleSignInCompletion
                            )
                            .signInWithAppleButtonStyle(.black) // Or .white, .whiteOutline
                            .frame(height: 50)
                            .cornerRadius(8)
                            .padding(.horizontal)
                            .accessibilityLabel("Sign in with Apple")
                            
                            // Google Sign In Button
                            GoogleSignInButton(scheme: .light, style: .wide, state: .normal, action: viewModel.signInWithGoogle)
                                .frame(height: 50)
                                .padding(.horizontal)
                                .accessibilityLabel("Sign in with Google")

                            TextField("Enter Your Guest Name", text: $viewModel.guestDisplayName)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.nickname)
                                .autocapitalization(.words)
                                .multilineTextAlignment(.center)
                                .focused($focusedField, equals: .guestName)
                                .padding(.horizontal)

                            Button(action: {
                                focusedField = nil
                                viewModel.startGuestSession()
                            }) {
                                Text("Continue as Guest")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(isGuestButtonDisabled ? LightTheme.accent.opacity(0.5) : LightTheme.accent)
                                    .foregroundColor(LightTheme.secondaryBackground)
                                    .cornerRadius(8)
                            }
                            .frame(height: 50)
                            .padding(.horizontal)
                            .disabled(isGuestButtonDisabled)
                            .accessibilityLabel("Continue as a guest")
                        }

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(LightTheme.destructive)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, 10)
                        }
                        
                        Spacer()
                        
                        Text("By signing in or creating an account, you agree to our Terms of Service and Privacy Policy.")
                            .font(.caption2)
                            .foregroundColor(LightTheme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 10)

                    }
                    .padding()
                }
            }
            .navigationTitle("Welcome")
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }

    private var isGuestButtonDisabled: Bool {
        viewModel.guestDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
