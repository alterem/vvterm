import Foundation

struct WorkspaceServerFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var parentId: UUID?
    var name: String
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        parentId: UUID? = nil,
        name: String,
        order: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentId = parentId
        self.name = name
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
