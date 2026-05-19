import Foundation
import ZIPFoundation

struct ServerExportPackage {
    let data: Data
    let filename: String
}

@MainActor
final class ServerExportManager {
    static let shared = ServerExportManager()

    private let keychain = KeychainManager.shared

    private init() {}

    func makeExportPackage(servers: [Server], workspaces: [Workspace]) throws -> ServerExportPackage {
        let sortedServers = sortedServers(servers, workspaces: workspaces)
        let workspaceById = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        var connectionRows: [[String]] = []
        var keyRows: [[String]] = []

        for server in sortedServers {
            let workspaceName = workspaceById[server.workspaceId]?.name ?? String(localized: "Unknown Workspace")
            let credentials = (try? keychain.getCredentials(for: server)) ?? ServerCredentials(serverId: server.id)
            let privateKey = credentials.privateKey.flatMap(Self.utf8String) ?? ""
            let publicKey = credentials.publicKey.flatMap(Self.utf8String) ?? ""
            let passphrase = credentials.passphrase ?? ""

            connectionRows.append([
                workspaceName,
                server.environment.displayName,
                server.name,
                server.host,
                String(server.port),
                server.username,
                credentials.password ?? "",
                server.authMethod.displayName,
                displayName(for: server.connectionMode),
                server.tags.joined(separator: ", "),
                server.notes ?? ""
            ])

            if [privateKey, publicKey, passphrase].contains(where: { !$0.isEmpty }) {
                keyRows.append([
                    workspaceName,
                    server.name,
                    server.host,
                    server.username,
                    server.authMethod.displayName,
                    privateKey,
                    publicKey,
                    passphrase
                ])
            }
        }

        let data = try ServerExportWorkbookBuilder.makeWorkbookData(
            connectionRows: connectionRows,
            keyRows: keyRows
        )

        return ServerExportPackage(data: data, filename: defaultFilename())
    }

    private func sortedServers(_ servers: [Server], workspaces: [Workspace]) -> [Server] {
        let workspaceById = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.id, $0) })
        return servers.sorted { lhs, rhs in
            let lhsWorkspace = workspaceById[lhs.workspaceId]
            let rhsWorkspace = workspaceById[rhs.workspaceId]
            let lhsOrder = lhsWorkspace?.order ?? Int.max
            let rhsOrder = rhsWorkspace?.order ?? Int.max

            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }

            let lhsWorkspaceName = lhsWorkspace?.name ?? ""
            let rhsWorkspaceName = rhsWorkspace?.name ?? ""
            let workspaceComparison = lhsWorkspaceName.localizedStandardCompare(rhsWorkspaceName)
            if workspaceComparison != .orderedSame {
                return workspaceComparison == .orderedAscending
            }

            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func displayName(for mode: SSHConnectionMode) -> String {
        switch mode {
        case .standard:
            return String(localized: "SSH")
        case .tailscale:
            return String(localized: "Tailscale")
        case .mosh:
            return String(localized: "Mosh")
        case .cloudflare:
            return String(localized: "Cloudflare")
        }
    }

    private static func utf8String(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "VVTerm-Servers-\(formatter.string(from: Date())).xlsx"
    }
}

enum ServerExportWorkbookBuilder {
    private enum WorkbookError: LocalizedError {
        case archiveCreationFailed
        case entryTooLarge(String)

        var errorDescription: String? {
            switch self {
            case .archiveCreationFailed:
                return String(localized: "Failed to create the Excel export archive.")
            case .entryTooLarge(let path):
                return String(format: String(localized: "The Excel export entry is too large: %@"), path)
            }
        }
    }

    static func makeWorkbookData(connectionRows: [[String]], keyRows: [[String]]) throws -> Data {
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VVTerm-ServerExport-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let archive = Archive(url: temporaryURL, accessMode: .create) else {
            throw WorkbookError.archiveCreationFailed
        }

        try addEntry(named: "[Content_Types].xml", contents: contentTypesXML(), to: archive)
        try addEntry(named: "_rels/.rels", contents: rootRelationshipsXML(), to: archive)
        try addEntry(named: "xl/workbook.xml", contents: workbookXML(), to: archive)
        try addEntry(named: "xl/_rels/workbook.xml.rels", contents: workbookRelationshipsXML(), to: archive)
        try addEntry(named: "xl/styles.xml", contents: stylesXML(), to: archive)
        try addEntry(
            named: "xl/worksheets/sheet1.xml",
            contents: worksheetXML(
                headers: [
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
                ],
                rows: connectionRows
            ),
            to: archive
        )
        try addEntry(
            named: "xl/worksheets/sheet2.xml",
            contents: worksheetXML(
                headers: [
                    "Workspace",
                    "Server",
                    "Host",
                    "Username",
                    "Auth Method",
                    "Private Key",
                    "Public Key",
                    "Passphrase"
                ],
                rows: keyRows
            ),
            to: archive
        )

        return try Data(contentsOf: temporaryURL)
    }

    private static func addEntry(named path: String, contents: String, to archive: Archive) throws {
        let data = Data(contents.utf8)
        guard data.count <= UInt32.max else {
            throw WorkbookError.entryTooLarge(path)
        }

        try archive.addEntry(
            with: path,
            type: .file,
            uncompressedSize: UInt32(data.count),
            compressionMethod: .deflate,
            bufferSize: 4096,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + Int(size), data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            }
        )
    }

    private static func worksheetXML(headers: [String], rows: [[String]]) -> String {
        let allRows = [headers] + rows
        let rowXML = allRows.enumerated()
            .map { index, values in
                worksheetRowXML(rowIndex: index + 1, values: values, columnCount: headers.count)
            }
            .joined(separator: "\n")
        let dimension = "A1:\(columnName(headers.count))\(max(allRows.count, 1))"

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="\(dimension)"/>
          <sheetViews><sheetView workbookViewId="0"/></sheetViews>
          <sheetFormatPr defaultRowHeight="15"/>
          <sheetData>
        \(rowXML)
          </sheetData>
          <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
        </worksheet>
        """
    }

    private static func worksheetRowXML(rowIndex: Int, values: [String], columnCount: Int) -> String {
        let cells = (0..<columnCount)
            .map { columnIndex in
                let value = columnIndex < values.count ? values[columnIndex] : ""
                let reference = "\(columnName(columnIndex + 1))\(rowIndex)"
                return """
                    <c r="\(reference)" t="inlineStr"><is><t xml:space="preserve">\(escapeXML(value))</t></is></c>
                """
            }
            .joined(separator: "\n")

        return """
            <row r="\(rowIndex)">
        \(cells)
            </row>
        """
    }

    private static func columnName(_ index: Int) -> String {
        var index = index
        var name = ""

        while index > 0 {
            let remainder = (index - 1) % 26
            name.insert(Character(UnicodeScalar(65 + remainder)!), at: name.startIndex)
            index = (index - 1) / 26
        }

        return name
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func contentTypesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """
    }

    private static func rootRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
    }

    private static func workbookXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="Connections" sheetId="1" r:id="rId1"/>
            <sheet name="Keys" sheetId="2" r:id="rId2"/>
          </sheets>
        </workbook>
        """
    }

    private static func workbookRelationshipsXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/><scheme val="minor"/></font></fonts>
          <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>
          <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
          <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
          <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>
          <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
          <dxfs count="0"/>
          <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
        </styleSheet>
        """
    }
}
