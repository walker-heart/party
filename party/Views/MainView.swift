import SwiftUI

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
                // Background
                Theme.Colors.background(colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: Theme.Spacing.large) {
                        if authManager.isAuthenticated {
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
                                            Task {
                                                do {
                                                    try await partyManager.deleteParty(party.id)
                                                    await authManager.removePartyFromActive(party.id)
                                                } catch {
                                                    print("Error deleting party:", error.localizedDescription)
                                                }
                                            }
                                        },
                                        onRemove: {
                                            Task {
                                                do {
                                                    if let userId = authManager.currentUser?.id,
                                                       party.editors.contains(userId) {
                                                        try await partyManager.removeEditor(userId)
                                                    }
                                                    await authManager.removePartyFromActive(party.id)
                                                } catch {
                                                    print("Error removing party:", error.localizedDescription)
                                                }
                                            }
                                        }
                                    )
                                    .padding(.horizontal)
                                }
                            }
                        } else {
                            // Login prompt
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
                    .padding(.vertical)
                }
            }
            .navigationTitle("Party")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
            }
            .sheet(isPresented: $showingLoginSheet) {
                LoginView()
            }
            .sheet(isPresented: $showingCreateParty) {
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
            .sheet(isPresented: $showingJoinParty) {
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
            .fullScreenCover(isPresented: $showingAttendeeList) {
                AttendeeListView()
            }
            .sheet(isPresented: $showingAccount) {
                AccountView()
            }
        }
        .environmentObject(authManager)
        .environmentObject(partyManager)
        .onAppear {
            partyManager.setAuthManager(authManager)
            authManager.setPartyManager(partyManager)
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
                try await partyManager.createParty(name: partyName, passcode: passcode, creatorId: userId)
                // Add the party to user's active parties
                if let partyId = partyManager.currentParty?.id {
                    try await authManager.addPartyToActive(partyId)
                }
                showingCreateParty = false
                partyName = ""
                showingAttendeeList = true
            } catch {
                showError = true
                errorMessage = error.localizedDescription
            }
            isLoading = false
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
