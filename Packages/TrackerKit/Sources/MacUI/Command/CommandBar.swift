#if os(macOS)
import AppKit
import SwiftUI
import TrackerCore
import TrackerKit
import WideUI

/// The command line with what it would do under it, and the keys to know:
/// in the menu bar's popover, in the panel the shortcut opens, and in the
/// main window.
struct CommandBar: View {
    let line: CommandLineModel
    var placeholder = "Start, switch, stop or log time"
    var focusesWithWindow = false
    var focusRequest = 0
    /// After a line ran, as for closing the popover.
    var onDone: () -> Void = {}
    /// After Escape with nothing typed.
    var onCancel: () -> Void = {}
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("›")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                CommandField(
                    text: Binding(get: { line.text }, set: { line.text = $0 }),
                    placeholder: placeholder,
                    reading: line.reading,
                    ledger: line.model.ledger,
                    focusesWithWindow: focusesWithWindow,
                    focusRequest: focusRequest,
                    cursorRequest: line.cursorRequest,
                    cursor: line.requestedCursor,
                    onSubmit: submit,
                    onTab: { line.acceptSuggestion() || line.complete() },
                    onUp: { line.moveSuggestion(by: -1) || line.previousLine() },
                    onDown: { line.moveSuggestion(by: 1) || line.nextLine() },
                    onCancel: cancel,
                    onCursorChange: { line.cursor = $0 }
                )
                .frame(height: 24)
                .accessibilityLabel(Text(placeholder))
                KeyCap("esc")
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(height: 54)

            if !line.suggestions.isEmpty {
                SuggestionStrip(suggestions: line.suggestions, highlighted: line.highlightedSuggestion, ledger: line.model.ledger) { index in
                    line.acceptSuggestion(at: index)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            if hasPreview {
                Divider().overlay(Theme.line)
                CommandPreviewView(line: line)
            }
            if !listed.isEmpty {
                Divider().overlay(Theme.line)
                EntryList(model: line.model, entries: listed)
            }
            Divider().overlay(Theme.line)
            hints
        }
    }

    private var hasPreview: Bool {
        line.message != nil || line.preview != nil || (line.reading.problem != nil && !line.text.isEmpty)
    }

    /// What "find" found, or today's entries after Down.
    private var listed: [ResolvedEntry] {
        if case .find? = line.reading.primary {
            return Array(line.found.prefix(12))
        }
        return line.showsToday ? Array(line.todaysEntries.prefix(12)) : []
    }

    private func submit(alternate: Bool) {
        if line.submit(alternate: alternate, undoManager: undoManager), line.model.preferences.closesAfterReturn {
            onDone()
        }
    }

    private func cancel() {
        if line.text.isEmpty && !line.showsToday {
            onCancel()
        } else {
            line.clear()
        }
    }

    /// The keys that do something with what's typed.
    private var hints: some View {
        HStack(spacing: 16) {
            if let completion = line.reading.completion {
                KeyHint("⇥", "\(completion.text), from \(Format.weekday(completion.day))")
                    .lineLimit(1)
            } else if case .addProject? = line.reading.alternate {
                KeyHint("⌥⏎", "add and start")
            } else if line.reading.alternate != nil || line.text.isEmpty {
                KeyHint("⌥⏎", "log as finished")
            }
            if line.text.isEmpty {
                if line.model.running != nil {
                    KeyHint("stop", "stop the timer")
                    KeyHint("from 10:30", "change its start")
                } else {
                    KeyHint("↑", "history")
                    KeyHint("↓", "today's entries")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
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
