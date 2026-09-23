#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The main window.
struct MainWindow: View {
    let model: AppModel

    var body: some View {
        List(model.resolved.reversed()) { entry in
            HStack {
                ProjectLabel(ledger: model.ledger, projectID: entry.entry.projectID)
                Text(entry.entry.note)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Format.duration(model.duration(of: entry)))
                    .monospacedDigit()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
#endif
