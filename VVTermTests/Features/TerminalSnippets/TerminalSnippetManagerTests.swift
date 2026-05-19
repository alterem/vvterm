import XCTest
@testable import VVTerm

@MainActor
final class TerminalSnippetManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TerminalSnippetManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCreateSnippetPersistsSnippet() throws {
        let manager = TerminalSnippetManager(defaults: defaults)

        let snippet = try manager.createSnippet(
            name: "Deploy",
            content: "npm run deploy",
            description: "Deploy current app",
            sendBehavior: .insert
        )

        XCTAssertEqual(manager.snippets.count, 1)
        XCTAssertEqual(snippet.name, "Deploy")
        XCTAssertEqual(manager.snippets.first?.description, "Deploy current app")

        let reloaded = TerminalSnippetManager(defaults: defaults)
        XCTAssertEqual(reloaded.snippets.count, 1)
        XCTAssertEqual(reloaded.snippets.first?.content, "npm run deploy")
        XCTAssertEqual(reloaded.snippets.first?.sendBehavior, .insert)
    }

    func testUpdateSnippetChangesFields() throws {
        let manager = TerminalSnippetManager(defaults: defaults)
        let snippet = try manager.createSnippet(
            name: "Tail logs",
            content: "tail -f app.log",
            description: "Watch logs",
            sendBehavior: .insert
        )

        let updated = try manager.updateSnippet(
            id: snippet.id,
            name: "Tail prod logs",
            content: "tail -f /var/log/app.log",
            description: "Production log stream",
            sendBehavior: .insertAndEnter
        )

        XCTAssertEqual(updated.name, "Tail prod logs")
        XCTAssertEqual(updated.sendBehavior, .insertAndEnter)
        XCTAssertEqual(manager.snippets.first?.content, "tail -f /var/log/app.log")
        XCTAssertEqual(manager.snippets.first?.description, "Production log stream")
    }

    func testDeleteSnippetHidesSnippetFromActiveList() throws {
        let manager = TerminalSnippetManager(defaults: defaults)
        let snippet = try manager.createSnippet(
            name: "SSH",
            content: "ssh user@host",
            description: "",
            sendBehavior: .insert
        )

        manager.deleteSnippet(id: snippet.id)

        XCTAssertTrue(manager.snippets.isEmpty)
        XCTAssertEqual(manager.webDAVSnapshotLibrary().entries.count, 1)
        XCTAssertEqual(manager.webDAVSnapshotLibrary().entries.first?.deletedAt != nil, true)
    }
}
