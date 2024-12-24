import SwiftUI
import FirebaseAuth

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
                    
                    Button(action: { showingCreateAccount = true }) {
                        Text("Create Account")
                            .foregroundColor(Theme.Colors.primary)
                    }
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingCreateAccount) {
                CreateAccountView(isShowing: $showingCreateAccount)
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
        
        Task {
            do {
                try await authManager.signIn(email: email, password: password)
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
