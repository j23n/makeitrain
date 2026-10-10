#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit
import WideUI

/// The running timer and the command line, with what the line would do
/// under it and the keys to know: in the menu bar's popover and in the
/// panel the shortcut opens. The main window's line shows the same under
/// it. It's disabled while the data is read-only.
struct CommandBar: View {
    let line: CommandLineModel
    /// After a line ran, or Escape with nothing typed, as for closing the
    /// popover.
    let close: () -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            if let running = line.model.running {
                RunningHeader(model: line.model, running: running)
                Divider().overlay(Theme.line)
            }
            HStack(spacing: 10) {
                Text("›")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                CommandField(
                    line: line,
                    placeholder: CommandText.placeholder,
                    focusesWithWindow: true,
                    onSubmit: submit,
                    onCancel: cancel
                )
                .frame(height: 24)
                .accessibilityLabel(Text(CommandText.placeholder))
                KeyCap("esc")
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 54)
            CommandDetails(line: line)
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

    private func cancel() {
        if line.cancel() {
            close()
        }
    }
}

/// The running timer above the command line: its time, project and note,
/// and Stop.
struct RunningHeader: View {
    let model: AppModel
    let running: ResolvedEntry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Theme.now)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(Format.duration(model.duration(of: running)))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
            ProjectName(ledger: model.ledger, projectID: running.entry.projectID, weight: .semibold)
                .fixedSize()
            Text(running.entry.note)
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                model.stopTimer(undoManager: undoManager)
            } label: {
                HStack(spacing: 7) {
                    Text("Stop")
                    Text("⌘.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                .font(.system(size: 12.5))
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.strongLine))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .disabled(model.isReadOnly)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 44)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Running: \(model.ledger.projectTitle(running.entry.projectID)), \(Format.duration(model.duration(of: running)))"))
    }
}
#endif
