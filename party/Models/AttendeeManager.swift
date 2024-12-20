import SwiftUI
import FirebaseCore
import FirebaseFirestore

@MainActor
final class PartyManager: ObservableObject {
    @Published private(set) var currentParty: Party?
    private let db: Firestore
    private let collectionName = "party"
    private var listenerRegistration: ListenerRegistration?
    
    init(db: Firestore = Firestore.firestore(), previewParty: Party? = nil) {
        self.db = db
        self.currentParty = previewParty
    }
    
    static var preview: PartyManager {
        PartyManager(
            db: Firestore.firestore(),
            previewParty: Party(
                id: "preview-id",
                name: "Preview Party",
                passcode: "1234",
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
    
    private enum SendableFirestoreValue: Sendable {
        case string(String)
        case bool(Bool)
        case timestamp(Date)
        case serverTimestamp
        case array([SendableFirestoreValue])
        case dictionary([String: SendableFirestoreValue])
        
        var firestoreValue: Any {
            switch self {
            case .string(let str): return str
            case .bool(let bool): return bool
            case .timestamp(let date): return Timestamp(date: date)
            case .serverTimestamp: return FieldValue.serverTimestamp()
            case .array(let array): return array.map { $0.firestoreValue }
            case .dictionary(let dict): return dict.mapValues { $0.firestoreValue }
            }
        }
    }
    
    private struct FirestorePartyData: Sendable {
        let id: String
        let name: String
        let passcode: String
        let people: [FirestoreAttendeeData]
        let createdAt: Date?
        let updatedAt: Date?
        let creatorId: String
        
        var firestoreData: SendableFirestoreValue {
            .dictionary([
                "id": .string(id),
                "name": .string(name),
                "passcode": .string(passcode),
                "people": .array(people.map { $0.firestoreData }),
                "createdAt": createdAt.map { .timestamp($0) } ?? .serverTimestamp,
                "updatedAt": updatedAt.map { .timestamp($0) } ?? .serverTimestamp,
                "creatorId": .string(creatorId)
            ])
        }
    }
    
    private struct FirestoreAttendeeData: Sendable {
        let id: String
        let firstName: String
        let lastName: String
        let isPresent: Bool
        let createdAt: Date
        let updatedAt: Date
        let addMethod: String
        
        var firestoreData: SendableFirestoreValue {
            .dictionary([
                "id": .string(id),
                "firstName": .string(firstName),
                "lastName": .string(lastName),
                "isPresent": .bool(isPresent),
                "createdAt": .timestamp(createdAt),
                "updatedAt": .timestamp(updatedAt),
                "addMethod": .string(addMethod)
            ])
        }
        
        init(from attendee: Attendee) {
            self.id = attendee.id
            self.firstName = attendee.firstName
            self.lastName = attendee.lastName
            self.isPresent = attendee.isPresent
            self.createdAt = attendee.createdAt
            self.updatedAt = attendee.updatedAt
            self.addMethod = attendee.addMethod
        }
    }
    
    func createParty(name: String, passcode: String, creatorId: String) async throws {
        let party = Party(name: name, passcode: passcode, creatorId: creatorId)
        guard !party.id.isEmpty else {
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid party ID"])
        }
        
        let partyData = FirestorePartyData(
            id: party.id,
            name: name,
            passcode: passcode,
            people: [],
            createdAt: nil,
            updatedAt: nil,
            creatorId: creatorId
        )
        
        let documentRef = db.collection(collectionName).document(party.id)
        try await documentRef.setData(partyData.firestoreData.firestoreValue as! [String: Any])
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
        
        let attendeeData = FirestoreAttendeeData(from: attendee)
        let documentRef = db.collection(collectionName).document(party.id)
        
        try await documentRef.updateData([
            "people": FieldValue.arrayUnion([attendeeData.firestoreData.firestoreValue as! [String: Any]]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
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
            
            try await documentRef.updateData([
                "people": people,
                "updatedAt": FieldValue.serverTimestamp()
            ])
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
        
        try await documentRef.updateData([
            "people": people,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
    
    private func parseAttendee(from data: [String: Any]) -> Attendee? {
        guard let id = data["id"] as? String,
              let firstName = data["firstName"] as? String,
              let lastName = data["lastName"] as? String,
              let isPresent = data["isPresent"] as? Bool,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
              let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
              let addMethod = data["addMethod"] as? String
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
    
    private func listenToParty(id: String) {
        guard !id.isEmpty else { return }
        
        listenerRegistration?.remove()
        
        let documentRef = db.collection(collectionName).document(id)
        listenerRegistration = documentRef.addSnapshotListener { [weak self] documentSnapshot, error in
            guard let self = self,
                  let document = documentSnapshot,
                  let data = document.data() else {
                print("Error listening to party:", error?.localizedDescription ?? "Unknown error")
                return
            }
            
            let attendees = (data["people"] as? [[String: Any]] ?? [])
                .compactMap { self.parseAttendee(from: $0) }
            
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
            
            self.currentParty = Party(
                id: document.documentID,
                name: data["name"] as? String ?? "",
                passcode: data["passcode"] as? String ?? "",
                creatorId: data["creatorId"] as? String ?? "",
                createdAt: createdAt,
                updatedAt: updatedAt,
                attendees: attendees
            )
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
} 
