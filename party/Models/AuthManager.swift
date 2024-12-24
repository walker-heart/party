import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var activeParties: [Party] = []
    
    private let auth: Auth
    private let db: Firestore
    private let usersCollection = "users"
    private let partiesCollection = "party"
    private var partyManager: PartyManager?
    
    init(auth: Auth = Auth.auth(), db: Firestore = Firestore.firestore()) {
        self.auth = auth
        self.db = db
        
        // Set up auth state listener
        _ = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                if let user = user {
                    do {
                        try await self?.fetchUserData(userId: user.uid)
                    } catch {
                        print("Error fetching user data:", error.localizedDescription)
                        self?.resetState()
                    }
                } else {
                    self?.removeAllPartyListeners()
                    self?.resetState()
                }
            }
        }
    }
    
    func setPartyManager(_ partyManager: PartyManager) {
        self.partyManager = partyManager
    }
    
    private func removeAllPartyListeners() {
        for party in activeParties {
            partyManager?.removeListener(for: party.id)
        }
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
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "User data not found"])
        }
        
        // Create user from raw data to handle missing fields
        let user = User(
            id: userId,
            email: data["email"] as? String ?? auth.currentUser?.email ?? "",
            firstName: data["firstName"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            isAdmin: data["isAdmin"] as? Bool ?? false,
            activeParties: data["activeParties"] as? [String] ?? []
        )
        
        // Update user data to ensure it has all fields
        try await saveUserData(user)
        
        self.currentUser = user
        self.isAuthenticated = true
        
        // Remove existing listeners
        removeAllPartyListeners()
        
        // If user is admin, fetch all parties, otherwise fetch active parties
        if user.isAdmin {
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    parties.append(party)
                    partyManager?.listenToParty(id: party.id)
                }
            }
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            // Get all parties from Firestore
            let snapshot = try await db.collection(partiesCollection).getDocuments()
            var parties: [Party] = []
            
            // Get current date and date 3 days ago
            let currentDate = Date()
            let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: currentDate) ?? currentDate
            
            for document in snapshot.documents {
                if let party = try? await fetchParty(partyId: document.documentID) {
                    // Include party if:
                    // 1. User is an editor
                    // 2. Party was joined in the last 3 days
                    if party.editors.contains(user.id) || 
                       (party.updatedAt >= threeDaysAgo && user.activeParties.contains(party.id)) {
                        parties.append(party)
                        partyManager?.listenToParty(id: party.id)
                    }
                }
            }
            
            // Sort by most recently updated
            self.activeParties = parties.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
    
    private func resetState() {
        self.currentUser = nil
        self.isAuthenticated = false
        self.activeParties = []
    }
    
    func signOut() async throws {
        try auth.signOut()
        removeAllPartyListeners()
        resetState()
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await auth.signIn(withEmail: email, password: password)
        try await fetchUserData(userId: result.user.uid)
    }
    
    func signUp(email: String, password: String, firstName: String = "", lastName: String = "") async throws {
        let result = try await auth.createUser(withEmail: email, password: password)
        let user = User(
            id: result.user.uid,
            email: email,
            firstName: firstName,
            lastName: lastName
        )
        try await saveUserData(user)
        self.currentUser = user
        self.isAuthenticated = true
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
        
        if !user.activeParties.contains(partyId) {
            user.activeParties.append(partyId)
            try await saveUserData(user)
            self.currentUser = user
            
            if let party = try? await fetchParty(partyId: partyId) {
                if !activeParties.contains(where: { $0.id == partyId }) {
                    activeParties.append(party)
                    activeParties.sort { $0.updatedAt > $1.updatedAt }
                }
            }
        }
    }
    
    func removePartyFromActive(_ partyId: String) async {
        activeParties.removeAll { $0.id == partyId }
        
        if let user = currentUser, !user.isAdmin {
            var updatedUser = user
            updatedUser.activeParties.removeAll { $0 == partyId }
            do {
                try await saveUserData(updatedUser)
                self.currentUser = updatedUser
            } catch {
                print("Error updating user data:", error.localizedDescription)
            }
        }
    }
    
    func fetchParty(partyId: String) async throws -> Party {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        let document = try await db.collection(partiesCollection).document(partyId).getDocument()
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        let name = data["name"] as? String ?? ""
        let passcode = data["passcode"] as? String ?? ""
        let creatorId = data["creatorId"] as? String ?? ""
        let editors = data["editors"] as? [String] ?? [creatorId]
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
            
            let updatedBy = personData["updatedBy"] as? String
            
            return Attendee(
                id: id,
                firstName: firstName,
                lastName: lastName,
                isPresent: isPresent,
                createdAt: createdAt,
                updatedAt: updatedAt,
                addMethod: addMethod,
                updatedBy: updatedBy
            )
        }
        
        return Party(
            id: document.documentID,
            name: name,
            passcode: passcode,
            creatorId: creatorId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attendees: people,
            editors: editors
        )
    }
    
    func getUserIdByEmail(_ email: String) async throws -> String? {
        let snapshot = try await db.collection(usersCollection)
            .whereField("email", isEqualTo: email)
            .getDocuments()
        
        return snapshot.documents.first?.documentID
    }
    
    func getUserById(_ userId: String) async throws -> User? {
        guard !userId.isEmpty else { return nil }
        
        let document = try await db.collection(usersCollection).document(userId).getDocument()
        guard let data = document.data() else { return nil }
        
        return User(
            id: userId,
            email: data["email"] as? String ?? "",
            firstName: data["firstName"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            isAdmin: data["isAdmin"] as? Bool ?? false,
            activeParties: data["activeParties"] as? [String] ?? []
        )
    }
    
    func refreshParty(_ partyId: String) async throws {
        let party = try await fetchParty(partyId: partyId)
        refreshParty(party)
    }
    
    func refreshParty(_ party: Party?) {
        guard let party = party else { return }
        if let index = activeParties.firstIndex(where: { $0.id == party.id }) {
            activeParties[index] = party
            // Sort by most recently updated
            activeParties.sort { $0.updatedAt > $1.updatedAt }
        }
    }
}