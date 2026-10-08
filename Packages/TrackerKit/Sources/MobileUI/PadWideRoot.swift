#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import WideUI

/// An iPad window wide enough for the Mac's layout: the bar with the zoom
/// and the command line over the week, month, year or projects, with
/// Settings at the end of the bar.
struct PadWideRoot: View {
    let model: AppModel
    @State private var showsSettings = false

    var body: some View {
        WideRoot(model: model) {
            Button {
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text2)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel(Text("Settings"))
        }
        .sheet(isPresented: $showsSettings) {
            PhoneSettings(model: model)
        }
    }
}
#endif
