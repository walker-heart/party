import Foundation
import FirebaseFirestore

struct User: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let isAdmin: Bool
    var activeParties: [String] // Array of party IDs
    
    init(id: String = UUID().uuidString,
         email: String,
         firstName: String = "",
         lastName: String = "",
         isAdmin: Bool = false,
         activeParties: [String] = []) {
        self.id = id
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.isAdmin = isAdmin
        self.activeParties = activeParties
    }
} 