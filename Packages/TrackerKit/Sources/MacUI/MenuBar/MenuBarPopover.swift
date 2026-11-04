#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The popover under the menu bar item: the running timer, if any, the
/// command line, and today's time. Everything else is typed, or in the main
/// window.
struct MenuBarPopover: View {
    let model: AppModel
    @State private var line: CommandLineModel
    @Environment(\.openWindow) private var openWindow

    init(model: AppModel) {
        self.model = model
        _line = State(initialValue: CommandLineModel(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            Notices(model: model)
            CommandBar(line: line, close: close)
            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 380)
        .background(Theme.popover)
    }

    /// Today's time, and opening the main window and Settings, and
    /// quitting. The keys are in each button's help.
    private var footer: some View {
        HStack(spacing: 2) {
            TodayTotal(model: model)
            Spacer(minLength: 8)
            iconButton("macwindow", "Open Time Tracker (⌘O)", label: "Open Time Tracker") {
                openWindow(id: WindowID.main)
                NSApp.activate()
                close()
            }
            .keyboardShortcut("o")
            SettingsLink {
                icon("gearshape")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",")
            .help("Settings… (⌘,)")
            .accessibilityLabel(Text("Settings"))
            #if FEEDBACK
            iconButton("bubble.left", "Feedback…", label: "Feedback") {
                close()
                Task { await Feedback.center.begin() }
            }
            .disabled(!Feedback.center.isEnabled)
            .accessibilityIdentifier("menuBar.feedback")
            #endif
            iconButton("power", "Quit (⌘Q)", label: "Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 40)
    }

    private func iconButton(_ systemImage: String, _ help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon(systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(label))
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 13))
            .foregroundStyle(Theme.text2)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
    }

    private func close() {
        line.clear()
        NSApp.keyWindow?.close()
    }
}

#if DEBUG
#Preview("Running") {
    MenuBarPopover(model: PreviewData.model())
}

#Preview("Stopped") {
    MenuBarPopover(model: PreviewData.model(PreviewData.stoppedLedger))
}

#Preview("No Data") {
    MenuBarPopover(model: PreviewData.model(Ledger()))
}
#endif
#endif
