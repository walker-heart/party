import SwiftUI
import GoogleSignInSwift

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(Color.white)
                        .padding(.trailing, 8)
                }
                
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Theme.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(Theme.CornerRadius.medium)
        }
        .disabled(isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Theme.Colors.surfaceLight(colorScheme))
                .foregroundColor(Theme.Colors.primary)
                .cornerRadius(Theme.CornerRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                        .stroke(Theme.Colors.primary, lineWidth: 1)
                )
        }
    }
}

struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Group {
            if isSecure {
                SecureField("", text: $text)
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                    .accentColor(Theme.Colors.primary)
                    .textFieldStyle(.plain)
            } else {
                TextField("", text: $text)
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                    .accentColor(Theme.Colors.primary)
                    .textFieldStyle(.plain)
            }
        }
        .padding()
        .background(Theme.Colors.surfaceLight(colorScheme))
        .cornerRadius(Theme.CornerRadius.medium)
        .tint(Theme.Colors.primary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .overlay {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                    .padding(.leading, Theme.Spacing.medium)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct AppSecureField: View {
    let placeholder: String
    @Binding var text: String
    var textContentType: UITextContentType? = nil
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        SecureField("", text: $text)
            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
            .accentColor(Theme.Colors.primary)
            .textFieldStyle(.plain)
            .padding()
            .background(Theme.Colors.surfaceLight(colorScheme))
            .cornerRadius(Theme.CornerRadius.medium)
            .tint(Theme.Colors.primary)
            .textContentType(textContentType)
            .overlay {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Theme.Colors.textSecondary(colorScheme))
                        .padding(.leading, Theme.Spacing.medium)
                        .allowsHitTesting(false)
                }
            }
    }
}

// Helper view modifier for placeholder
extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

struct PartyCard: View {
    let name: String
    let passcode: String
    let creatorId: String
    let currentUserId: String?
    let action: () -> Void
    let onDelete: () -> Void
    let onRemove: () -> Void
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingLeaveConfirmation = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                HStack {
                    Text(name)
                        .font(.headline)
                        .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                    
                    Spacer()
                    
                    HStack(spacing: Theme.Spacing.medium) {
                        if let userId = currentUserId {
                            if userId != creatorId {
                                Button(action: {
                                    if let party = authManager.activeParties.first(where: { $0.name == name }),
                                       party.editors.contains(userId) {
                                        showingLeaveConfirmation = true
                                    } else {
                                        onRemove()
                                    }
                                }) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .foregroundColor(Theme.Colors.error)
                                }
                            }
                        }
                        
                        if currentUserId == creatorId || authManager.currentUser?.isAdmin == true {
                            Button(action: onDelete) {
                                Image(systemName: "trash")
                                    .foregroundColor(Theme.Colors.error)
                            }
                        }
                    }
                }
                
                Text("Passcode: \(passcode)")
                    .font(.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary(colorScheme))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.surfaceLight(colorScheme))
            .cornerRadius(Theme.CornerRadius.medium)
        }
        .alert("Leave Party", isPresented: $showingLeaveConfirmation) {
            Button("Leave", role: .destructive) {
                onRemove()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to leave this party? You will be removed as an editor.")
        }
    }
}

struct StatusBadge: View {
    let isPresent: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Text(isPresent ? "Present" : "Absent")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isPresent ? Theme.Colors.success : Theme.Colors.error)
            .cornerRadius(Theme.CornerRadius.small)
    }
}

struct CustomGoogleSignInButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(colorScheme == .dark ? Color(white: 0.15) : .white)
            .foregroundColor(colorScheme == .dark ? .white : Color.black.opacity(0.54))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
    }
}

// Add preview
#Preview {
    VStack {
        AppSecureField(placeholder: "Password", text: .constant(""))
        AppSecureField(placeholder: "Password", text: .constant("test"), textContentType: .password)
    }
    .padding()
} 
