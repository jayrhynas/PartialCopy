import PartialCopy

@PartialCopyable
struct Person {
    let firstName: String
    let lastName: String
    
    init(firstName: String, lastName: String) async throws {
        self.firstName = firstName
        self.lastName = lastName
    }
}
