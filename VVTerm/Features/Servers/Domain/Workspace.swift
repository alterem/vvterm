import Foundation
import SwiftUI

// MARK: - Workspace Model (CloudKit synced)

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var icon: String?
    var order: Int
    var environments: [ServerEnvironment]
    var folders: [WorkspaceServerFolder]
    var lastSelectedEnvironmentId: UUID?
    var lastSelectedServerId: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#007AFF",
        icon: String? = nil,
        order: Int = 0,
        environments: [ServerEnvironment] = ServerEnvironment.builtInEnvironments,
        folders: [WorkspaceServerFolder] = [],
        lastSelectedEnvironmentId: UUID? = nil,
        lastSelectedServerId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.order = order
        self.environments = environments
        self.folders = folders
        self.lastSelectedEnvironmentId = lastSelectedEnvironmentId
        self.lastSelectedServerId = lastSelectedServerId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var color: Color {
        Color.fromHex(colorHex)
    }

    func environment(withId id: UUID) -> ServerEnvironment? {
        environments.first { $0.id == id }
    }

    func containsEnvironment(_ candidate: ServerEnvironment) -> Bool {
        environment(withId: candidate.id) != nil
    }

    func folder(withId id: UUID) -> WorkspaceServerFolder? {
        folders.first { $0.id == id }
    }

    func childFolders(of parentId: UUID?) -> [WorkspaceServerFolder] {
        folders
            .filter { $0.parentId == parentId }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func folderPath(for folderId: UUID?) -> [WorkspaceServerFolder] {
        guard let folderId else { return [] }

        var path: [WorkspaceServerFolder] = []
        var currentId: UUID? = folderId
        var visited = Set<UUID>()

        while let activeFolderId = currentId,
              !visited.contains(activeFolderId),
              let folder = folder(withId: activeFolderId) {
            path.append(folder)
            visited.insert(activeFolderId)
            currentId = folder.parentId
        }

        return path.reversed()
    }

    func folderPathNames(for folderId: UUID?) -> [String] {
        folderPath(for: folderId).map(\.name)
    }

    func folderDisplayName(for folderId: UUID?, separator: String = " / ") -> String? {
        let names = folderPathNames(for: folderId)
        guard !names.isEmpty else { return nil }
        return names.joined(separator: separator)
    }

    func descendantFolderIDs(of folderId: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var stack = childFolders(of: folderId).map(\.id)

        while let nextId = stack.popLast() {
            guard result.insert(nextId).inserted else { continue }
            stack.append(contentsOf: childFolders(of: nextId).map(\.id))
        }

        return result
    }

    static let defaultColors: [String] = [
        "#007AFF", // Blue (default)
        "#AF52DE", // Purple
        "#FF2D55", // Pink
        "#FF3B30", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#5AC8FA", // Teal
        "#00C7BE", // Cyan
        "#5856D6"  // Indigo
    ]
}

// MARK: - Color Extension

extension Color {
    nonisolated static func fromHex(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
