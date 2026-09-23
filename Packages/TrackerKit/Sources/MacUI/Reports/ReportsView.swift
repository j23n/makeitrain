#if os(macOS)
import SwiftUI
import TrackerKit

/// Totals for a range of days, with a chart and CSV export.
struct ReportsView: View {
    let model: AppModel

    var body: some View {
        ContentUnavailableView("Reports", systemImage: "chart.bar.xaxis", description: Text("Coming in a later build."))
    }
}
#endif
