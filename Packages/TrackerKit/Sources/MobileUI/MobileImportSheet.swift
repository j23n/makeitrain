#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Shows what importing a CSV file adds, and adds it.
struct MobileImportSheet: View {
    let model: AppModel
    let request: ImportRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let count = request.plan.entries.count
        NavigationStack {
            Form {
                ImportSummary(plan: request.plan, ledger: model.ledger)
            }
            .navigationTitle(request.fileName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        model.importEntries(request.plan, undoManager: undoManager)
                        dismiss()
                    }
                    .disabled(count == 0 || model.isReadOnly)
                }
            }
        }
    }
}
#endif
