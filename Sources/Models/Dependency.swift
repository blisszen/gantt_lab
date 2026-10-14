import Foundation

struct Dependency: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var fromTaskId: UUID
    var toTaskId: UUID
    
    init(id: UUID = UUID(), fromTaskId: UUID, toTaskId: UUID) {
        self.id = id
        self.fromTaskId = fromTaskId
        self.toTaskId = toTaskId
    }
}
