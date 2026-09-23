#if os(macOS)
import SwiftUI
import TrackerKit

/// A day's entries as blocks on a timeline.
struct DayTimelineScreen: View {
    let model: AppModel

    var body: some View {
        ContentUnavailableView("Timeline", systemImage: "calendar.day.timeline.left", description: Text("Coming in a later build."))
    }
}
#endif
