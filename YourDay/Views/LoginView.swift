import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift

let plantDarkGreen = Color(hex: "#477468")
let plantMediumGreen = Color(hex: "#3A9C75")
let plantDustyBlue = Color(hex: "#82A9BF")
let plantBeige = Color(hex: "#EEE7D6")


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

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
