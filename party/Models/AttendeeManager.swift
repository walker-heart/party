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
            .dictionary([
                "id": .string(attendee.id),
                "firstName": .string(attendee.firstName),
                "lastName": .string(attendee.lastName),
                "isPresent": .bool(attendee.isPresent),
                "createdAt": .timestamp(attendee.createdAt),
                "updatedAt": .timestamp(attendee.updatedAt),
                "addMethod": .string(attendee.addMethod)
            ])
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
    
    private func listenToParty(id: String) {
        guard !id.isEmpty else { return }
        
        listenerRegistration?.remove()
        
        let documentRef = db.collection(collectionName).document(id)
        listenerRegistration = documentRef.addSnapshotListener { [weak self] documentSnapshot, error in
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
                
                // Process attendees using FirestoreValue
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
                
                // Create the party object
                let updatedParty = Party(
                    id: document.documentID,
                    name: name,
                    passcode: passcode,
                    creatorId: creatorId,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    attendees: attendees
                )
                
                // Update the current party on the main actor
                self.currentParty = updatedParty
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
        
        let documentRef = db.collection(collectionName).document(partyId)
        try await documentRef.delete()
        
        // If this was the current party, clear it
        if currentParty?.id == partyId {
            currentParty = nil
        }
    }
    
    func createParty(name: String, passcode: String, creatorId: String) async throws {
        let party = Party(name: name, passcode: passcode, creatorId: creatorId)
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
            "creatorId": .string(creatorId)
        ])
        
        let documentRef = db.collection(collectionName).document(party.id)
        try await documentRef.setData(partyData.firestoreValue as! [String: Any])
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
        
        listenToParty(id: partyId)
    }
}
