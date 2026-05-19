import XCTest
@testable import VVTerm

@MainActor
final class ServerImportManagerTests: XCTestCase {
    func testParseVVTermWorkbookBuildsServerAndKeyData() throws {
        let connectionRows = [[
            "Ops",
            "Production",
            "Prod API",
            "prod.example.com",
            "22",
            "root",
            "super-secret",
            "SSH Key + Passphrase",
            "SSH",
            "primary, api",
            "important"
        ]]
        let keyRows = [[
            "Ops",
            "Prod API",
            "prod.example.com",
            "root",
            "SSH Key + Passphrase",
            "PRIVATE KEY",
            "PUBLIC KEY",
            "passphrase"
        ]]
        let data = try ServerExportWorkbookBuilder.makeWorkbookData(
            connectionRows: connectionRows,
            keyRows: keyRows
        )

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xlsx")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let preview = try ServerImportManager.shared.previewVVTermExcelImport(from: tempURL)

        XCTAssertEqual(preview.items.count, 1)
        let item = try XCTUnwrap(preview.items.first)
        XCTAssertEqual(item.workspaceName, "Ops")
        XCTAssertEqual(item.server.environment, .production)
        XCTAssertEqual(item.server.name, "Prod API")
        XCTAssertEqual(item.server.host, "prod.example.com")
        XCTAssertEqual(item.server.username, "root")
        XCTAssertEqual(item.server.authMethod, .sshKeyWithPassphrase)
        XCTAssertEqual(item.server.tags, ["primary", "api"])
        XCTAssertEqual(item.server.notes, "important")
        XCTAssertEqual(String(data: try XCTUnwrap(item.credentials.privateKey), encoding: .utf8), "PRIVATE KEY")
        XCTAssertEqual(String(data: try XCTUnwrap(item.credentials.publicKey), encoding: .utf8), "PUBLIC KEY")
        XCTAssertEqual(item.credentials.passphrase, "passphrase")
        XCTAssertEqual(item.credentials.password, "super-secret")
    }

    func testParseSecureCRTSessionsDirectoryBuildsRecordsFromNestedIniFiles() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let groupURL = rootURL.appendingPathComponent("Production", isDirectory: true)
        try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let fileURL = groupURL.appendingPathComponent("Bastion.ini")
        let content = """
        S:"Protocol Name"=SSH2
        S:"Hostname"=bastion.example.com
        S:"Username"=admin
        D:"[SSH2] Port"=2222
        S:"Identity Filename V2"=/Users/demo/.ssh/id_ed25519
        """
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let preview = try ServerImportManager.shared.previewSecureCRTImport(fromSessionsDirectory: rootURL)

        XCTAssertEqual(preview.items.count, 1)
        let item = try XCTUnwrap(preview.items.first)
        XCTAssertEqual(item.source, .secureCRT)
        XCTAssertEqual(item.workspaceName, "Production")
        XCTAssertEqual(item.server.name, "Bastion")
        XCTAssertEqual(item.server.host, "bastion.example.com")
        XCTAssertEqual(item.server.port, 2222)
        XCTAssertEqual(item.server.username, "admin")
        XCTAssertEqual(item.server.authMethod, .sshKey)
        XCTAssertEqual(item.server.environment, .production)
    }
}
