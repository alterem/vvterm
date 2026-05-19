import Foundation
import Combine

@MainActor
final class TerminalSnippetManager: ObservableObject {
    static let shared = TerminalSnippetManager()

    @Published private(set) var library: TerminalSnippetLibrary

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.library = Self.loadLibrary(from: defaults)
    }

    var snippets: [TerminalSnippetEntry] {
        library.entries
            .filter { !$0.isDeleted }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var canCreateSnippet: Bool {
        snippets.count < TerminalSnippetLibrary.maxEntries
    }

    func snippet(for id: UUID) -> TerminalSnippetEntry? {
        snippets.first { $0.id == id }
    }

    @discardableResult
    func createSnippet(
        name: String,
        content: String,
        description: String,
        sendBehavior: TerminalSnippetSendBehavior
    ) throws -> TerminalSnippetEntry {
        guard canCreateSnippet else {
            throw TerminalSnippetValidationError.snippetLimitReached
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TerminalSnippetValidationError.emptyName
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TerminalSnippetValidationError.emptyContent
        }

        let now = Date()
        let entry = TerminalSnippetEntry(
            name: String(trimmedName.prefix(TerminalSnippetLibrary.maxNameLength)),
            content: String(content.prefix(TerminalSnippetLibrary.maxContentLength)),
            description: String(
                description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(TerminalSnippetLibrary.maxDescriptionLength)
            ),
            sendBehavior: sendBehavior,
            updatedAt: now,
            deletedAt: nil
        )

        applyLibraryMutation(at: now) { nextLibrary, _ in
            nextLibrary.entries.insert(entry, at: 0)
        }

        return entry
    }

    @discardableResult
    func updateSnippet(
        id: UUID,
        name: String,
        content: String,
        description: String,
        sendBehavior: TerminalSnippetSendBehavior
    ) throws -> TerminalSnippetEntry {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw TerminalSnippetValidationError.emptyName
        }

        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TerminalSnippetValidationError.emptyContent
        }

        guard let index = library.entries.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
            throw TerminalSnippetValidationError.snippetNotFound
        }

        let now = Date()
        applyLibraryMutation(at: now) { nextLibrary, mutationDate in
            nextLibrary.entries[index].name = String(trimmedName.prefix(TerminalSnippetLibrary.maxNameLength))
            nextLibrary.entries[index].content = String(content.prefix(TerminalSnippetLibrary.maxContentLength))
            nextLibrary.entries[index].description = String(
                description
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(TerminalSnippetLibrary.maxDescriptionLength)
            )
            nextLibrary.entries[index].sendBehavior = sendBehavior
            nextLibrary.entries[index].updatedAt = mutationDate
            nextLibrary.entries[index].deletedAt = nil
        }

        guard let snippet = snippet(for: id) else {
            throw TerminalSnippetValidationError.snippetNotFound
        }
        return snippet
    }

    func deleteSnippet(id: UUID) {
        guard let index = library.entries.firstIndex(where: { $0.id == id && !$0.isDeleted }) else {
            return
        }

        applyLibraryMutation { nextLibrary, now in
            nextLibrary.entries[index].name = ""
            nextLibrary.entries[index].content = ""
            nextLibrary.entries[index].description = ""
            nextLibrary.entries[index].deletedAt = now
            nextLibrary.entries[index].updatedAt = now
        }
    }

    func webDAVSnapshotLibrary() -> TerminalSnippetLibrary {
        library
    }

    func applyWebDAVSnapshot(_ remoteLibrary: TerminalSnippetLibrary) {
        let merged = TerminalSnippetLibrary.merged(local: library, remote: remoteLibrary).normalized()
        applyLibrary(merged)
    }

    private func applyLibraryMutation(
        at mutationDate: Date = Date(),
        _ mutate: (inout TerminalSnippetLibrary, Date) -> Void
    ) {
        var nextLibrary = library
        mutate(&nextLibrary, mutationDate)
        nextLibrary.updatedAt = mutationDate
        nextLibrary.lastWriterDeviceId = DeviceIdentity.id
        applyLibrary(nextLibrary.normalized())
    }

    private func applyLibrary(_ nextLibrary: TerminalSnippetLibrary) {
        library = nextLibrary
        persistLibrary(nextLibrary)
    }

    private func persistLibrary(_ nextLibrary: TerminalSnippetLibrary) {
        if let data = try? JSONEncoder().encode(nextLibrary) {
            defaults.set(data, forKey: TerminalSnippetLibrary.defaultsKey)
        }
    }

    private static func loadLibrary(from defaults: UserDefaults) -> TerminalSnippetLibrary {
        guard let data = defaults.data(forKey: TerminalSnippetLibrary.defaultsKey) else {
            let defaultLibrary = TerminalSnippetLibrary.defaultValue.normalized()
            if let encoded = try? JSONEncoder().encode(defaultLibrary) {
                defaults.set(encoded, forKey: TerminalSnippetLibrary.defaultsKey)
            }
            return defaultLibrary
        }

        do {
            let decoded = try JSONDecoder().decode(TerminalSnippetLibrary.self, from: data).normalized()
            if let encoded = try? JSONEncoder().encode(decoded) {
                defaults.set(encoded, forKey: TerminalSnippetLibrary.defaultsKey)
            }
            return decoded
        } catch {
            let defaultLibrary = TerminalSnippetLibrary.defaultValue.normalized()
            if let encoded = try? JSONEncoder().encode(defaultLibrary) {
                defaults.set(encoded, forKey: TerminalSnippetLibrary.defaultsKey)
            }
            return defaultLibrary
        }
    }
}
