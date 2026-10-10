#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit

/// The popover under the menu bar item: the running timer, if any, and the
/// command line. Everything else is typed, or in the main window.
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
        .frame(width: 410)
        .background(Theme.popover)
    }

    /// Opening the main window and Settings, and quitting.
    private var footer: some View {
        HStack(spacing: 14) {
            Button("Open Time Tracker") {
                openWindow(id: WindowID.main)
                NSApp.activate()
                close()
            }
            .keyboardShortcut("o")
            SettingsLink {
                Text("Settings…")
            }
            .keyboardShortcut(",")
            #if FEEDBACK
            Button("Feedback…") {
                close()
                Task { await Feedback.center.begin() }
            }
            .disabled(!Feedback.center.isEnabled)
            .accessibilityIdentifier("menuBar.feedback")
            #endif
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 14)
        .frame(height: 30)
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
