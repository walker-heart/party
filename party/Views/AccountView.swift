import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authManager: AuthManager
    @State private var isEditing = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPasswordResetConfirmation = false
    @State private var showingPasswordResetSuccess = false
    @State private var showingAddEmailPassword = false
    @State private var email = ""
    @State private var password = ""
    @State private var showingRemoveProviderConfirmation = false
    @State private var providerToRemove: String?
    @State private var isLinkingGoogle = false
    @State private var showingPasswordVerification = false
    @State private var verificationPassword = ""
    @State private var showingDeletePasswordVerification = false
    @State private var deleteAccountPassword = ""
    @State private var showingPasswordResetWarning = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.large) {
                        // User Info Section
                        VStack(spacing: Theme.Spacing.medium) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.Colors.primary)
                            
                            if let user = authManager.currentUser {
                                if isEditing {
                                    VStack(spacing: Theme.Spacing.medium) {
                                        AppTextField(placeholder: "First Name", text: $firstName)
                                        AppTextField(placeholder: "Last Name", text: $lastName)
                                    }
                                } else {
                                    Text("\(user.firstName) \(user.lastName)")
                                        .font(.title2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                                }
                                
                                Text(user.email)
                                    .font(.subheadline)
                                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                            }
                        }
                        .padding(.bottom, Theme.Spacing.large)
                        
                        if showError {
                            Text(errorMessage)
                                .foregroundColor(Theme.Colors.error)
                                .font(.caption)
                        }
                        
                        // Account Actions
                        VStack(spacing: Theme.Spacing.medium) {
                            if authManager.currentUser?.isAdmin == true {
                                Text("Admin Account")
                                    .font(.caption)
                                    .padding(.horizontal, Theme.Spacing.medium)
                                    .padding(.vertical, Theme.Spacing.small)
                                    .background(Theme.Colors.primary.opacity(0.2))
                                    .foregroundColor(Theme.Colors.primary)
                                    .cornerRadius(Theme.CornerRadius.small)
                            }
                            
                            // Authentication Methods
                            if let user = authManager.currentUser {
                                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                                    HStack {
                                        Text("Sign-in Methods")
                                            .font(.headline)
                                            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                                        
                                        Spacer()
                                        
                                        if !user.authProviders.contains("password") || !user.authProviders.contains("google.com") {
                                            Menu {
                                                if !user.authProviders.contains("password") {
                                                    Button(action: { showingAddEmailPassword = true }) {
                                                        Label("Add Email/Password", systemImage: "key.fill")
                                                    }
                                                }
                                                if !user.authProviders.contains("google.com") {
                                                    if isLinkingGoogle {
                                                        Label("Linking Google...", systemImage: "hourglass")
                                                    } else {
                                                        Button(action: linkGoogle) {
                                                            Label("Add Google Account", systemImage: "g.circle.fill")
                                                        }
                                                    }
                                                }
                                            } label: {
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(Theme.Colors.primary)
                                            }
                                            .disabled(isLinkingGoogle)
                                        }
                                    }
                                    
                                    ForEach(user.authProviders, id: \.self) { provider in
                                        HStack {
                                            Image(systemName: getProviderIcon(provider))
                                            Text(getProviderDisplayName(provider))
                                            
                                            Spacer()
                                            
                                            if provider == "password" {
                                                Button("Reset Password") {
                                                    showingPasswordResetWarning = true
                                                }
                                                .foregroundColor(Theme.Colors.primary)
                                                .font(.subheadline)
                                            }
                                            
                                            if user.authProviders.count > 1 {
                                                Button(action: {
                                                    providerToRemove = provider
                                                    showingRemoveProviderConfirmation = true
                                                }) {
                                                    Image(systemName: "minus.circle.fill")
                                                        .foregroundColor(Theme.Colors.error)
                                                }
                                            }
                                        }
                                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                                        .padding(.vertical, 4)
                                    }
                                }
                                .padding()
                                .background(Theme.Colors.surfaceLight(colorScheme))
                                .cornerRadius(Theme.CornerRadius.medium)
                            }
                            
                            // Sign Out Button
                            Button(action: signOut) {
                                Text("Sign Out")
                                    .foregroundColor(Theme.Colors.error)
                                    .font(.headline)
                            }
                            .padding(.top, Theme.Spacing.medium)
                            
                            // Delete Account Button
                            Button(action: { showingDeleteConfirmation = true }) {
                                Text("Delete Account")
                                    .foregroundColor(Theme.Colors.error)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                            resetFields()
                        }
                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button(action: saveChanges) {
                            if isLoading {
                                ProgressView()
                                    .tint(Theme.Colors.primary)
                            } else {
                                Text("Save")
                                    .foregroundColor(Theme.Colors.primary)
                            }
                        }
                        .disabled(isLoading)
                    } else {
                        Button("Edit") {
                            startEditing()
                        }
                        .foregroundColor(Theme.Colors.primary)
                    }
                }
            }
            .alert("Delete Account", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete your account? This action cannot be undone.")
            }
            .alert("Warning", isPresented: $showingPasswordResetWarning) {
                Button("Reset Password", role: .destructive) {
                    showingPasswordResetConfirmation = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Resetting your password will remove all other authentication providers (Google, Apple). Are you sure you want to continue?")
            }
            .alert("Reset Password?", isPresented: $showingPasswordResetConfirmation) {
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
            .alert("Remove Sign-in Method", isPresented: $showingRemoveProviderConfirmation) {
                Button("Remove", role: .destructive) {
                    if let provider = providerToRemove {
                        if provider == "password" {
                            showingPasswordVerification = true
                        } else {
                            removeAuthProvider(provider)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let provider = providerToRemove {
                    Text(provider == "password" ? 
                         "Are you sure you want to remove email/password sign-in?" :
                         "Are you sure you want to remove Google sign-in?")
                }
            }
            .alert("Verify Password", isPresented: $showingPasswordVerification) {
                SecureField("Current Password", text: $verificationPassword)
                Button("Remove", role: .destructive) {
                    if let provider = providerToRemove {
                        removeAuthProvider(provider, password: verificationPassword)
                    }
                    verificationPassword = ""
                }
                Button("Cancel", role: .cancel) {
                    verificationPassword = ""
                }
            } message: {
                Text("Please enter your current password to remove email/password sign-in.")
            }
            .sheet(isPresented: $showingAddEmailPassword) {
                NavigationView {
                    ZStack {
                        Theme.Colors.background(colorScheme)
                            .ignoresSafeArea()
                        
                        VStack(spacing: Theme.Spacing.large) {
                            VStack(spacing: Theme.Spacing.medium) {
                                if let user = authManager.currentUser {
                                    Text(user.email)
                                        .font(.headline)
                                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                                    
                                    AppSecureField(
                                        placeholder: "New Password",
                                        text: $password,
                                        textContentType: .newPassword
                                    )
                                }
                            }
                            
                            if showError {
                                Text(errorMessage)
                                    .foregroundColor(Theme.Colors.error)
                                    .font(.caption)
                            }
                            
                            PrimaryButton(
                                title: "Add Password Authentication",
                                action: addEmailPassword,
                                isLoading: isLoading
                            )
                        }
                        .padding()
                    }
                    .navigationTitle("Add Password")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showingAddEmailPassword = false
                                password = ""
                                showError = false
                            }
                            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                        }
                    }
                }
            }
        }
    }
    
    private func startEditing() {
        if let user = authManager.currentUser {
            firstName = user.firstName
            lastName = user.lastName
        }
        isEditing = true
    }
    
    private func resetFields() {
        firstName = ""
        lastName = ""
        showError = false
        errorMessage = ""
    }
    
    private func saveChanges() {
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
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await authManager.updateUserProfile(firstName: firstName, lastName: lastName)
                isEditing = false
                resetFields()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func signOut() {
        Task {
            do {
                try await authManager.signOut()
                dismiss()
            } catch {
                print("Error signing out:", error.localizedDescription)
            }
        }
    }
    
    private func resetPassword() {
        Task {
            do {
                try await authManager.sendPasswordResetEmail()
                showingPasswordResetSuccess = true
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func addEmailPassword() {
        guard !password.isEmpty else {
            showError = true
            errorMessage = "Please enter a password"
            return
        }
        
        guard let user = authManager.currentUser else {
            showError = true
            errorMessage = "No user found"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await authManager.linkEmailPassword(email: user.email, password: password)
                showingAddEmailPassword = false
                password = ""
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
    
    private func linkGoogle() {
        isLinkingGoogle = true
        showError = false
        
        Task {
            do {
                try await authManager.linkGoogleAccount()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLinkingGoogle = false
        }
    }
    
    private func removeAuthProvider(_ provider: String, password: String? = nil) {
        Task {
            do {
                try await authManager.removeAuthProvider(provider, password: password)
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func deleteAccount(password: String? = nil) {
        Task {
            do {
                try await authManager.deleteAccount()
                dismiss()
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
        }
    }
    
    private func getProviderIcon(_ provider: String) -> String {
        switch provider {
        case "password":
            return "key.fill"
        case "google.com":
            return "g.circle.fill"
        case "apple.com":
            return "apple.logo"
        default:
            return "questionmark.circle.fill"
        }
    }
    
    private func getProviderDisplayName(_ provider: String) -> String {
        switch provider {
        case "password":
            return "Email and Password"
        case "google.com":
            return "Google"
        case "apple.com":
            return "Apple"
        default:
            return provider
        }
    }
}

#Preview {
    AccountView()
        .environmentObject(AuthManager())
} 