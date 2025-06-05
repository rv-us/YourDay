import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

// The Color extension and the global color constants (plantDarkGreen, plantMediumGreen, etc.)
// are now assumed to be defined elsewhere (e.g., in your ShopView.swift or a dedicated extensions file)
// and are accessible here.

struct LoginView: View {

    @StateObject var viewModel: LoginViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                Text("Welcome to YourDay")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(plantDarkGreen)
                    .multilineTextAlignment(.center)

                Text("Sign in to continue and save your progress.")
                    .font(.headline)
                    .foregroundColor(plantMediumGreen)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()

                if viewModel.isLoading {
                    ProgressView("Signing In...")
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: plantMediumGreen))
                } else {
                    GoogleSignInButton(action: {
                          viewModel.signInWithGoogle()
                      })
                    .frame(height: 50)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top, 10)
                }
                
                Spacer()
                Spacer()
                
                Text("By signing in, you agree to our Terms of Service and Privacy Policy.")
                    .font(.caption2)
                    .foregroundColor(plantDustyBlue)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)

            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(plantBeige.edgesIgnoringSafeArea(.all))
            .navigationTitle("Login")
            .navigationBarHidden(true)
        }
    }
}
