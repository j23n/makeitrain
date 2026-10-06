import SwiftUI
import UniformTypeIdentifiers

/// A CSV file for the save dialog.
public struct CSVDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.commaSeparatedText] }

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
