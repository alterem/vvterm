import Foundation

struct ServerImportPreview {
    let items: [ImportedServerRecord]
}

struct ImportedServerRecord: Identifiable {
    let id = UUID()
    let source: ServerImportSource
    let workspaceName: String
    let folderPath: [String]
    let server: Server
    let credentials: ServerCredentials
}

enum ServerImportSource: String, Hashable {
    case vvtermExcel
    case secureCRT
}

struct ServerImportResult {
    let importedCount: Int
    let workspaceCount: Int
    let skippedCount: Int
}
