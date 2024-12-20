import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var activeParties: [Party] = []
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let usersCollection = "users"
    private let partiesCollection = "party"
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
    }
    
    private func setupAuthStateListener() {
        let handle = auth.addStateDidChangeListener { [weak self] auth, user in
            guard let self = self else { return }
            
            if let user = user {
                Task { @MainActor in
                    do {
                        try await self.fetchUserData(userId: user.uid)
                    } catch {
                        print("Error fetching user data:", error.localizedDescription)
                        await self.resetState()
                    }
                }
            } else {
                Task { @MainActor in
                    await self.resetState()
                }
            }
        }
        self.authStateListener = handle
    }
    
    private func resetState() {
        self.currentUser = nil
        self.isAuthenticated = false
        self.activeParties = []
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        try await fetchUserData(userId: result.user.uid)
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = User(id: result.user.uid, email: email)
        try await saveUserData(user)
        self.currentUser = user
        self.isAuthenticated = true
    }
    
    func signOut() throws {
        try auth.signOut()
        resetState()
    }
    
    private func fetchUserData(userId: String) async throws {
        guard !userId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        let document = try await db.collection(usersCollection).document(userId).getDocument()
        
        if !document.exists {
            // Create new user document if it doesn't exist
            let user = User(id: userId, email: auth.currentUser?.email ?? "")
            try await saveUserData(user)
            self.currentUser = user
            self.isAuthenticated = true
            self.activeParties = []
            return
        }
        
        guard let data = document.data(),
              let user = try? Firestore.Decoder().decode(User.self, from: data) else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user data"])
        }
        
        self.currentUser = user
        self.isAuthenticated = true
        
        // If user is admin, fetch all parties
        if user.isAdmin {
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    parties.append(party)
                }
            }
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        }
        // Otherwise, fetch only active parties
        else if !user.activeParties.isEmpty {
            var parties: [Party] = []
            for partyId in user.activeParties {
                if let party = try? await fetchParty(partyId: partyId) {
                    parties.append(party)
                }
            }
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            self.activeParties = []
        }
    }
    
    private func fetchParty(partyId: String) async throws -> Party {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        let document = try await db.collection(partiesCollection).document(partyId).getDocument()
        guard let data = document.data(),
              let name = data["name"] as? String,
              let passcode = data["passcode"] as? String else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party data"])
        }
        
        let creatorId = data["creatorId"] as? String ?? ""
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
        
        let people = (data["people"] as? [[String: Any]] ?? []).compactMap { personData -> Attendee? in
            guard let id = personData["id"] as? String,
                  let firstName = personData["firstName"] as? String,
                  let lastName = personData["lastName"] as? String,
                  let isPresent = personData["isPresent"] as? Bool,
                  let createdAt = (personData["createdAt"] as? Timestamp)?.dateValue(),
                  let updatedAt = (personData["updatedAt"] as? Timestamp)?.dateValue(),
                  let addMethod = personData["addMethod"] as? String
            else { return nil }
            
            return Attendee(
                id: id,
                firstName: firstName,
                lastName: lastName,
                isPresent: isPresent,
                createdAt: createdAt,
                updatedAt: updatedAt,
                addMethod: addMethod
            )
        }
        
        return Party(
            id: document.documentID,
            name: name,
            passcode: passcode,
            creatorId: creatorId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attendees: people
        )
    }
    
    private func saveUserData(_ user: User) async throws {
        guard !user.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid user ID"])
        }
        
        let data = try Firestore.Encoder().encode(user)
        try await db.collection(usersCollection).document(user.id).setData(data)
    }
    
    func addPartyToActive(_ partyId: String) async throws {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        guard var user = currentUser else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // If admin, refresh all parties
        if user.isAdmin {
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    parties.append(party)
                }
            }
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
            return
        }
        
        // For regular users, add to active parties
        if !user.activeParties.contains(partyId) {
            user.activeParties.append(partyId)
            try await saveUserData(user)
            self.currentUser = user
            
            if let party = try? await fetchParty(partyId: partyId) {
                self.activeParties.append(party)
                self.activeParties.sort { $0.updatedAt > $1.updatedAt }
            }
        }
    }
    
    func removePartyFromActive(_ partyId: String) {
        self.activeParties.removeAll { $0.id == partyId }
        
        // Also remove from user's active parties if not admin
        if let user = currentUser, !user.isAdmin {
            Task {
                var updatedUser = user
                updatedUser.activeParties.removeAll { $0 == partyId }
                try? await saveUserData(updatedUser)
                self.currentUser = updatedUser
            }
        }
    }
} 