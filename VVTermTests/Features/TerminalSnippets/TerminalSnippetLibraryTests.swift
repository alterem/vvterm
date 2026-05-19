import XCTest
@testable import VVTerm

final class TerminalSnippetLibraryTests: XCTestCase {
    func testMergedKeepsNewestEntryVersion() {
        let snippetID = UUID()
        let local = TerminalSnippetLibrary(
            schemaVersion: 1,
            entries: [
                TerminalSnippetEntry(
                    id: snippetID,
                    name: "Local",
                    content: "echo local",
                    description: "local version",
                    sendBehavior: .insert,
                    updatedAt: Date(timeIntervalSince1970: 10)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 10),
            lastWriterDeviceId: "local-device"
        )

        let remote = TerminalSnippetLibrary(
            schemaVersion: 1,
            entries: [
                TerminalSnippetEntry(
                    id: snippetID,
                    name: "Remote",
                    content: "echo remote",
                    description: "remote version",
                    sendBehavior: .insertAndEnter,
                    updatedAt: Date(timeIntervalSince1970: 20)
                )
            ],
            updatedAt: Date(timeIntervalSince1970: 20),
            lastWriterDeviceId: "remote-device"
        )

        let merged = TerminalSnippetLibrary.merged(local: local, remote: remote)

        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(merged.entries.first?.name, "Remote")
        XCTAssertEqual(merged.entries.first?.content, "echo remote")
        XCTAssertEqual(merged.entries.first?.sendBehavior, .insertAndEnter)
    }
}
