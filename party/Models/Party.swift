import Foundation

struct Party: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let passcode: String
    let creatorId: String
    let createdAt: Date
    let updatedAt: Date
    let attendees: [Attendee]
    let editors: [String]  // Array of user IDs who can edit the party
    
    init(id: String = UUID().uuidString,
         name: String,
         passcode: String,
         creatorId: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         attendees: [Attendee] = [],
         editors: [String] = []) {
        self.id = id
        self.name = name
        self.passcode = passcode
        self.creatorId = creatorId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attendees = attendees
        self.editors = editors.isEmpty ? [creatorId] : editors  // Always include creator
    }
}