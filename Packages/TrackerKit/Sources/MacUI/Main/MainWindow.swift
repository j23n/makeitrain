#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers
import WideUI

/// The main window: the wide window's bar and screens, with the Mac's
/// File menu imports and exports, and a background to drag it by.
struct MainWindow: View {
    let model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var importing = false
    @State private var importingEvents = false
    @State private var exporting = false
    @State private var exportDocument: CSVDocument?
    @State private var exportFileName = ""
    @State private var exportError: String?

    var body: some View {
        WideRoot(model: model, leadingInset: 62) {
            Color.clear.frame(width: 60, height: 1)
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(WindowConfigurator())
        .focusedSceneValue(\.fileActions, fileActions)
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName
        ) { result in
            if case .failure(let failure) = result {
                exportError = failure.localizedDescription
            }
        }
        .alert("Couldn't Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .csvImporter(isPresented: $importing, model: model, undoManager: undoManager)
        .sheet(isPresented: $importingEvents) {
            CalendarImportSheet(model: model, undoManager: undoManager)
        }
    }

    private var fileActions: FileActions {
        FileActions(
            importCSV: { importing = true },
            importEvents: { importingEvents = true },
            exportEntries: model.hasFinishedEntries ? { exportEntries() } : nil
        )
    }

    /// Imports or exports as Settings asked, also when it opened the
    /// window to do so. The screens take the other requests.
    private func handle(_ request: AppRequest?) {
        switch request {
        case .importCSV?:
            importing = true
        case .importEvents?:
            importingEvents = true
        case .exportEntries?:
            exportEntries()
        default:
            return
        }
        model.request = nil
    }

    /// Saves every finished entry through the save dialog, with the columns
    /// of a report's export.
    private func exportEntries() {
        guard let csv = model.finishedEntriesCSV() else { return }
        exportDocument = csv.document
        exportFileName = csv.fileName
        exporting = true
    }
}

/// What the File menu does in the focused main window.
struct FileActions {
    /// Picks a CSV file to import.
    let importCSV: () -> Void
    /// Imports events from linked calendars.
    let importEvents: () -> Void
    /// Saves every finished entry as a CSV file, or nil when there's none
    /// yet.
    let exportEntries: (() -> Void)?
}

struct FileActionsKey: FocusedValueKey {
    typealias Value = FileActions
}

extension FocusedValues {
    /// The File menu's actions in the focused main window.
    var fileActions: FileActions? {
        get { self[FileActionsKey.self] }
        set { self[FileActionsKey.self] = newValue }
    }
}

/// File › Import CSV…, Import Calendar Events… and Export CSV….
struct FileCommands: Commands {
    @FocusedValue(\.fileActions) private var actions

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import CSV…") {
                actions?.importCSV()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(actions == nil)
            Button("Import Calendar Events…") {
                actions?.importEvents()
            }
            .disabled(actions == nil)
            Button("Export CSV…") {
                actions?.exportEntries?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(actions?.exportEntries == nil)
        }
    }
}

/// Lets the window be dragged by its background, since the title bar is
/// hidden behind the top bar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

#if DEBUG
#Preview("Week") {
    MainWindow(model: PreviewData.model(PreviewData.freelancerLedger))
        .frame(width: 1280, height: 820)
}

#Preview("No Data") {
    MainWindow(model: PreviewData.model(Ledger()))
        .frame(width: 1280, height: 820)
}
#endif
#endif
