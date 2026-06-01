import Foundation

struct WorkspaceMetadata: Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    let createdAt: Date
    let sourceCatalogFilename: String
    var workspaceDescription: String

    init(
        id: UUID,
        displayName: String,
        createdAt: Date,
        sourceCatalogFilename: String,
        workspaceDescription: String = ""
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.sourceCatalogFilename = sourceCatalogFilename
        self.workspaceDescription = workspaceDescription
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case createdAt
        case sourceCatalogFilename
        case workspaceDescription = "description"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sourceCatalogFilename = try container.decode(String.self, forKey: .sourceCatalogFilename)
        workspaceDescription = try container.decodeIfPresent(
            String.self,
            forKey: .workspaceDescription
        ) ?? ""
    }
}
