import SwiftUI
import Firebase
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices // Import for Apple Sign In

// MARK: - Login View (Carousel landing)
struct LoginView: View {
    @StateObject var viewModel: LoginViewModel
    @State private var showAuthForm = false
    @State private var isRegistering = false

    private let carouselImages: [String] = [
        "summer-legendary",
        "spring-legendary",
        "spring-epic",
        "fall-common1",
        "summer-common1"
    ]

    var body: some View {
        NavigationView {
            ZStack {
                Color.white.ignoresSafeArea()

                if showAuthForm || viewModel.pendingLinkCredential != nil {
                    LoginFormView(viewModel: viewModel, isRegistering: $isRegistering, onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAuthForm = false
                        }
                        // Clear pending link if user goes back
                        viewModel.pendingLinkCredential = nil
                        viewModel.pendingLinkProviderName = nil
                    })
                    .transition(.move(edge: .trailing))
                } else {
                    CarouselLoginLandingView(
                        viewModel: viewModel,
                        images: carouselImages,
                        onSignUpWithEmail: {
                            isRegistering = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAuthForm = true
                            }
                        },
                        onLogIn: {
                            isRegistering = false
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAuthForm = true
                            }
                        }
                    )
                    .transition(.move(edge: .leading))
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onChange(of: viewModel.pendingLinkCredential) { _, newValue in
            // Automatically show email/password form when linking is needed
            if newValue != nil && !showAuthForm {
                isRegistering = false // Force sign-in mode
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAuthForm = true
                }
            }
        }
    }
}

// MARK: - Carousel Landing Screen
private struct CarouselLoginLandingView: View {
    @ObservedObject var viewModel: LoginViewModel
    let images: [String]
    let onSignUpWithEmail: () -> Void
    let onLogIn: () -> Void

    @State private var selectedIndex: Int = 1
    @State private var carouselTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            LoginCarouselHeaderView(images: images, selectedIndex: $selectedIndex)
                .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Text("YourDay")
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundColor(.black)

                Text("Capture and organize your days, goals, and moments.")
                    .multilineTextAlignment(.center)
                    .frame(width: 280)
                    .foregroundColor(.black.opacity(0.7))
            }
            .padding(.bottom)

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signUp) { request in
                    viewModel.handleAppleSignInRequest(request)
                } onCompletion: { result in
                    viewModel.handleAppleSignInCompletion(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .frame(maxWidth: .infinity)

                Button(action: { viewModel.signInWithGoogle() }) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(.white)
                .foregroundStyle(.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                )

                Button(action: onSignUpWithEmail) {
                    Text("Sign up with Email")
                        .padding(4)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(dynamicPrimaryColor)
                .foregroundStyle(Color.white)
            }
            .font(.system(.title3, weight: .medium))
            .frame(width: 290)

            Spacer()

            Button(action: onLogIn) {
                Text("Already signed up? Log in")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
        .background(Color.white)
        .overlay {
            if viewModel.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Please wait...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)
            }
        }
        .alert("Sign-in error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .onAppear {
            // Start auto-scrolling carousel
            carouselTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                guard !images.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    selectedIndex = (selectedIndex + 1) % images.count
                }
            }
        }
        .onDisappear {
            // Stop timer when view disappears
            carouselTimer?.invalidate()
            carouselTimer = nil
        }
    }
}

// MARK: - Carousel Header (layered cards)
private struct LoginCarouselHeaderView: View {
    let images: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        ZStack {
            // Back-most row
            HStack(spacing: 150) {
                carouselCard(name: image(at: selectedIndex - 2), height: 108)
                carouselCard(name: image(at: selectedIndex + 2), height: 108)
            }

            // Middle row
            HStack {
                carouselCard(name: image(at: selectedIndex - 1), height: 158)
                carouselCard(name: image(at: selectedIndex + 1), height: 158)
            }

            // Front (swipeable)
            TabView(selection: $selectedIndex) {
                ForEach(images.indices, id: \.self) { idx in
                    carouselCard(name: images[idx], height: 200)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal)
    }

    private func image(at index: Int) -> String {
        guard !images.isEmpty else { return "" }
        let safeIndex = (index % images.count + images.count) % images.count
        return images[safeIndex]
    }

    private func carouselCard(name: String, height: CGFloat) -> some View {
        Image(name)
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(height: height)
            .clipped()
    }
}

// MARK: - Existing Auth Form (refactored)
private struct LoginFormView: View {
    @ObservedObject var viewModel: LoginViewModel
    @Binding var isRegistering: Bool
    let onBack: () -> Void

    // State for managing focus on different text fields
    private enum Field: Int, Hashable {
        case displayName, email, password
    }
    @FocusState private var focusedField: Field?

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
                .onTapGesture { focusedField = nil }

            ScrollView {
                VStack(spacing: 15) {
                    HStack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.black)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)

                    Text(isRegistering ? "Create Account" : "Welcome Back")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)

                    if viewModel.pendingLinkCredential != nil, let providerName = viewModel.pendingLinkProviderName {
                        Text("This email is already registered. Sign in with your email and password to add \(providerName) sign-in to your account.")
                            .font(.headline)
                            .foregroundColor(dynamicPrimaryColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 8)
                    } else {
                        Text("Sign in to sync your progress across devices.")
                            .font(.headline)
                            .foregroundColor(.black.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }

                    if viewModel.isLoading {
                        ProgressView("Please Wait...")
                            .progressViewStyle(CircularProgressViewStyle(tint: dynamicPrimaryColor))
                            .scaleEffect(1.2)
                            .padding(.vertical, 50)
                    } else {
                        VStack(spacing: 14) {
                            // Custom pill toggle (replaces SegmentedPickerStyle)
                            // Hide toggle when linking account (only allow sign-in)
                            if viewModel.pendingLinkCredential == nil {
                                HStack(spacing: 0) {
                                    Button {
                                        focusedField = nil
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isRegistering = false
                                        }
                                    } label: {
                                        Text("Sign In")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .foregroundColor(isRegistering ? .black.opacity(0.65) : .white)
                                            .background(isRegistering ? Color.clear : dynamicPrimaryColor)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        focusedField = nil
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isRegistering = true
                                        }
                                    } label: {
                                        Text("Create Account")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .foregroundColor(isRegistering ? .white : .black.opacity(0.65))
                                            .background(isRegistering ? dynamicPrimaryColor : Color.clear)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(4)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.06))
                                )
                                .padding(.bottom, 6)
                            } else {
                                // When linking, only sign-in is allowed; keep UI minimal
                                EmptyView()
                                    .onAppear {
                                        if isRegistering { isRegistering = false }
                                    }
                            }

                            if isRegistering {
                                AuthTextField(
                                    title: "Display Name",
                                    systemImage: "person",
                                    text: $viewModel.displayNameForRegistration,
                                    contentType: .nickname,
                                    keyboardType: .default,
                                    autocapitalization: .words
                                )
                                .focused($focusedField, equals: .displayName)
                            }

                            AuthTextField(
                                title: "Email",
                                systemImage: "envelope",
                                text: $viewModel.email,
                                contentType: .emailAddress,
                                keyboardType: .emailAddress,
                                autocapitalization: .never,
                                disableAutocorrection: true
                            )
                            .focused($focusedField, equals: .email)

                            AuthSecureField(
                                title: "Password",
                                systemImage: "lock",
                                text: $viewModel.password,
                                contentType: isRegistering ? .newPassword : .password
                            )
                            .focused($focusedField, equals: .password)

                            Button(action: {
                                focusedField = nil
                                // When linking, only allow sign-in (not create account)
                                if viewModel.pendingLinkCredential != nil || !isRegistering {
                                    viewModel.signInWithEmailPassword()
                                } else {
                                    viewModel.createAccountWithEmailPassword()
                                }
                            }) {
                                Text(viewModel.pendingLinkCredential != nil ? "Sign In & Link Account" : (isRegistering ? "Create Account" : "Sign In"))
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(dynamicPrimaryColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.top, 5)

                            if !isRegistering {
                                Button(action: viewModel.sendPasswordResetEmail) {
                                    Text("Forgot your password?")
                                        .font(.footnote)
                                        .foregroundColor(dynamicPrimaryColor)
                                        .underline()
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.top, 4)
                                }
                            }
                        }
                        .padding(.horizontal, 20)

                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(dynamicDestructiveColor)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 10)
                    }

                    Spacer(minLength: 10)

                    Text("By signing in or creating an account, you agree to our Terms of Service and Privacy Policy.")
                        .font(.caption2)
                        .foregroundColor(.black.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 10)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
    }
}

// MARK: - Pretty text fields
private struct AuthTextField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let contentType: UITextContentType?
    let keyboardType: UIKeyboardType
    let autocapitalization: TextInputAutocapitalization
    let disableAutocorrection: Bool

    init(
        title: String,
        systemImage: String,
        text: Binding<String>,
        contentType: UITextContentType? = nil,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences,
        disableAutocorrection: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self._text = text
        self.contentType = contentType
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.disableAutocorrection = disableAutocorrection
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.black.opacity(0.55))
                .frame(width: 18)

            TextField(
                "",
                text: $text,
                prompt: Text(title)
                    .foregroundColor(.black.opacity(0.5))
            )
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(disableAutocorrection)
                .foregroundColor(.black)
                .tint(dynamicPrimaryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

private struct AuthSecureField: View {
    let title: String
    let systemImage: String
    @Binding var text: String
    let contentType: UITextContentType?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundColor(.black.opacity(0.55))
                .frame(width: 18)

            SecureField(
                "",
                text: $text,
                prompt: Text(title)
                    .foregroundColor(.black.opacity(0.5))
            )
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .foregroundColor(.black)
                .tint(dynamicPrimaryColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}
