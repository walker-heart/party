import SwiftUI

struct MainView: View {
    @EnvironmentObject private var partyManager: PartyManager
    @EnvironmentObject private var authManager: AuthManager
    @State private var passcode = ""
    @State private var partyName = ""
    @State private var showingCreateParty = false
    @State private var showingAttendeeList = false
    @State private var showingLogin = false
    @State private var showingError = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Text("Party")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                VStack(spacing: 20) {
                    if authManager.isAuthenticated {
                        Button(action: { showingCreateParty = true }) {
                            Text("Create Party")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                    } else {
                        Button(action: { showingLogin = true }) {
                            Text("Sign in to create party")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.gray)
                                .cornerRadius(10)
                        }
                    }
                    
                    Text("OR")
                        .foregroundColor(.gray)
                    
                    VStack(spacing: 15) {
                        SecureField("Enter Passcode", text: $passcode)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                        
                        Button(action: joinParty) {
                            Text("Join Party")
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.green)
                                .cornerRadius(10)
                        }
                        .disabled(passcode.isEmpty)
                    }
                }
                .padding(.horizontal, 50)
                
                if authManager.isAuthenticated {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(authManager.currentUser?.isAdmin == true ? "All Parties" : "Your Active Parties")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if authManager.activeParties.isEmpty {
                            Text("No parties")
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                        } else {
                            List(authManager.activeParties) { party in
                                Button(action: {
                                    partyManager.setCurrentParty(party)
                                    showingAttendeeList = true
                                }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(party.name)
                                                .font(.headline)
                                            HStack {
                                                Text("Passcode: \(party.passcode)")
                                                Spacer()
                                                Text("Here: \(party.attendees.filter(\.isPresent).count)")
                                                    .foregroundColor(.green)
                                                Text("Away: \(party.attendees.filter { !$0.isPresent }.count)")
                                                    .foregroundColor(.red)
                                            }
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                        }
                                        Spacer()
                                        if authManager.currentUser?.isAdmin == true ||
                                           authManager.currentUser?.id == party.creatorId {
                                            Button(action: {
                                                Task {
                                                    do {
                                                        try await partyManager.deleteParty(party.id)
                                                        authManager.removePartyFromActive(party.id)
                                                    } catch {
                                                        errorMessage = error.localizedDescription
                                                        showingError = true
                                                    }
                                                }
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .padding(.trailing, 8)
                                        }
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.gray)
                                    }
                                }
                                .foregroundColor(.primary)
                            }
                            .listStyle(PlainListStyle())
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showingAttendeeList) {
                AttendeeListView()
            }
            .sheet(isPresented: $showingCreateParty) {
                NavigationView {
                    Form {
                        Section(header: Text("Party Information")) {
                            TextField("Party Name", text: $partyName)
                                .textInputAutocapitalization(.words)
                        }
                    }
                    .navigationTitle("Create Party")
                    .navigationBarItems(
                        leading: Button("Cancel") {
                            showingCreateParty = false
                            partyName = ""
                        },
                        trailing: Button("Create") {
                            createParty()
                        }
                        .disabled(partyName.isEmpty)
                    )
                }
            }
            .sheet(isPresented: $showingLogin) {
                LoginView(authManager: authManager)
            }
            .alert("Error", isPresented: $showingError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { error in
                Text(error)
            }
            .toolbar {
                if authManager.isAuthenticated {
                    Button(action: {
                        try? authManager.signOut()
                    }) {
                        HStack {
                            Text(authManager.currentUser?.email ?? "")
                                .foregroundColor(.primary)
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } else {
                    Button(action: { showingLogin = true }) {
                        Image(systemName: "person.circle")
                    }
                }
            }
        }
    }
    
    private func createParty() {
        Task {
            do {
                guard let userId = authManager.currentUser?.id else {
                    showingLogin = true
                    return
                }
                let randomPasscode = String(format: "%06d", Int.random(in: 0...999999))
                try await partyManager.createParty(name: partyName, passcode: randomPasscode, creatorId: userId)
                
                if let partyId = partyManager.currentParty?.id {
                    try await authManager.addPartyToActive(partyId)
                }
                
                showingCreateParty = false
                showingAttendeeList = true
                partyName = ""
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func joinParty() {
        Task {
            do {
                try await partyManager.joinParty(withPasscode: passcode)
                if authManager.isAuthenticated {
                    try await authManager.addPartyToActive(partyManager.currentParty?.id ?? "")
                }
                showingAttendeeList = true
                resetFields()
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
    
    private func resetFields() {
        partyName = ""
        passcode = ""
    }
}

#Preview {
    MainView()
        .environmentObject(PartyManager.preview)
        .environmentObject(AuthManager())
} 