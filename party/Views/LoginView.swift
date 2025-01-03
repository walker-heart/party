import SwiftUI
import FirebaseAuth
import GoogleSignInSwift
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showingCreateAccount = false
    @State private var showingPasswordResetConfirmation = false
    @State private var showingPasswordResetSuccess = false
    @State private var isWrongPassword = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    // Logo/Title Area
                    VStack(spacing: Theme.Spacing.medium) {
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Theme.Colors.primary)
                        
                        Text("Party")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                        
                        Text("Sign in to manage your events")
                            .font(.subheadline)
                            .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                    }
                    .padding(.bottom, Theme.Spacing.extraLarge)
                    
                    // Login Form
                    VStack(spacing: Theme.Spacing.medium) {
                        AppTextField(
                            placeholder: "Email",
                            text: $email
                        )
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        
                        AppSecureField(
                            placeholder: "Password",
                            text: $password,
                            textContentType: .password
                        )
                        
                        HStack {
                            Spacer()
                            Button("Forgot Password?") {
                                showingPasswordResetConfirmation = true
                            }
                            .foregroundColor(Theme.Colors.primary)
                            .font(.subheadline)
                        }
                    }
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                    }
                    
                    PrimaryButton(
                        title: "Sign In",
                        action: signIn,
                        isLoading: isLoading
                    )
                    .padding(.top, Theme.Spacing.small)
                    
                    Text("or")
                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                        .padding(.vertical, Theme.Spacing.small)
                    
                    CustomGoogleSignInButton(action: signInWithGoogle)
                        .padding(.horizontal, Theme.Spacing.small)
                    
                    SignInWithAppleButton(
                        onRequest: { request in
                            request.requestedScopes = [.fullName, .email]
                        },
                        onCompletion: { result in
                            Task {
                                do {
                                    try await authManager.signInWithApple()
                                    dismiss()
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }
                    )
                    .frame(height: 44)
                    .cornerRadius(8)
                    .padding(.horizontal, Theme.Spacing.small)
                    
                    Button(action: { showingCreateAccount = true }) {
                        Text("Create Account")
                            .foregroundColor(Theme.Colors.primary)
                    }
                    .padding(.top, Theme.Spacing.small)
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingCreateAccount) {
                CreateAccountView(isShowing: $showingCreateAccount)
            }
            .alert("Reset Password", isPresented: $showingPasswordResetConfirmation) {
                Button("Send Reset Email", role: .destructive) {
                    resetPassword()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("We'll send you an email with instructions to reset your password.")
            }
            .alert("Password Reset Email Sent", isPresented: $showingPasswordResetSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your email for instructions to reset your password.")
            }
        }
    }
    
    private func signIn() {
        guard !email.isEmpty else {
            showError = true
            errorMessage = "Please enter your email"
            return
        }
        
        guard !password.isEmpty else {
            showError = true
            errorMessage = "Please enter your password"
            return
        }
        
        isLoading = true
        showError = false
        isWrongPassword = false
        
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
                dismiss()
            } catch let error as NSError {
                showError = true
                errorMessage = error.localizedDescription
                
                // Check for wrong password or invalid email errors
                if error.domain == AuthErrorDomain {
                    switch error.code {
                    case AuthErrorCode.wrongPassword.rawValue,
                         AuthErrorCode.invalidEmail.rawValue,
                         AuthErrorCode.userNotFound.rawValue:
                        isWrongPassword = true
                    default:
                        break
                    }
                }
            }
            isLoading = false
        }
    }
    
    private func resetPassword() {
        guard !email.isEmpty else {
            showError = true
            errorMessage = "Please enter your email"
            return
        }
        
        Task {
            do {
                // Just send the reset email without modifying providers
                try await Auth.auth().sendPasswordReset(withEmail: email)
                showingPasswordResetSuccess = true
                showError = false
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func signInWithGoogle() {
        isLoading = true
        showError = false
        
        Task {
            do {
                try await authManager.signInWithGoogle()
                dismiss()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct CreateAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authManager: AuthManager
    @Binding var isShowing: Bool
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                
                VStack(spacing: Theme.Spacing.large) {
                    VStack(spacing: Theme.Spacing.medium) {
                        AppTextField(placeholder: "First Name", text: $firstName)
                            .textContentType(.givenName)
                            .autocapitalization(.words)
                        
                        AppTextField(placeholder: "Last Name", text: $lastName)
                            .textContentType(.familyName)
                            .autocapitalization(.words)
                        
                        AppTextField(placeholder: "Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                        
                        AppSecureField(
                            placeholder: "Password",
                            text: $password,
                            textContentType: .newPassword
                        )
                    }
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                            .padding(.top, Theme.Spacing.small)
                    }
                    
                    PrimaryButton(
                        title: "Create Account",
                        action: createAccount,
                        isLoading: isLoading
                    )
                }
                .padding()
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isShowing = false
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
        }
    }
    
    private func createAccount() {
        guard !firstName.isEmpty else {
            showError = true
            errorMessage = "Please enter your first name"
            return
        }
        
        guard !lastName.isEmpty else {
            showError = true
            errorMessage = "Please enter your last name"
            return
        }
        
        guard !email.isEmpty else {
            showError = true
            errorMessage = "Please enter your email"
            return
        }
        
        guard !password.isEmpty else {
            showError = true
            errorMessage = "Please enter a password"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await authManager.signUp(
                    email: email,
                    password: password,
                    firstName: firstName,
                    lastName: lastName
                )
                dismiss()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}

struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        CreateAccountView(isShowing: .constant(true))
            .environmentObject(AuthManager())
    }
} 
