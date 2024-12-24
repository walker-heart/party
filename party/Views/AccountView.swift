import SwiftUI

struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authManager: AuthManager
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    // User Info Section
                    VStack(spacing: Theme.Spacing.medium) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(Theme.Colors.primary)
                        
                        if let user = authManager.currentUser {
                            Text("\(user.firstName) \(user.lastName)")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                            
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                        }
                    }
                    .padding(.bottom, Theme.Spacing.large)
                    
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
                        
                        Button(action: signOut) {
                            Text("Sign Out")
                                .foregroundColor(Theme.Colors.error)
                                .font(.headline)
                        }
                        .padding(.top, Theme.Spacing.medium)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
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
}

#Preview {
    AccountView()
        .environmentObject(AuthManager())
} 