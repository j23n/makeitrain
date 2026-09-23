#if os(macOS)
import SwiftUI
import TrackerKit

/// The menu bar item: an icon, plus hours and minutes while a timer runs.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        if let running = model.running {
            Text("\(Image(systemName: "stopwatch.fill")) \(Format.duration(model.duration(of: running)))")
                .monospacedDigit()
        } else {
            Image(systemName: "stopwatch")
        }
    }
}

#if DEBUG
#Preview("Running") {
    MenuBarLabel(model: PreviewData.model())
        .padding()
}

#Preview("Stopped") {
    MenuBarLabel(model: PreviewData.model(PreviewData.stoppedLedger))
        .padding()
}
#endif
#endif
