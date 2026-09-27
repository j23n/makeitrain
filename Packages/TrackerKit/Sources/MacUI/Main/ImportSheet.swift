#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Shows what importing a CSV file adds, and adds it.
struct ImportSheet: View {
    let model: AppModel
    let request: ImportRequest
    /// The main window's, so the import undoes there.
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let count = request.plan.entries.count
        VStack(spacing: 0) {
            Text("Import \u{201C}\(request.fileName)\u{201D}")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.top, .horizontal], 20)
            Form {
                ImportSummary(plan: request.plan, ledger: model.ledger)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(count == 1 ? "Import 1 Entry" : "Import \(count) Entries") {
                    model.importEntries(request.plan, undoManager: undoManager)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0 || model.isReadOnly)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 540, height: 460)
    }
}

/// Opens the CSV import, for the File menu.
struct ImportAction {
    let open: () -> Void
}

struct ImportActionKey: FocusedValueKey {
    typealias Value = ImportAction
}

extension FocusedValues {
    /// Opens the CSV import in the focused main window.
    var importCSV: ImportAction? {
        get { self[ImportActionKey.self] }
        set { self[ImportActionKey.self] = newValue }
    }
}

/// File › Import CSV….
struct ImportCommands: Commands {
    @FocusedValue(\.importCSV) private var importCSV

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import CSV…") {
                importCSV?.open()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(importCSV == nil)
        }
    }
}

#if DEBUG
#Preview("Import") {
    let csv = """
    start,end,client,project,tags,note
    2026-09-24T09:00:00+02:00,2026-09-24T10:30:00+02:00,Acme,Website redesign,design,Review
    2026-09-24T11:00:00+02:00,2026-09-24T12:00:00+02:00,Initech,Consulting,,Kickoff
    2026-09-23T09:00:00+02:00,2026-09-23T10:30:00+02:00,Acme,Website redesign,client-call,Kickoff with the new team
    """
    let model = PreviewData.model()
    let plan = try! model.importPlan(for: Data(csv.utf8))
    return ImportSheet(model: model, request: ImportRequest(fileName: "toggl-september.csv", plan: plan), undoManager: nil)
}
#endif
#endif
