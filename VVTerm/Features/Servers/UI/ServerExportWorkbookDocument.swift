import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let vvtermExcelWorkbook = UTType(filenameExtension: "xlsx") ?? .spreadsheet
}

struct ServerExportWorkbookDocument: FileDocument {
    static let contentType: UTType = .vvtermExcelWorkbook
    static var readableContentTypes: [UTType] { [contentType] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
