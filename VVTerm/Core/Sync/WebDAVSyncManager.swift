import Combine
import Foundation
import os.log

enum WebDAVSyncSettings {
    static let enabledKey = "webDAVSyncEnabled"
    static let serverURLKey = "webDAVServerURL"
    static let usernameKey = "webDAVUsername"
    static let remotePathKey = "webDAVRemotePath"
    static let defaultRemotePath = "VVTerm/vvterm-sync.json"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
    }
}

struct WebDAVSyncSnapshot: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let deviceId: String
    var servers: [Server]
    var workspaces: [Workspace]
    var terminalThemes: [TerminalTheme]
    var terminalThemePreference: TerminalThemePreference?
    var terminalAccessoryProfile: TerminalAccessoryProfile?
    var terminalSnippetLibrary: TerminalSnippetLibrary?

    init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        deviceId: String = DeviceIdentity.id,
        servers: [Server],
        workspaces: [Workspace],
        terminalThemes: [TerminalTheme],
        terminalThemePreference: TerminalThemePreference?,
        terminalAccessoryProfile: TerminalAccessoryProfile?,
        terminalSnippetLibrary: TerminalSnippetLibrary?
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.deviceId = deviceId
        self.servers = servers
        self.workspaces = workspaces
        self.terminalThemes = terminalThemes
        self.terminalThemePreference = terminalThemePreference
        self.terminalAccessoryProfile = terminalAccessoryProfile
        self.terminalSnippetLibrary = terminalSnippetLibrary
    }
}

enum WebDAVSyncError: LocalizedError {
    case invalidServerURL
    case missingCredentials
    case invalidResponse
    case httpStatus(Int)
    case remoteFileNotFound

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return String(localized: "Enter a valid WebDAV server URL.")
        case .missingCredentials:
            return String(localized: "Enter your WebDAV username and password.")
        case .invalidResponse:
            return String(localized: "The WebDAV server returned an invalid response.")
        case .httpStatus(let status):
            return String(format: String(localized: "WebDAV request failed with HTTP %lld."), Int64(status))
        case .remoteFileNotFound:
            return String(localized: "No WebDAV sync file was found.")
        }
    }
}

private struct WebDAVCredentials {
    var serverURL: URL
    var username: String
    var password: String
    var remotePath: String
}

@MainActor
final class WebDAVSyncManager: ObservableObject {
    static let shared = WebDAVSyncManager()

    @Published var isSyncing = false
    @Published var statusMessage: String = String(localized: "Disabled")
    @Published var lastSyncDate: Date?
    @Published var lastError: String?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.vivy.vvterm",
        category: "WebDAVSync"
    )
    private let defaults: UserDefaults
    private let session: URLSession

    private init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    func testConnection() async {
        await runSyncOperation(status: String(localized: "Testing WebDAV...")) {
            let credentials = try self.loadCredentials()
            try await self.ensureParentCollections(credentials: credentials)
            self.statusMessage = String(localized: "WebDAV connected")
        }
    }

    func uploadCurrentSnapshot() async {
        await runSyncOperation(status: String(localized: "Uploading to WebDAV...")) {
            let credentials = try self.loadCredentials()
            let snapshot = self.makeSnapshot()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)

            try await self.ensureParentCollections(credentials: credentials)
            let remoteURL = self.remoteFileURL(credentials: credentials)
            var request = self.authorizedRequest(url: remoteURL, credentials: credentials)
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            let (_, response) = try await self.perform(request)
            try self.validate(response: response, allowed: 200..<300)
            self.lastSyncDate = Date()
            self.statusMessage = String(localized: "Uploaded to WebDAV")
        }
    }

    func downloadAndApplySnapshot() async {
        await runSyncOperation(status: String(localized: "Downloading from WebDAV...")) {
            let credentials = try self.loadCredentials()
            let remoteURL = self.remoteFileURL(credentials: credentials)
            var request = self.authorizedRequest(url: remoteURL, credentials: credentials)
            request.httpMethod = "GET"

            let (data, response) = try await self.perform(request)
            if response.statusCode == 404 {
                throw WebDAVSyncError.remoteFileNotFound
            }
            try self.validate(response: response, allowed: 200..<300)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WebDAVSyncSnapshot.self, from: data)
            await self.apply(snapshot: snapshot)

            self.lastSyncDate = Date()
            self.statusMessage = String(localized: "Downloaded from WebDAV")
        }
    }

    private func runSyncOperation(
        status: String,
        operation: @escaping () async throws -> Void
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = status
        lastError = nil

        do {
            try await operation()
        } catch {
            let message = error.localizedDescription
            lastError = message
            statusMessage = String(format: String(localized: "WebDAV error: %@"), message)
            logger.error("WebDAV sync failed: \(message)")
        }

        isSyncing = false
    }

    private func makeSnapshot() -> WebDAVSyncSnapshot {
        let serverSnapshot = ServerManager.shared.webDAVSnapshot()
        return WebDAVSyncSnapshot(
            servers: serverSnapshot.servers,
            workspaces: serverSnapshot.workspaces,
            terminalThemes: TerminalThemeManager.shared.webDAVSnapshotThemes(),
            terminalThemePreference: TerminalThemeManager.shared.webDAVSnapshotPreference(),
            terminalAccessoryProfile: TerminalAccessoryPreferencesManager.shared.webDAVSnapshotProfile(),
            terminalSnippetLibrary: TerminalSnippetManager.shared.webDAVSnapshotLibrary()
        )
    }

    private func apply(snapshot: WebDAVSyncSnapshot) async {
        await ServerManager.shared.applyWebDAVSnapshot(
            servers: snapshot.servers,
            workspaces: snapshot.workspaces
        )
        TerminalThemeManager.shared.applyWebDAVSnapshot(
            themes: snapshot.terminalThemes,
            preference: snapshot.terminalThemePreference
        )
        if let profile = snapshot.terminalAccessoryProfile {
            TerminalAccessoryPreferencesManager.shared.applyWebDAVSnapshot(profile)
        }
        if let snippetLibrary = snapshot.terminalSnippetLibrary {
            TerminalSnippetManager.shared.applyWebDAVSnapshot(snippetLibrary)
        }
    }

    private func loadCredentials() throws -> WebDAVCredentials {
        let rawURL = defaults.string(forKey: WebDAVSyncSettings.serverURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: rawURL), let scheme = url.scheme, scheme.hasPrefix("http") else {
            throw WebDAVSyncError.invalidServerURL
        }

        let username = defaults.string(forKey: WebDAVSyncSettings.usernameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = try KeychainManager.shared.getWebDAVPassword() ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            throw WebDAVSyncError.missingCredentials
        }

        let remotePath = normalizedRemotePath(
            defaults.string(forKey: WebDAVSyncSettings.remotePathKey)
        )
        return WebDAVCredentials(
            serverURL: url,
            username: username,
            password: password,
            remotePath: remotePath
        )
    }

    private func normalizedRemotePath(_ path: String?) -> String {
        let trimmed = path?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) ?? ""
        return trimmed.isEmpty ? WebDAVSyncSettings.defaultRemotePath : trimmed
    }

    private func remoteFileURL(credentials: WebDAVCredentials) -> URL {
        url(from: credentials.serverURL, appending: credentials.remotePath)
    }

    private func url(from baseURL: URL, appending remotePath: String) -> URL {
        var url = baseURL
        for segment in remotePath.split(separator: "/") {
            url.appendPathComponent(String(segment))
        }
        return url
    }

    private func ensureParentCollections(credentials: WebDAVCredentials) async throws {
        let segments = credentials.remotePath.split(separator: "/").map(String.init)
        guard segments.count > 1 else { return }

        var collectionURL = credentials.serverURL
        for segment in segments.dropLast() {
            collectionURL.appendPathComponent(segment, isDirectory: true)
            var request = authorizedRequest(url: collectionURL, credentials: credentials)
            request.httpMethod = "MKCOL"

            let (_, response) = try await perform(request)
            if response.statusCode == 405 {
                continue
            }
            try validate(response: response, allowed: 200..<300)
        }
    }

    private func authorizedRequest(url: URL, credentials: WebDAVCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let raw = "\(credentials.username):\(credentials.password)"
        let token = Data(raw.utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("VVTerm", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVSyncError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func validate(response: HTTPURLResponse, allowed: Range<Int>) throws {
        guard allowed.contains(response.statusCode) else {
            throw WebDAVSyncError.httpStatus(response.statusCode)
        }
    }
}
