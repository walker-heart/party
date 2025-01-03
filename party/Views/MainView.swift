import SwiftUI

// MARK: - Main View
struct MainView: View {
    @StateObject private var authManager = AuthManager()
    @StateObject private var partyManager = PartyManager()
    @State private var showingCreateParty = false
    @State private var showingJoinParty = false
    @State private var showingAttendeeList = false
    @State private var showingLoginSheet = false
    @State private var showingAccount = false
    @State private var partyName = ""
    @State private var passcode = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    if authManager.isAuthenticated {
                        AuthenticatedContent(
                            authManager: authManager,
                            partyManager: partyManager,
                            showingCreateParty: $showingCreateParty,
                            showingJoinParty: $showingJoinParty,
                            showingAttendeeList: $showingAttendeeList,
                            showError: $showError,
                            errorMessage: $errorMessage
                        )
                    } else {
                        UnauthenticatedContent(showingLoginSheet: $showingLoginSheet)
                    }
                }
            }
            .navigationTitle("Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {
                    showError = false
                    errorMessage = ""
                }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showingLoginSheet) {
                LoginView()
            }
            .sheet(isPresented: $showingCreateParty) {
                CreatePartySheet(
                    showingCreateParty: $showingCreateParty,
                    showingAttendeeList: $showingAttendeeList,
                    partyName: $partyName,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    isLoading: $isLoading,
                    authManager: authManager,
                    partyManager: partyManager
                )
            }
            .sheet(isPresented: $showingJoinParty) {
                JoinPartySheet(
                    showingJoinParty: $showingJoinParty,
                    showingAttendeeList: $showingAttendeeList,
                    passcode: $passcode,
                    showError: $showError,
                    errorMessage: $errorMessage,
                    isLoading: $isLoading,
                    authManager: authManager,
                    partyManager: partyManager
                )
            }
            .fullScreenCover(isPresented: $showingAttendeeList) {
                AttendeeListView()
            }
            .sheet(isPresented: $showingAccount) {
                AccountView()
            }
        }
        .environmentObject(authManager)
        .environmentObject(partyManager)
        .navigationViewStyle(.stack)
        .onAppear {
            partyManager.setAuthManager(authManager)
            authManager.setPartyManager(partyManager)
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if authManager.isAuthenticated {
                Button("Account") {
                    showingAccount = true
                }
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
            } else {
                Button("Sign In") {
                    showingLoginSheet = true
                }
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
            }
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Help") {
                if let url = URL(string: "https://wplister.replit.app/") {
                    UIApplication.shared.open(url)
                }
            }
            .foregroundColor(Theme.Colors.textPrimary(colorScheme))
        }
    }
}

// MARK: - Authenticated Content
private struct AuthenticatedContent: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var partyManager: PartyManager
    @Binding var showingCreateParty: Bool
    @Binding var showingJoinParty: Bool
    @Binding var showingAttendeeList: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: Theme.Spacing.large) {
            // Create & Join Buttons
            VStack(spacing: Theme.Spacing.medium) {
                PrimaryButton(
                    title: "Create Party",
                    action: { showingCreateParty = true }
                )
                
                SecondaryButton(
                    title: "Join Party",
                    action: { showingJoinParty = true }
                )
            }
            .padding(.horizontal)
            
            // Active Parties Section
            ActivePartiesSection(
                authManager: authManager,
                partyManager: partyManager,
                showingAttendeeList: $showingAttendeeList,
                showError: $showError,
                errorMessage: $errorMessage
            )
        }
        .padding(.vertical)
    }
}

// MARK: - Active Parties Section
private struct ActivePartiesSection: View {
    @ObservedObject var authManager: AuthManager
    @ObservedObject var partyManager: PartyManager
    @Binding var showingAttendeeList: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            Text(authManager.currentUser?.isAdmin == true ? "All Parties" : "Your Active Parties")
                .font(.headline)
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                .padding(.horizontal)
            
            ForEach(authManager.activeParties) { party in
                PartyCard(
                    name: party.name,
                    passcode: party.passcode,
                    creatorId: party.creatorId,
                    currentUserId: authManager.currentUser?.id,
                    action: {
                        partyManager.setCurrentParty(party)
                        showingAttendeeList = true
                    },
                    onDelete: {
                        try await deleteParty(party)
                    },
                    onRemove: {
                        try await removeParty(party)
                    }
                )
                .padding(.horizontal)
            }
        }
    }
    
    private func deleteParty(_ party: Party) async throws {
        do {
            // Delete from Firestore first
            try await partyManager.deleteParty(party.id)
            // Then remove from active parties
            await authManager.removePartyFromActive(party.id)
        } catch {
            print("Error deleting party:", error.localizedDescription)
            if (error as NSError).domain == "NSPOSIXErrorDomain" && (error as NSError).code == 50 {
                showError = true
                errorMessage = "Cannot delete party while offline. Please check your internet connection and try again."
                throw error
            } else {
                showError = true
                errorMessage = "Failed to delete party. Please try again."
                throw error
            }
        }
    }
    
    private func removeParty(_ party: Party) async throws {
        do {
            if let userId = authManager.currentUser?.id,
               party.editors.contains(userId) {
                try await partyManager.removeEditor(userId)
            }
            await authManager.removePartyFromActive(party.id)
        } catch {
            print("Error removing party:", error.localizedDescription)
            if (error as NSError).domain == "NSPOSIXErrorDomain" && (error as NSError).code == 50 {
                showError = true
                errorMessage = "Cannot leave party while offline. Please check your internet connection and try again."
                throw error
            } else {
                showError = true
                errorMessage = "Failed to leave party. Please try again."
                throw error
            }
        }
    }
}

// MARK: - Unauthenticated Content
private struct UnauthenticatedContent: View {
    @Binding var showingLoginSheet: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: Theme.Spacing.medium) {
            Text("Welcome to Party")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Theme.Colors.textPrimary(colorScheme))
            
            Text("Sign in to create or join parties")
                .foregroundColor(Theme.Colors.textSecondary(colorScheme))
            
            PrimaryButton(
                title: "Sign In",
                action: { showingLoginSheet = true }
            )
        }
        .padding()
    }
}

// MARK: - Create Party Sheet
private struct CreatePartySheet: View {
    @Binding var showingCreateParty: Bool
    @Binding var showingAttendeeList: Bool
    @Binding var partyName: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool
    @ObservedObject var authManager: AuthManager
    @ObservedObject var partyManager: PartyManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    AppTextField(placeholder: "Party Name", text: $partyName)
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                    }
                    
                    PrimaryButton(
                        title: "Create Party",
                        action: createParty,
                        isLoading: isLoading
                    )
                }
                .padding()
            }
            .navigationTitle("Create Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingCreateParty = false
                        partyName = ""
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
        }
    }
    
    private func createParty() {
        guard !partyName.isEmpty else {
            showError = true
            errorMessage = "Please enter a party name"
            return
        }
        
        guard let userId = authManager.currentUser?.id else {
            showError = true
            errorMessage = "You must be signed in to create a party"
            return
        }
        
        isLoading = true
        showError = false
        
        // Generate a random 6-digit passcode
        let passcode = String(format: "%06d", Int.random(in: 0...999999))
        
        Task {
            do {
                // Create party first
                try await partyManager.createParty(name: partyName, passcode: passcode, creatorId: userId)
                
                // Add to active parties if successful
                if let partyId = partyManager.currentParty?.id {
                    try await authManager.addPartyToActive(partyId)
                    
                    // Only proceed if both operations succeed
                    showingCreateParty = false
                    partyName = ""
                    showingAttendeeList = true
                }
            } catch let error as NSError {
                showError = true
                if error.domain == "NSPOSIXErrorDomain" && error.code == 50 {
                    errorMessage = "Network connection failed. Please check your internet connection and try again."
                } else if error.domain.contains("Firebase") {
                    errorMessage = "Server connection failed. Please try again."
                } else {
                    errorMessage = "Failed to create party: \(error.localizedDescription)"
                }
                print("Error creating party:", error)
            }
            isLoading = false
        }
    }
}

// MARK: - Join Party Sheet
private struct JoinPartySheet: View {
    @Binding var showingJoinParty: Bool
    @Binding var showingAttendeeList: Bool
    @Binding var passcode: String
    @Binding var showError: Bool
    @Binding var errorMessage: String
    @Binding var isLoading: Bool
    @ObservedObject var authManager: AuthManager
    @ObservedObject var partyManager: PartyManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: Theme.Spacing.large) {
                    AppTextField(placeholder: "Party Passcode", text: $passcode)
                        .keyboardType(.numberPad)
                    
                    if showError {
                        Text(errorMessage)
                            .foregroundColor(Theme.Colors.error)
                            .font(.caption)
                    }
                    
                    PrimaryButton(
                        title: "Join Party",
                        action: joinParty,
                        isLoading: isLoading
                    )
                }
                .padding()
            }
            .navigationTitle("Join Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingJoinParty = false
                        passcode = ""
                    }
                    .foregroundColor(Theme.Colors.textPrimary(colorScheme))
                }
            }
        }
    }
    
    private func joinParty() {
        guard !passcode.isEmpty else {
            showError = true
            errorMessage = "Please enter a passcode"
            return
        }
        
        isLoading = true
        showError = false
        
        Task {
            do {
                try await partyManager.joinParty(withPasscode: passcode)
                // Add the party to user's active parties
                if let partyId = partyManager.currentParty?.id {
                    try await authManager.addPartyToActive(partyId)
                }
                showingJoinParty = false
                passcode = ""
                showingAttendeeList = true
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    MainView()
} 
