import Foundation

enum TerminalSnippetValidationError: LocalizedError {
    case snippetLimitReached
    case emptyName
    case emptyContent
    case snippetNotFound

    var errorDescription: String? {
        switch self {
        case .snippetLimitReached:
            return String(
                format: String(localized: "You can create up to %lld code blocks."),
                Int64(TerminalSnippetLibrary.maxEntries)
            )
        case .emptyName:
            return String(localized: "Enter a name for this code block.")
        case .emptyContent:
            return String(localized: "Enter code content before saving.")
        case .snippetNotFound:
            return String(localized: "This code block could not be found.")
        }
    }
}
