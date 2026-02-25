import Foundation

struct User: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var phoneNumber: String

    init(id: String = UUID().uuidString, name: String, phoneNumber: String) {
        self.id = id
        self.name = name
        self.phoneNumber = phoneNumber
    }
}
