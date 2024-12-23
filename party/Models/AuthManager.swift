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
    private let usersCollection: String
    private let partiesCollection: String
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var partyListeners: [String: ListenerRegistration]
    
    private enum FirestoreValue: Sendable {
        case string(String)
        case bool(Bool)
        case timestamp(Date)
        case serverTimestamp
        case array([FirestoreValue])
        case dictionary([String: FirestoreValue])
        
        var firestoreValue: Any {
            switch self {
            case .string(let str): return str
            case .bool(let bool): return bool
            case .timestamp(let date): return Timestamp(date: date)
            case .serverTimestamp: return FieldValue.serverTimestamp()
            case .array(let array): return array.map(\.firestoreValue)
            case .dictionary(let dict): return dict.mapValues(\.firestoreValue)
            }
        }
    }
    
    init(auth: Auth = Auth.auth(), 
         db: Firestore = Firestore.firestore()) {
        self.auth = auth
        self.db = db
        self.usersCollection = "users"
        self.partiesCollection = "party"
        self.partyListeners = [:]
        setupAuthStateListener()
    }
    
    deinit {
        if let listener = authStateListener {
            auth.removeStateDidChangeListener(listener)
        }
        for listener in partyListeners.values {
            listener.remove()
        }
        partyListeners.removeAll()
    }
    
    private func removeAllPartyListeners() {
        for listener in partyListeners.values {
            listener.remove()
        }
        partyListeners.removeAll()
    }
    
    private func listenToParty(_ partyId: String) {
        // Remove existing listener if any
        partyListeners[partyId]?.remove()
        
        // Set up new listener
        let listener = db.collection(partiesCollection).document(partyId)
            .addSnapshotListener { [weak self] documentSnapshot, error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    guard let document = documentSnapshot,
                          let data = document.data() else {
                        print("Error listening to party:", error?.localizedDescription ?? "Unknown error")
                        return
                    }
                    
                    // Create local copies of data to avoid capturing state
                    let peopleData = data["people"] as? [[String: Any]] ?? []
                    let name = data["name"] as? String ?? ""
                    let passcode = data["passcode"] as? String ?? ""
                    let creatorId = data["creatorId"] as? String ?? ""
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
                    
                    // Process attendees
                    let attendees = peopleData.compactMap { attendeeData -> Attendee? in
                        guard let id = attendeeData["id"] as? String,
                              let firstName = attendeeData["firstName"] as? String,
                              let lastName = attendeeData["lastName"] as? String,
                              let isPresent = attendeeData["isPresent"] as? Bool,
                              let createdAt = (attendeeData["createdAt"] as? Timestamp)?.dateValue(),
                              let updatedAt = (attendeeData["updatedAt"] as? Timestamp)?.dateValue(),
                              let addMethod = attendeeData["addMethod"] as? String
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
                    
                    // Create and update party
                    let updatedParty = Party(
                        id: document.documentID,
                        name: name,
                        passcode: passcode,
                        creatorId: creatorId,
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        attendees: attendees
                    )
                    
                    // Update active parties
                    if let index = self.activeParties.firstIndex(where: { $0.id == partyId }) {
                        self.activeParties[index] = updatedParty
                        self.activeParties.sort { $0.updatedAt > $1.updatedAt }
                    }
                }
            }
        
        partyListeners[partyId] = listener
    }
    
    private func setupAuthStateListener() {
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            Task { @MainActor in
                if let user = user {
                    do {
                        try await self.fetchUserData(userId: user.uid)
                    } catch {
                        print("Error fetching user data:", error.localizedDescription)
                        self.resetState()
                    }
                } else {
                    self.removeAllPartyListeners()
                    self.resetState()
                }
            }
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
    
    func refreshParty(_ partyId: String) async throws {
        guard !partyId.isEmpty else { return }
        
        if let party = try? await fetchParty(partyId: partyId) {
            if let index = activeParties.firstIndex(where: { $0.id == partyId }) {
                activeParties[index] = party
                activeParties.sort { $0.updatedAt > $1.updatedAt }
            }
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
            for party in parties {
                listenToParty(party.id)
            }
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
            for party in parties {
                listenToParty(party.id)
            }
        } else {
            self.activeParties = []
        }
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
            for party in parties {
                listenToParty(party.id)
            }
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
                listenToParty(party.id)
            }
        }
    }
    
    func removePartyFromActive(_ partyId: String) async {
        // Remove from active parties
        activeParties.removeAll { $0.id == partyId }
        
        // Remove listener
        partyListeners[partyId]?.remove()
        partyListeners.removeValue(forKey: partyId)
        
        // Also remove from user's active parties if not admin
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
}