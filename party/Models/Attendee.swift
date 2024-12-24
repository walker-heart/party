import Foundation
import FirebaseFirestore

struct Attendee: Identifiable, Codable, Sendable {
    let id: String
    let firstName: String
    let lastName: String
    var isPresent: Bool
    let createdAt: Date
    var updatedAt: Date
    let addMethod: String
    var updatedBy: String?
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
    
    init(id: String = UUID().uuidString, 
         firstName: String,
         lastName: String,
         isPresent: Bool = false,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         addMethod: String = "appAdd",
         updatedBy: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.isPresent = isPresent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.addMethod = addMethod
        self.updatedBy = updatedBy
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case firstName
        case lastName
        case isPresent
        case createdAt
        case updatedAt
        case addMethod
        case updatedBy
    }
} 