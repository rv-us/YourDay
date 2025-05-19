import SwiftUI

import Firebase
import GoogleSignIn
import GoogleSignInSwift

struct LoginView: View {

    @StateObject var viewModel: LoginViewModel

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                Text("Welcome to YourDay")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Sign in to continue and save your progress.")
                    .font(.headline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()

                if viewModel.isLoading {
                    ProgressView("Signing In...")
                        .scaleEffect(1.5)
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
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.bottom)

            }
            .padding()
            .navigationTitle("Login")
            .navigationBarHidden(true)
        }
       
    }
}

// Preview Provider for LoginView
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide a LoginViewModel instance for the preview.
        LoginView(viewModel: LoginViewModel())
    }
}
