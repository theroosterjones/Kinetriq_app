import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject private var auth = AuthService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false
    @State private var currentNonce: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    form
                    actionButton
                    appleSignInSection
                    secondaryActions
                    legalLinks
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Account", isPresented: .init(
                get: { auth.authError != nil },
                set: { if !$0 { auth.authError = nil } }
            )) {
                Button("OK") { auth.authError = nil }
            } message: {
                Text(auth.authError ?? "")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text("Kinetriq")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Sign in once and use your subscription across iOS, Android, and web.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textContentType(isSignUpMode ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)

            if let hint = validationHint {
                Label(hint, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !auth.isConfigured {
                Label("Development mode: Supabase keys are placeholders, so sign-in creates a local test account.", systemImage: "wrench.and.screwdriver")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var actionButton: some View {
        Button {
            Task {
                if isSignUpMode {
                    await auth.signUp(email: email, password: password)
                } else {
                    await auth.signIn(email: email, password: password)
                }
            }
        } label: {
            Group {
                if auth.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(isSignUpMode ? "Create Account" : "Sign In")
                        .font(.headline.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isFormValid ? Color.blue : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isFormValid || auth.isLoading)
    }

    private var appleSignInSection: some View {
        VStack(spacing: 16) {
            HStack {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text("or")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }

            SignInWithAppleButton(.signIn) { request in
                let nonce = AuthService.randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthService.sha256(nonce)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authResults):
            guard let credential = authResults.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce else {
                auth.authError = "Apple sign-in could not be completed. Please try again."
                return
            }
            Task {
                await auth.signInWithApple(
                    idTokenData: credential.identityToken,
                    rawNonce: nonce,
                    fullName: credential.fullName
                )
            }
        case .failure(let error):
            // Don't surface an error banner when the user simply cancels.
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            auth.authError = error.localizedDescription
        }
    }

    private var secondaryActions: some View {
        VStack(spacing: 12) {
            Button(isSignUpMode ? "Already have an account? Sign in" : "New to Kinetriq? Create an account") {
                isSignUpMode.toggle()
            }
            .font(.footnote)

            Button("Forgot password?") {
                Task { await auth.sendPasswordReset(email: email) }
            }
            .font(.footnote)
            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 18) {
            if let privacyURL = AppEnvironment.privacyPolicyURL {
                Link("Privacy Policy", destination: privacyURL)
            }
            if let termsURL = AppEnvironment.termsURL {
                Link("Terms", destination: termsURL)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var isFormValid: Bool {
        email.contains("@") && password.count >= 6
    }

    /// Explains why the action button is disabled so the form never feels broken.
    private var validationHint: String? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty && password.isEmpty {
            return "Enter your email and a password of at least 6 characters."
        }
        if !email.contains("@") {
            return "Enter a valid email address."
        }
        if password.count < 6 {
            return "Password must be at least 6 characters."
        }
        return nil
    }
}
