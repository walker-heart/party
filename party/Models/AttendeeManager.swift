import SwiftUI
import FirebaseCore
import FirebaseFirestore

@MainActor
final class PartyManager: ObservableObject {
    @Published private(set) var currentParty: Party?
    private let db: Firestore
    private let collectionName: String
    private var listenerRegistration: ListenerRegistration?
    private weak var authManager: AuthManager?
    
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
        
        static func fromAttendee(_ attendee: Attendee) -> FirestoreValue {
            var dict: [String: FirestoreValue] = [
                "id": .string(attendee.id),
                "firstName": .string(attendee.firstName),
                "lastName": .string(attendee.lastName),
                "isPresent": .bool(attendee.isPresent),
                "createdAt": .timestamp(attendee.createdAt),
                "updatedAt": .timestamp(attendee.updatedAt),
                "addMethod": .string(attendee.addMethod)
            ]
            
            if let updatedBy = attendee.updatedBy {
                dict["updatedBy"] = .string(updatedBy)
            }
            
            return .dictionary(dict)
        }
    }
    
    init(db: Firestore = Firestore.firestore(), previewParty: Party? = nil) {
        self.db = db
        self.collectionName = "party"
        self.currentParty = previewParty
    }
    
    static var preview: PartyManager {
        PartyManager(
            db: Firestore.firestore(),
            previewParty: Party(
                id: "preview-id",
                name: "Preview Party",
                passcode: "1234",
                creatorId: "preview-creator",
                attendees: [
                    Attendee(firstName: "John", lastName: "Doe", isPresent: true, addMethod: "appAdd"),
                    Attendee(firstName: "Jane", lastName: "Smith", isPresent: false, addMethod: "appAdd")
                ]
            )
        )
    }
    
    deinit {
        listenerRegistration?.remove()
    }
    
    func setCurrentParty(_ party: Party) {
        guard !party.id.isEmpty else { return }
        self.currentParty = party
        listenToParty(id: party.id)
    }
    
    func setAuthManager(_ authManager: AuthManager) {
        self.authManager = authManager
    }
    
    func addAttendee(firstName: String, lastName: String) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        let attendee = Attendee(
            id: UUID().uuidString,
            firstName: firstName,
            lastName: lastName,
            isPresent: false,
            createdAt: Date(),
            updatedAt: Date(),
            addMethod: "appAdd"
        )
        
        let attendeeData = FirestoreValue.fromAttendee(attendee)
        let documentRef = db.collection(collectionName).document(party.id)
        
        let updateData: [String: Any] = [
            "people": FieldValue.arrayUnion([attendeeData.firestoreValue]),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        
        try await documentRef.updateData(updateData)
        
        // Refresh the party in AuthManager
        if let authManager = authManager {
            try await authManager.refreshParty(party.id)
        }
    }
    
    func updateAttendanceStatus(for attendeeId: String, isPresent: Bool) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        let documentRef = db.collection(collectionName).document(party.id)
        let document = try await documentRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        var people = data["people"] as? [[String: Any]] ?? []
        if let index = people.firstIndex(where: { ($0["id"] as? String) == attendeeId }) {
            people[index]["isPresent"] = isPresent
            people[index]["updatedAt"] = Timestamp(date: Date())
            people[index]["updatedBy"] = authManager?.currentUser?.id
            
            let updateData: [String: Any] = [
                "people": people,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await documentRef.updateData(updateData)
            
            // Refresh the party in AuthManager
            if let authManager = authManager {
                try await authManager.refreshParty(party.id)
            }
        }
    }
    
    func removeAttendee(_ attendeeId: String) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        let documentRef = db.collection(collectionName).document(party.id)
        let document = try await documentRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        var people = data["people"] as? [[String: Any]] ?? []
        people.removeAll { ($0["id"] as? String) == attendeeId }
        
        let updateData: [String: Any] = [
            "people": people,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await documentRef.updateData(updateData)
        
        // Refresh the party in AuthManager
        if let authManager = authManager {
            try await authManager.refreshParty(party.id)
        }
    }
    
    func removeListener(for partyId: String) {
        if currentParty?.id == partyId {
            listenerRegistration?.remove()
            listenerRegistration = nil
        }
    }
    
    func listenToParty(id: String) {
        guard !id.isEmpty else { return }
        
        listenerRegistration?.remove()
        
        let documentRef = db.collection(collectionName).document(id)
        listenerRegistration = documentRef.addSnapshotListener { [weak self] documentSnapshot, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                guard let document = documentSnapshot,
                      document.exists,
                      let data = document.data() else {
                    return
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
                
                let party = Party(
                    id: document.documentID,
                    name: name,
                    passcode: passcode,
                    creatorId: creatorId,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    attendees: people,
                    editors: editors
                )
                
                self.currentParty = party
                
                // Notify AuthManager of the update
                if let authManager = self.authManager {
                    authManager.refreshParty(party)
                }
            }
        }
    }
    
    func searchAttendees(query: String) -> [Attendee] {
        guard let attendees = currentParty?.attendees else { return [] }
        
        if query.isEmpty {
            return attendees.sorted { $0.lastName < $1.lastName }
        }
        return attendees
            .filter { 
                $0.firstName.lowercased().contains(query.lowercased()) ||
                $0.lastName.lowercased().contains(query.lowercased()) ||
                $0.fullName.lowercased().contains(query.lowercased())
            }
            .sorted { $0.lastName < $1.lastName }
    }
    
    func deleteParty(_ partyId: String) async throws {
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        do {
            let documentRef = db.collection(collectionName).document(partyId)
            try await documentRef.delete()
            
            // If this was the current party, clear it
            if currentParty?.id == partyId {
                currentParty = nil
            }
        } catch let error as NSError {
            // Handle network errors specifically
            if error.domain == "NSPOSIXErrorDomain" && error.code == 50 {
                throw NSError(
                    domain: "PartyManagerError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot delete party while offline. Please check your internet connection and try again."]
                )
            }
            // For other errors, throw a generic message
            throw NSError(
                domain: "PartyManagerError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete party. Please try again."]
            )
        }
    }
    
    func createParty(name: String, passcode: String, creatorId: String) async throws {
        let party = Party(name: name, passcode: passcode, creatorId: creatorId, editors: [creatorId])
        guard !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        let partyData = FirestoreValue.dictionary([
            "id": .string(party.id),
            "name": .string(name),
            "passcode": .string(passcode),
            "people": .array([]),
            "createdAt": .serverTimestamp,
            "updatedAt": .serverTimestamp,
            "creatorId": .string(creatorId),
            "editors": .array([.string(creatorId)])
        ])
        
        let documentRef = db.collection(collectionName).document(party.id)
        try await documentRef.setData(partyData.firestoreValue as! [String: Any])
        
        // Add the party to the creator's active parties
        if let authManager = authManager {
            try await authManager.addPartyToActive(party.id)
        }
        
        self.currentParty = party
        listenToParty(id: party.id)
    }
    
    func joinParty(withPasscode passcode: String) async throws {
        guard !passcode.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Passcode cannot be empty"])
        }
        
        let snapshot = try await db.collection(collectionName)
            .whereField("passcode", isEqualTo: passcode)
            .getDocuments()
        
        guard let document = snapshot.documents.first else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party not found"])
        }
        
        let partyId = document.documentID
        guard !partyId.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        // Add the party to the user's active parties
        if let authManager = authManager {
            try await authManager.addPartyToActive(partyId)
        }
        
        listenToParty(id: partyId)
    }
    
    func updateAttendeeName(attendeeId: String, firstName: String, lastName: String) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        let documentRef = db.collection(collectionName).document(party.id)
        let document = try await documentRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        var people = data["people"] as? [[String: Any]] ?? []
        if let index = people.firstIndex(where: { ($0["id"] as? String) == attendeeId }) {
            people[index]["firstName"] = firstName
            people[index]["lastName"] = lastName
            people[index]["updatedAt"] = Timestamp(date: Date())
            people[index]["updatedBy"] = authManager?.currentUser?.id
            
            let updateData: [String: Any] = [
                "people": people,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await documentRef.updateData(updateData)
            
            // Refresh the party in AuthManager
            if let authManager = authManager {
                try await authManager.refreshParty(party.id)
            }
        }
    }
    
    func addEditor(_ userId: String) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        let documentRef = db.collection(collectionName).document(party.id)
        let document = try await documentRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        var editors = data["editors"] as? [String] ?? [party.creatorId]
        if !editors.contains(userId) {
            editors.append(userId)
            
            let updateData: [String: Any] = [
                "editors": editors,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            try await documentRef.updateData(updateData)
            
            // Add party to the new editor's active parties
            if let authManager = authManager {
                try await authManager.addPartyToActive(party.id)
                
                // Refresh the party to update the UI
                try await authManager.refreshParty(party.id)
            }
        }
    }
    
    func removeEditor(_ userId: String) async throws {
        guard let party = currentParty, !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active party"])
        }
        
        // Don't allow removing the creator
        guard userId != party.creatorId else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot remove the party creator"])
        }
        
        let documentRef = db.collection(collectionName).document(party.id)
        let document = try await documentRef.getDocument()
        
        guard let data = document.data() else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Party data not found"])
        }
        
        var editors = data["editors"] as? [String] ?? [party.creatorId]
        editors.removeAll { $0 == userId }
        
        let updateData: [String: Any] = [
            "editors": editors,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        try await documentRef.updateData(updateData)
        
        // Remove party from the editor's active parties
        if let authManager = authManager {
            await authManager.removePartyFromActive(party.id)
        }
    }
}
