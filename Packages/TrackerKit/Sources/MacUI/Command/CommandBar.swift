#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit
import WideUI

/// The running timer and the command line, with what the line would do
/// under it: in the menu bar's popover and in the panel the shortcut opens.
/// The main window's line shows the same under it. It's disabled while the
/// data is read-only.
struct CommandBar: View {
    let line: CommandLineModel
    /// After a line ran, or Escape with nothing typed, as for closing the
    /// popover.
    let close: () -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            if let running = line.model.running {
                RunningCard(model: line.model, running: running)
                Divider().overlay(Theme.line)
            }
            HStack(spacing: 10) {
                Text("›")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                CommandField(
                    line: line,
                    placeholder: CommandText.placeholder,
                    fontSize: 14,
                    focusesWithWindow: true,
                    onSubmit: submit,
                    onCancel: cancel
                )
                .frame(height: 24)
                .accessibilityLabel(Text(CommandText.placeholder))
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            CommandDetails(
                line: line,
                submit: { submit(alternate: $0) },
                startAgain: startAgain
            )
        }
        .disabled(line.model.isReadOnly)
        .onChange(of: line.model.revision) {
            line.refresh()
        }
    }

    private func submit(alternate: Bool) {
        if line.submitClosing(alternate: alternate, undoManager: undoManager) {
            close()
        }
    }

    private func startAgain(_ entry: ResolvedEntry) {
        if line.startAgainClosing(entry, undoManager: undoManager) {
            close()
        }
    }

    private func cancel() {
        if line.cancel() {
            close()
        }
    }
}
#endif
