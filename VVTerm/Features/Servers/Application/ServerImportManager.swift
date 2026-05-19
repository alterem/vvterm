import Foundation
import ZIPFoundation

@MainActor
final class ServerImportManager {
    static let shared = ServerImportManager()

    private init() {}

    func previewVVTermExcelImport(from url: URL) throws -> ServerImportPreview {
        let data = try readFileData(from: url)
        return try VVTermWorkbookImporter.parseWorkbook(data: data)
    }

    func previewSecureCRTImport(fromSessionsDirectory url: URL) throws -> ServerImportPreview {
        let records = try SecureCRTSessionImporter.parseSessionsDirectory(at: url)
        return ServerImportPreview(items: records)
    }

    func applyImportPreview(
        _ preview: ServerImportPreview,
        into serverManager: ServerManager
    ) async throws -> ServerImportResult {
        let grouped = Dictionary(grouping: preview.items, by: \.workspaceName)
        let existingWorkspaceNames = Set(serverManager.workspaces.map(\.name))
        var createdWorkspaces: [String: Workspace] = [:]
        var nextOrder = (serverManager.workspaces.map(\.order).max() ?? -1) + 1

        for workspaceName in grouped.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard !workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard !existingWorkspaceNames.contains(workspaceName),
                  createdWorkspaces[workspaceName] == nil else { continue }

            let workspace = Workspace(
                name: workspaceName,
                colorHex: Workspace.defaultColors[nextOrder % Workspace.defaultColors.count],
                order: nextOrder
            )
            try await serverManager.addWorkspace(workspace)
            createdWorkspaces[workspaceName] = workspace
            nextOrder += 1
        }

        var workspaceByName: [String: Workspace] = Dictionary(uniqueKeysWithValues: serverManager.workspaces.map { ($0.name, $0) })
        let workspaceNameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: serverManager.workspaces.map { ($0.id, $0.name) })
        var existingServerKeys = Set<String>(serverManager.servers.compactMap { server -> String? in
            guard let workspaceName = workspaceNameByID[server.workspaceId] else { return nil }
            return makeDeduplicationKey(
                workspaceName: workspaceName,
                serverName: server.name,
                host: server.host,
                port: server.port,
                username: server.username
            )
        })
        var importedCount = 0
        var skippedCount = 0

        for item in preview.items {
            guard var workspace = workspaceByName[item.workspaceName] else { continue }
            let deduplicationKey = makeDeduplicationKey(
                workspaceName: item.workspaceName,
                serverName: item.server.name,
                host: item.server.host,
                port: item.server.port,
                username: item.server.username
            )
            if existingServerKeys.contains(deduplicationKey) {
                skippedCount += 1
                continue
            }

            let folderId = try await ensureFolderPath(
                item.folderPath,
                in: workspace,
                using: serverManager
            )
            workspace = serverManager.workspace(withId: workspace.id) ?? workspace
            workspaceByName[item.workspaceName] = workspace

            var server = item.server
            server.workspaceId = workspace.id
            server.folderId = folderId
            try await serverManager.addServer(server, credentials: item.credentials)
            existingServerKeys.insert(deduplicationKey)
            importedCount += 1
        }

        return ServerImportResult(
            importedCount: importedCount,
            workspaceCount: Set(preview.items.map(\.workspaceName)).count,
            skippedCount: skippedCount
        )
    }

    private func readFileData(from url: URL) throws -> Data {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try Data(contentsOf: url)
    }

    private func makeDeduplicationKey(
        workspaceName: String,
        serverName: String,
        host: String,
        port: Int,
        username: String
    ) -> String {
        [
            workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            serverName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(port),
            username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "|")
    }

    private func ensureFolderPath(
        _ folderPath: [String],
        in workspace: Workspace,
        using serverManager: ServerManager
    ) async throws -> UUID? {
        guard !folderPath.isEmpty else { return nil }

        var refreshedWorkspace = serverManager.workspace(withId: workspace.id) ?? workspace
        var currentParentId: UUID?

        for component in folderPath {
            let trimmedName = component.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else { continue }

            if let existing = refreshedWorkspace.folders.first(where: {
                $0.parentId == currentParentId &&
                $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            }) {
                currentParentId = existing.id
                continue
            }

            let created = try await serverManager.createFolder(
                name: trimmedName,
                in: refreshedWorkspace,
                parentId: currentParentId
            )
            refreshedWorkspace = serverManager.workspace(withId: refreshedWorkspace.id) ?? refreshedWorkspace
            currentParentId = created.id
        }

        return currentParentId
    }
}

private enum VVTermWorkbookImporter {
    enum ImportError: LocalizedError {
        case missingWorkbook
        case malformedWorksheet(String)

        var errorDescription: String? {
            switch self {
            case .missingWorkbook:
                return String(localized: "The selected Excel file is not a valid VVTerm server export.")
            case .malformedWorksheet(let name):
                return String(format: String(localized: "The Excel worksheet could not be parsed: %@"), name)
            }
        }
    }

    private static let connectionHeaders = [
        "Workspace",
        "Environment",
        "Server",
        "Host",
        "Port",
        "Username",
        "Password",
        "Auth Method",
        "Connection Mode",
        "Tags",
        "Notes"
    ]

    private static let keyHeaders = [
        "Workspace",
        "Server",
        "Host",
        "Username",
        "Auth Method",
        "Private Key",
        "Public Key",
        "Passphrase"
    ]

    private struct KeyMaterial {
        let privateKey: String
        let publicKey: String
        let passphrase: String
    }

    static func parseWorkbook(data: Data) throws -> ServerImportPreview {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VVTerm-ServerImport-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL, options: .atomic)

        guard let archive = Archive(url: temporaryURL, accessMode: .read) else {
            throw ImportError.missingWorkbook
        }

        let sheet1 = try readArchiveEntry(named: "xl/worksheets/sheet1.xml", from: archive)
        let sheet2 = try readArchiveEntry(named: "xl/worksheets/sheet2.xml", from: archive)
        let connectionRows = try parseWorksheetRows(xml: sheet1, worksheetName: "sheet1")
        let keyRows = try parseWorksheetRows(xml: sheet2, worksheetName: "sheet2")

        guard connectionRows.first == connectionHeaders else {
            throw ImportError.missingWorkbook
        }
        guard keyRows.isEmpty || keyRows.first == keyHeaders else {
            throw ImportError.missingWorkbook
        }

        let keyMaterials: [String: KeyMaterial] = Dictionary(
            uniqueKeysWithValues: keyRows.dropFirst().compactMap { row -> (String, KeyMaterial)? in
                let normalized = paddedRow(row, count: keyHeaders.count)
                let key = makeKey(
                    workspace: normalized[0],
                    server: normalized[1],
                    host: normalized[2],
                    username: normalized[3]
                )
                guard !key.isEmpty else { return nil }
                return (
                    key,
                    KeyMaterial(
                        privateKey: normalized[5],
                        publicKey: normalized[6],
                        passphrase: normalized[7]
                    )
                )
            }
        )

        let records: [ImportedServerRecord] = connectionRows.dropFirst().compactMap { row -> ImportedServerRecord? in
            let normalized = paddedRow(row, count: connectionHeaders.count)
            let workspaceName = normalized[0].nilIfBlank ?? String(localized: "Imported")
            let environment = environment(from: normalized[1])
            let name = normalized[2].nilIfBlank ?? normalized[3].nilIfBlank ?? String(localized: "Imported Server")
            guard let host = normalized[3].nilIfBlank,
                  let username = normalized[5].nilIfBlank else {
                return nil
            }

            let port = Int(normalized[4]) ?? 22
            let authMethod = authMethod(from: normalized[7], password: normalized[6], keyMaterial: keyMaterials[makeKey(
                workspace: workspaceName,
                server: normalized[2],
                host: host,
                username: username
            )])
            let connectionMode = connectionMode(from: normalized[8])
            let tags = normalized[9]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let notes = normalized[10].nilIfBlank
            let keyMaterial = keyMaterials[makeKey(
                workspace: workspaceName,
                server: normalized[2],
                host: host,
                username: username
            )]

            var credentials = ServerCredentials(serverId: UUID())
            if let password = normalized[6].nilIfBlank {
                credentials.password = password
            }
            if let privateKey = keyMaterial.flatMap(\.privateKey.nilIfBlank) {
                credentials.privateKey = Data(privateKey.utf8)
            }
            if let publicKey = keyMaterial.flatMap(\.publicKey.nilIfBlank) {
                credentials.publicKey = Data(publicKey.utf8)
            }
            credentials.passphrase = keyMaterial.flatMap(\.passphrase.nilIfBlank)

            let server = Server(
                workspaceId: UUID(),
                environment: environment,
                name: name,
                host: host,
                port: port,
                username: username,
                connectionMode: connectionMode,
                authMethod: authMethod,
                tags: tags,
                notes: notes
            )

            return ImportedServerRecord(
                source: .vvtermExcel,
                workspaceName: workspaceName,
                folderPath: [],
                server: server,
                credentials: credentials
            )
        }

        return ServerImportPreview(items: records)
    }

    private static func readArchiveEntry(named path: String, from archive: Archive) throws -> String {
        guard let entry = archive[path] else {
            if path.hasSuffix("sheet2.xml") {
                return ""
            }
            throw ImportError.missingWorkbook
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func parseWorksheetRows(xml: String, worksheetName: String) throws -> [[String]] {
        guard !xml.isEmpty else { return [] }
        let parser = WorksheetInlineStringParser()
        guard parser.parse(xml: xml) else {
            throw ImportError.malformedWorksheet(worksheetName)
        }
        return parser.rows
    }

    private static func paddedRow(_ row: [String], count: Int) -> [String] {
        if row.count >= count {
            return Array(row.prefix(count))
        }
        return row + Array(repeating: "", count: count - row.count)
    }

    private static func environment(from text: String) -> ServerEnvironment {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "production", "prod":
            return .production
        case "staging", "stag":
            return .staging
        case "development", "dev":
            return .development
        default:
            return .production
        }
    }

    private static func connectionMode(from text: String) -> SSHConnectionMode {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "tailscale":
            return .tailscale
        case "mosh":
            return .mosh
        case "cloudflare":
            return .cloudflare
        default:
            return .standard
        }
    }

    private static func authMethod(from text: String, password: String, keyMaterial: KeyMaterial?) -> AuthMethod {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "ssh key + passphrase":
            return .sshKeyWithPassphrase
        case "ssh key":
            return keyMaterial.flatMap(\.passphrase.nilIfBlank) == nil ? .sshKey : .sshKeyWithPassphrase
        case "password":
            return .password
        default:
            if keyMaterial.flatMap(\.privateKey.nilIfBlank) != nil {
                return keyMaterial.flatMap(\.passphrase.nilIfBlank) == nil ? .sshKey : .sshKeyWithPassphrase
            }
            if password.nilIfBlank != nil {
                return .password
            }
            return .password
        }
    }

    private static func makeKey(workspace: String, server: String, host: String, username: String) -> String {
        [
            workspace.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            server.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ].joined(separator: "|")
    }

    private final class WorksheetInlineStringParser: NSObject, XMLParserDelegate {
        private var activeRowIndex: Int?
        private var activeColumnIndex = 0
        private var activeCellText = ""
        private var collectingText = false

        private(set) var rows: [[String]] = []

        func parse(xml: String) -> Bool {
            guard let data = xml.data(using: .utf8) else { return false }
            let parser = XMLParser(data: data)
            parser.delegate = self
            return parser.parse()
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            switch elementName {
            case "row":
                activeRowIndex = Int(attributeDict["r"] ?? "") ?? (rows.count + 1)
            case "c":
                let reference = attributeDict["r"] ?? ""
                activeColumnIndex = columnIndex(from: reference)
                activeCellText = ""
            case "t":
                collectingText = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard collectingText else { return }
            activeCellText.append(string)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            switch elementName {
            case "t":
                collectingText = false
            case "c":
                guard let rowNumber = activeRowIndex, rowNumber > 0 else { return }
                ensureRowExists(rowNumber - 1)
                ensureColumnExists(rowIndex: rowNumber - 1, columnIndex: activeColumnIndex)
                rows[rowNumber - 1][activeColumnIndex] = activeCellText
            case "row":
                activeRowIndex = nil
            default:
                break
            }
        }

        private func ensureRowExists(_ index: Int) {
            while rows.count <= index {
                rows.append([])
            }
        }

        private func ensureColumnExists(rowIndex: Int, columnIndex: Int) {
            while rows[rowIndex].count <= columnIndex {
                rows[rowIndex].append("")
            }
        }

        private func columnIndex(from reference: String) -> Int {
            let letters = reference.prefix { $0.isLetter }
            guard !letters.isEmpty else { return 0 }
            var value = 0
            for scalar in letters.uppercased().unicodeScalars {
                value = value * 26 + Int(scalar.value) - 64
            }
            return max(value - 1, 0)
        }
    }
}

private enum SecureCRTSessionImporter {
    enum ImportError: LocalizedError {
        case notDirectory

        var errorDescription: String? {
            switch self {
            case .notDirectory:
                return String(localized: "Please choose the SecureCRT Sessions folder.")
            }
        }
    }

    private static let ignoredFilenames: Set<String> = [
        "__folder_data__.ini",
        ".DS_Store"
    ]

    static func parseSessionsDirectory(at url: URL) throws -> [ImportedServerRecord] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ImportError.notDirectory
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var records: [ImportedServerRecord] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }

            let name = fileURL.lastPathComponent
            guard !ignoredFilenames.contains(name),
                  fileURL.pathExtension.lowercased() == "ini" else {
                continue
            }

            let content = try readSessionContent(from: fileURL)
            if let record = parseSessionFile(content: content, fileURL: fileURL, rootURL: url) {
                records.append(record)
            }
        }

        return records.sorted {
            let lhsWorkspace = $0.workspaceName.localizedStandardCompare($1.workspaceName)
            if lhsWorkspace != .orderedSame {
                return lhsWorkspace == .orderedAscending
            }
            return $0.server.name.localizedStandardCompare($1.server.name) == .orderedAscending
        }
    }

    private static func parseSessionFile(content: String, fileURL: URL, rootURL: URL) -> ImportedServerRecord? {
        let values = parseKeyValuePairs(content)

        guard isSSHProtocol(values) else { return nil }
        guard let host = firstNonEmpty(values["S:Hostname"], values["S:\"Hostname\""]) else { return nil }

        let username = firstNonEmpty(values["S:Username"], values["S:\"Username\""]) ?? ""
        let portString = firstNonEmpty(
            values["D:[SSH2] Port"],
            values["D:\"[SSH2] Port\""],
            values["D:Port"],
            values["D:\"Port\""],
            values["S:Port"],
            values["S:\"Port\""]
        )
        let port = parsePort(from: portString) ?? 22
        let sessionName = fileURL.deletingPathExtension().lastPathComponent
        let sessionLocation = sessionLocation(for: fileURL, rootURL: rootURL)
        let authMethod = resolveAuthMethod(values: values)
        let notes = firstNonEmpty(values["S:Description"], values["S:\"Description\""])

        let credentials = ServerCredentials(serverId: UUID())

        let server = Server(
            workspaceId: UUID(),
            environment: inferEnvironment(
                from: [sessionLocation.workspaceName] + sessionLocation.folderPath,
                sessionName: sessionName
            ),
            name: sessionName,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            tags: sessionLocation.folderPath,
            notes: notes
        )

        return ImportedServerRecord(
            source: .secureCRT,
            workspaceName: sessionLocation.workspaceName,
            folderPath: sessionLocation.folderPath,
            server: server,
            credentials: credentials
        )
    }

    private static func parseKeyValuePairs(_ content: String) -> [String: String] {
        content
            .split(whereSeparator: \.isNewline)
            .reduce(into: [String: String]()) { result, rawLine in
                let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty,
                      !line.hasPrefix("#"),
                      !line.hasPrefix(";"),
                      let separatorIndex = line.firstIndex(of: "=") else {
                    return
                }
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                result[key] = value
            }
    }

    private static func readSessionContent(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .windowsCP1252] {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func isSSHProtocol(_ values: [String: String]) -> Bool {
        let protocolValue = firstNonEmpty(values["S:Protocol Name"], values["S:\"Protocol Name\""])?.lowercased()
        let protocolRaw = firstNonEmpty(values["S:Protocol Name"], values["S:\"Protocol Name\""]) ?? ""
        return protocolValue == nil || protocolValue == "ssh2" || protocolRaw.contains("SSH2")
    }

    private static func resolveAuthMethod(values: [String: String]) -> AuthMethod {
        let useKey = firstNonEmpty(values["S:Identity Filename V2"], values["S:\"Identity Filename V2\""])?.isEmpty == false
            || firstNonEmpty(values["S:Identity Filename"], values["S:\"Identity Filename\""])?.isEmpty == false
        let passphrase = firstNonEmpty(values["S:Passphrase"], values["S:\"Passphrase\""])

        if useKey {
            return passphrase.flatMap { $0.nilIfBlank } == nil ? .sshKey : .sshKeyWithPassphrase
        }
        return .password
    }

    private struct SessionLocation {
        let workspaceName: String
        let folderPath: [String]
    }

    private static func sessionLocation(for fileURL: URL, rootURL: URL) -> SessionLocation {
        let relativeComponents = fileURL.deletingLastPathComponent()
            .path
            .replacingOccurrences(of: rootURL.path, with: "")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        let workspaceName = relativeComponents.first ?? String(localized: "SecureCRT")
        let folderPath = Array(relativeComponents.dropFirst())
        return SessionLocation(workspaceName: workspaceName, folderPath: folderPath)
    }

    private static func inferEnvironment(from pathComponents: [String], sessionName: String) -> ServerEnvironment {
        let combined = (pathComponents + [sessionName]).joined(separator: " ").lowercased()
        if combined.contains("stag") {
            return .staging
        }
        if combined.contains("dev") || combined.contains("test") || combined.contains("qa") {
            return .development
        }
        return .production
    }

    private static func parsePort(from rawValue: String?) -> Int? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if let direct = Int(rawValue) {
            return direct
        }

        let normalized = rawValue.lowercased()
        if normalized.hasPrefix("0x"),
           let hex = Int(normalized.dropFirst(2), radix: 16) {
            return hex
        }

        if rawValue.range(of: "^[0-9a-fA-F]{8}$", options: .regularExpression) != nil,
           let hex = Int(rawValue, radix: 16) {
            return hex
        }

        return nil
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                continue
            }
            return trimmed
        }
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
