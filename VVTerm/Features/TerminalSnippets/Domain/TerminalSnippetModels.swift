import Foundation

enum TerminalSnippetSendBehavior: String, Codable, CaseIterable, Identifiable {
    case insert
    case insertAndEnter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insert:
            return String(localized: "Insert")
        case .insertAndEnter:
            return String(localized: "Insert + Enter")
        }
    }
}

struct TerminalSnippetEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var content: String
    var description: String
    var sendBehavior: TerminalSnippetSendBehavior
    var updatedAt: Date
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        content: String,
        description: String = "",
        sendBehavior: TerminalSnippetSendBehavior = .insert,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.description = description
        self.sendBehavior = sendBehavior
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    var contentPreview: String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TerminalSnippetLibrary: Codable, Equatable {
    var schemaVersion: Int
    var entries: [TerminalSnippetEntry]
    var updatedAt: Date
    var lastWriterDeviceId: String

    init(
        schemaVersion: Int,
        entries: [TerminalSnippetEntry],
        updatedAt: Date,
        lastWriterDeviceId: String
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.updatedAt = updatedAt
        self.lastWriterDeviceId = lastWriterDeviceId
    }
}

extension TerminalSnippetLibrary {
    static let schemaVersion = 1
    static let defaultsKey = "terminalSnippetLibrary.v1"
    static let maxEntries = 500
    static let maxNameLength = 80
    static let maxDescriptionLength = 240
    static let maxContentLength = 12000

    static var defaultValue: TerminalSnippetLibrary {
        TerminalSnippetLibrary(
            schemaVersion: schemaVersion,
            entries: [],
            updatedAt: .distantPast,
            lastWriterDeviceId: DeviceIdentity.id
        )
    }

    func normalized() -> TerminalSnippetLibrary {
        var entriesByID: [UUID: TerminalSnippetEntry] = [:]
        for entry in entries {
            let normalizedEntry = entry.normalized()
            if let existing = entriesByID[normalizedEntry.id] {
                if normalizedEntry.updatedAt >= existing.updatedAt {
                    entriesByID[normalizedEntry.id] = normalizedEntry
                }
            } else {
                entriesByID[normalizedEntry.id] = normalizedEntry
            }
        }

        let sortedEntries = entriesByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let activeIDs = Set(
            sortedEntries
                .filter { !$0.isDeleted }
                .prefix(Self.maxEntries)
                .map(\.id)
        )

        let limitedEntries = sortedEntries.filter { $0.isDeleted || activeIDs.contains($0.id) }

        return TerminalSnippetLibrary(
            schemaVersion: max(schemaVersion, Self.schemaVersion),
            entries: limitedEntries,
            updatedAt: max(updatedAt, limitedEntries.first?.updatedAt ?? .distantPast),
            lastWriterDeviceId: lastWriterDeviceId.isEmpty ? DeviceIdentity.id : lastWriterDeviceId
        )
    }

    static func merged(local: TerminalSnippetLibrary, remote: TerminalSnippetLibrary) -> TerminalSnippetLibrary {
        let normalizedLocal = local.normalized()
        let normalizedRemote = remote.normalized()

        var entriesByID: [UUID: TerminalSnippetEntry] = [:]
        for entry in normalizedRemote.entries {
            entriesByID[entry.id] = entry
        }

        for entry in normalizedLocal.entries {
            if let existing = entriesByID[entry.id] {
                if entry.updatedAt >= existing.updatedAt {
                    entriesByID[entry.id] = entry
                }
            } else {
                entriesByID[entry.id] = entry
            }
        }

        let mergedEntries = entriesByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        let mergedUpdatedAt = max(
            normalizedLocal.updatedAt,
            normalizedRemote.updatedAt,
            mergedEntries.first?.updatedAt ?? .distantPast
        )

        let writerDeviceID: String
        if mergedUpdatedAt == normalizedLocal.updatedAt {
            writerDeviceID = normalizedLocal.lastWriterDeviceId
        } else {
            writerDeviceID = normalizedRemote.lastWriterDeviceId
        }

        return TerminalSnippetLibrary(
            schemaVersion: max(normalizedLocal.schemaVersion, normalizedRemote.schemaVersion, Self.schemaVersion),
            entries: mergedEntries,
            updatedAt: mergedUpdatedAt,
            lastWriterDeviceId: writerDeviceID
        )
        .normalized()
    }
}

private extension TerminalSnippetEntry {
    func normalized() -> TerminalSnippetEntry {
        let sanitizedName: String
        let sanitizedContent: String
        let sanitizedDescription: String

        if isDeleted {
            sanitizedName = ""
            sanitizedContent = ""
            sanitizedDescription = ""
        } else {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitizedName = String(trimmedName.prefix(TerminalSnippetLibrary.maxNameLength))
            sanitizedContent = String(content.prefix(TerminalSnippetLibrary.maxContentLength))
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            sanitizedDescription = String(trimmedDescription.prefix(TerminalSnippetLibrary.maxDescriptionLength))
        }

        return TerminalSnippetEntry(
            id: id,
            name: sanitizedName,
            content: sanitizedContent,
            description: sanitizedDescription,
            sendBehavior: sendBehavior,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
