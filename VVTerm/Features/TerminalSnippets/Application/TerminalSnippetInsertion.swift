import Foundation

enum TerminalSnippetInsertion {
    @MainActor
    static func insertIntoCurrentSession(_ snippet: TerminalSnippetEntry, sessionId: UUID) {
        ConnectionSessionManager.shared.sendText(snippet.content, to: sessionId)
        guard snippet.sendBehavior == .insertAndEnter else { return }
        ConnectionSessionManager.shared.sendText("\n", to: sessionId)
    }

    @MainActor
    static func insertIntoCurrentPane(_ snippet: TerminalSnippetEntry, paneId: UUID) {
        guard let terminal = TerminalTabManager.shared.getTerminal(for: paneId) else { return }
        terminal.sendText(snippet.content)
        guard snippet.sendBehavior == .insertAndEnter else { return }
        terminal.sendText("\n")
    }
}
