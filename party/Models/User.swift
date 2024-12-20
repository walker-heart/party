import Foundation
import FirebaseFirestore

struct User: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let isAdmin: Bool
    var activeParties: [String] // Array of party IDs
    
    init(id: String = UUID().uuidString,
         email: String,
         isAdmin: Bool = false,
         activeParties: [String] = []) {
        self.id = id
        self.email = email
        self.isAdmin = isAdmin
        self.activeParties = activeParties
    }
} 