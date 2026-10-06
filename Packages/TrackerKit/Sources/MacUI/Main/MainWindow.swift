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
    @State private var importRequest: ImportRequest?
    @State private var importError: String?
    @State private var importingEvents = false

    var body: some View {
        WideRoot(model: model, leadingInset: 62) {
            Color.clear.frame(width: 60, height: 1)
        }
        .frame(minWidth: 960, minHeight: 600)
        .background(WindowConfigurator())
        .exportsEntries(of: model)
        .focusedSceneValue(\.imports, imports)
        .onChange(of: model.request, initial: true) { _, request in
            handle(request)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
            do {
                importRequest = try model.importRequest(forFileAt: result.get())
            } catch {
                importError = error.localizedDescription
            }
        }
        .sheet(item: $importRequest) { request in
            ImportSheet(model: model, request: request, undoManager: undoManager)
        }
        .sheet(isPresented: $importingEvents) {
            CalendarImportSheet(model: model, undoManager: undoManager)
        }
        .alert(
            "Couldn't Import the File",
            isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
        ) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var imports: ImportActions {
        ImportActions {
            importing = true
        } calendar: {
            importingEvents = true
        }
    }

    /// Imports as Settings asked. The screens take the other requests,
    /// and EntriesExport the export.
    private func handle(_ request: AppRequest?) {
        switch request {
        case .importCSV?:
            importing = true
        case .importEvents?:
            importingEvents = true
        default:
            return
        }
        model.request = nil
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
