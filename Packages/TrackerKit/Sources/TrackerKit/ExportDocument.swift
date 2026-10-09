import SwiftUI
import UniformTypeIdentifiers

/// A CSV or PDF file for the save dialog. Each exporter says which type
/// it saves.
public struct ExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText, .pdf] }

    public var data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
