import SwiftUI
import TrackerCore
import TrackerKit

/// The selected entry at the side of the week, as the iPhone's entry sheet
/// has it: its line to change by typing, what the line reads as, and what
/// else can be done with it. Return applies the line, Escape puts it back,
/// and Escape again closes the panel.
struct EntryPanel: View {
    let model: AppModel
    let entryID: UUID
    /// Changes when the keyboard should go to the line.
    let focusRequest: Int
    /// Selects another entry, as a copy just made.
    let select: (UUID) -> Void
    let close: () -> Void
    @State private var line: EntryLineModel
    @State private var editing = false
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, entryID: UUID, focusRequest: Int, select: @escaping (UUID) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.entryID = entryID
        self.focusRequest = focusRequest
        self.select = select
        self.close = close
        _line = State(initialValue: EntryLineModel(model: model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let entry = line.entry {
                    SidebarTitle(title: Format.fullDay(entry.entry.day), detail: Format.duration(model.duration(of: entry)), close: close)
                    VStack(alignment: .leading, spacing: 10) {
                        field
                        if editing || !line.isUnchanged, !line.suggestions.isEmpty {
                            suggestions
                        }
                    }
                    EntryLineReading(model: model, line: line)
                    if !line.isUnchanged {
                        changeButtons
                    }
                    actions(entry)
                }
            }
            .padding(20)
        }
        .sidebarColumn()
        .onChange(of: entryID, initial: true) {
            line.show(entryID)
        }
        .onChange(of: model.revision) {
            if !editing {
                line.revert()
            }
        }
    }

    private var field: some View {
        CommandField(
            entryLine: line,
            fontSize: 13,
            focusRequest: focusRequest,
            onSubmit: { apply() },
            onCancel: {
                if line.isUnchanged {
                    close()
                } else {
                    line.revert()
                }
            },
            onFocusChange: { editing = $0 }
        )
        .frame(height: 20)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(line.refused ? Theme.amber : editing ? Theme.accent : Theme.strongLine, lineWidth: editing || line.refused ? 1.5 : 1)
        )
        .disabled(model.isReadOnly)
    }

    /// What could replace the word being typed: Tab takes the highlighted
    /// one, Up and Down move the highlight, and a click takes any.
    private var suggestions: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(line.suggestions.chips(ledger: model.ledger).enumerated()), id: \.offset) { index, chip in
                Button {
                    line.acceptSuggestion(at: index)
                } label: {
                    ChipLabel(chip)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Apply and Revert, while the line says something else than the entry.
    private var changeButtons: some View {
        HStack(spacing: 8) {
            Button(action: apply) {
                HStack(spacing: 8) {
                    Text("Apply")
                    KeyCap("⏎", onInverse: true)
                }
            }
            .buttonStyle(ChoiceButtonStyle(suggested: true))
            .disabled(model.isReadOnly || line.parts == nil)
            Button {
                line.revert()
            } label: {
                HStack(spacing: 8) {
                    Text("Revert")
                    KeyCap("esc")
                }
            }
            .buttonStyle(ChoiceButtonStyle())
            Spacer(minLength: 0)
        }
    }

    /// What else can be done with the entry, as on iPhone.
    private func actions(_ entry: ResolvedEntry) -> some View {
        VStack(spacing: 0) {
            if entry.isRunning {
                row("Stop", systemImage: "stop.fill") {
                    model.stopTimer(undoManager: undoManager)
                }
            } else {
                row("Continue it now", systemImage: "play.fill") {
                    model.startTimer(EntryDraft(entry.entry), undoManager: undoManager)
                }
                row("Duplicate", systemImage: "plus.square.on.square") {
                    if let copy = model.duplicateEntries([entry.id], undoManager: undoManager).first {
                        select(copy)
                    }
                }
            }
            if EntrySplit.range(of: entry, now: model.now) != nil {
                row("Split in the middle", systemImage: "scissors") {
                    model.splitEntry(entry.id, at: Timestamp(EntrySplit.suggestedTime(for: entry, now: model.now)), undoManager: undoManager)
                }
            }
            row("Delete", systemImage: "trash", destructive: true) {
                model.deleteEntries([entry.id], undoManager: undoManager)
                close()
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line))
        .disabled(model.isReadOnly)
    }

    private func row(_ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .foregroundStyle(destructive ? Theme.now : Theme.text)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func apply() {
        if line.apply(undoManager: undoManager) {
            line.revert()
        }
    }
}

/// What an entry's line reads as, a part to a row: its day, times, project,
/// tags and note, or why it isn't an entry.
struct EntryLineReading: View {
    let model: AppModel
    let line: EntryLineModel

    var body: some View {
        if let parts = line.parts {
            VStack(alignment: .leading, spacing: 7) {
                row("Day") {
                    Text(Format.fullDay(parts.start.local(in: parts.zone).date))
                }
                row("Time") {
                    Text(times(parts))
                        .monospacedDigit()
                }
                row("Project") {
                    if let projectID = parts.draft.projectID {
                        HStack(spacing: 6) {
                            TintDot(model.ledger.tint(ofProject: projectID), size: 8)
                            Text(model.ledger.projectTitle(projectID))
                        }
                    } else {
                        dash
                    }
                }
                row("Tags") {
                    if parts.draft.tags.isEmpty {
                        dash
                    } else {
                        Text(parts.draft.tags.map(Tags.typed).joined(separator: " "))
                            .foregroundStyle(Theme.tag)
                    }
                }
                row("Note") {
                    if parts.draft.note.isEmpty {
                        dash
                    } else {
                        Text(parts.draft.note)
                    }
                }
            }
            .font(.system(size: 12.5))
        } else if let problem = line.problem {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.amber)
                Text(problem)
                    .foregroundStyle(line.refused ? Theme.amberText : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12.5))
        }
    }

    /// A part the line leaves out.
    private var dash: some View {
        Text("—").foregroundStyle(Theme.text3)
    }

    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .foregroundStyle(Theme.text3)
                .frame(width: 56, alignment: .leading)
            value()
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "13:30–16:30 · 3:00", or "from 13:30" while it runs.
    private func times(_ parts: EntryLineParts) -> String {
        let start = Format.time(parts.start, zone: parts.zone)
        guard let end = parts.end else { return "from \(start)" }
        return "\(start)–\(Format.time(end, zone: parts.zone)) · \(Format.duration(parts.start.distance(to: end)))"
    }
}
