#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// Saves the entries as a CSV file, for the File menu.
struct ExportActions {
    /// Saves every finished entry, or nil when there's none yet.
    let csv: (() -> Void)?
}

struct ExportActionsKey: FocusedValueKey {
    typealias Value = ExportActions
}

extension FocusedValues {
    /// Saves the entries of the focused main window.
    var exports: ExportActions? {
        get { self[ExportActionsKey.self] }
        set { self[ExportActionsKey.self] = newValue }
    }
}

extension View {
    /// Offers File › Export CSV…, which saves every finished entry through
    /// the save dialog, with the columns of a report's export.
    func exportsEntries(of model: AppModel) -> some View {
        modifier(EntriesExport(model: model))
    }
}

/// A modifier, so that only it follows the entries to know whether there's
/// anything to save, not the window around it.
struct EntriesExport: ViewModifier {
    let model: AppModel
    @State private var document: CSVDocument?
    @State private var fileName = ""
    @State private var saving = false
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.exports, actions)
            .fileExporter(
                isPresented: $saving,
                document: document,
                contentType: .commaSeparatedText,
                defaultFilename: fileName
            ) { result in
                if case .failure(let failure) = result {
                    error = failure.localizedDescription
                }
            }
            .alert("Couldn't Export", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
    }

    private var actions: ExportActions {
        guard model.resolved.contains(where: { !$0.isRunning }) else {
            return ExportActions(csv: nil)
        }
        return ExportActions(csv: { save() })
    }

    private func save() {
        let entries = model.resolved.filter { !$0.isRunning }
        guard let name = Self.fileName(for: entries) else { return }
        document = CSVDocument(data: CSVExport.data(for: entries, ledger: model.ledger))
        fileName = name
        saving = true
    }

    /// "Time Entries" and the days from the first entry to the last, or nil
    /// when there are no entries.
    static func fileName(for entries: [ResolvedEntry]) -> String? {
        let days = entries.map(\.entry.day)
        guard let first = days.min(), let last = days.max() else { return nil }
        return first == last ? "Time Entries \(first)" : "Time Entries \(first) to \(last)"
    }
}
#endif
