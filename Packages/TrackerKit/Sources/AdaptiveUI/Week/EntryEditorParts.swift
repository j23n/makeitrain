import SwiftUI
import TrackerCore
import TrackerKit

// The parts of an entry's editor that the wide layout's sidebar and the
// narrow layout's sheet both show: what the line reads as, what could take
// the word being typed, and what else can be done with the entry.

/// What an entry's line reads as: its day, times, project, tags and note,
/// or why it isn't an entry. The wide layout's sidebar has a part to a row;
/// the narrow layout's sheet has them on one line, a part the line leaves
/// out showing as what could go there.
struct EntryLineReading: View {
    let model: AppModel
    let line: EntryLineModel
    var compact = false

    var body: some View {
        if compact {
            EntryLineGuide(model: model, line: line)
        } else if let parts = line.parts {
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
        guard let end = parts.end else { return "from \(Format.time(parts.start, zone: parts.zone))" }
        return "\(Format.span(parts.start, end, zone: parts.zone)) · \(Format.duration(parts.start.distance(to: end)))"
    }
}

/// What an entry's line reads as on one line, for the narrow layout: its
/// day, times, project, tags and note. A part the line leaves out shows as
/// what could go there, and a line that isn't an entry says why.
private struct EntryLineGuide: View {
    let model: AppModel
    let line: EntryLineModel

    var body: some View {
        if let parts = line.parts {
            HStack(spacing: 6) {
                Text(Format.day(parts.start.local(in: parts.zone).date))
                separator
                Text(times(parts))
                    .monospacedDigit()
                separator
                if let projectID = parts.draft.projectID {
                    HStack(spacing: 4) {
                        TintDot(model.ledger.tint(ofProject: projectID), size: 7)
                        Text(model.ledger.projectTitle(projectID))
                    }
                } else {
                    placeholder("project")
                }
                separator
                if parts.draft.tags.isEmpty {
                    placeholder("#tag")
                } else {
                    Text(parts.draft.tags.map(Tags.typed).joined(separator: " "))
                        .foregroundStyle(Theme.tag)
                }
                separator
                if parts.draft.note.isEmpty {
                    placeholder("note")
                } else {
                    Text(parts.draft.note)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .lineLimit(1)
        } else if let problem = line.problem {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Theme.amber)
                Text(problem)
                    .foregroundStyle(line.refused ? Theme.amberText : Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
        }
    }

    private var separator: some View {
        Text("·").foregroundStyle(Theme.text3)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.text3)
    }

    /// "13:30–16:30, 3:00", or "from 13:30" while it runs.
    private func times(_ parts: EntryLineParts) -> String {
        guard let end = parts.end else { return "from \(Format.time(parts.start, zone: parts.zone))" }
        return "\(Format.span(parts.start, end, zone: parts.zone)), \(Format.duration(parts.start.distance(to: end)))"
    }
}

/// What could replace the word being typed in an entry's line: Tab takes
/// the highlighted one, Up and Down move the highlight, and a click or tap
/// takes any. The wide layout wraps them; the narrow one has a strip that
/// scrolls sideways, without the keys.
struct EntryLineSuggestions: View {
    let model: AppModel
    let line: EntryLineModel
    var compact = false

    var body: some View {
        if compact {
            SuggestionStrip(suggestions: line.suggestions, ledger: model.ledger, showsKeys: false) { index in
                line.acceptSuggestion(at: index)
            }
        } else {
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
    }
}

/// What an entry's actions did, for the editor around them to follow: the
/// sidebar shows a copy just made, and the sheet closes.
enum EntryAction {
    case stopped, continued, split, deleted
    case duplicated(UUID)
}

/// What else can be done with an entry, a row each: Stop it, or Continue it
/// now and Duplicate it, Split it in the middle, and Delete it. The rows
/// are taller in the narrow layout, for a finger.
struct EntryActions: View {
    let model: AppModel
    let entry: ResolvedEntry
    var compact = false
    /// After an action, with what it did.
    let done: (EntryAction) -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            if entry.isRunning {
                row("Stop", systemImage: "stop.fill") {
                    model.stopTimer(undoManager: undoManager)
                    done(.stopped)
                }
            } else {
                row("Continue it now", systemImage: "play.fill") {
                    model.continueEntry(entry, undoManager: undoManager)
                    done(.continued)
                }
                row("Duplicate", systemImage: "plus.square.on.square") {
                    if let copy = model.duplicateEntry(entry.id, undoManager: undoManager) {
                        done(.duplicated(copy))
                    }
                }
            }
            if EntrySplit.time(for: entry, now: model.now) != nil {
                row("Split in the middle", systemImage: "scissors") {
                    model.splitInMiddle(entry, undoManager: undoManager)
                    done(.split)
                }
            }
            row("Delete", systemImage: "trash", destructive: true) {
                model.deleteEntry(entry.id, undoManager: undoManager)
                done(.deleted)
            }
        }
        .background(RoundedRectangle(cornerRadius: compact ? 14 : 10).fill(compact ? Theme.panel : Theme.card))
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 10))
        .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 10).strokeBorder(Theme.line))
        .disabled(model.isReadOnly)
    }

    private func row(_ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: compact ? 12 : 10) {
                Image(systemName: systemImage)
                    .frame(width: compact ? 22 : 18)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: compact ? 15 : 13))
            .foregroundStyle(destructive ? Theme.now : Theme.text)
            .padding(.horizontal, compact ? 14 : 12)
            .frame(minHeight: compact ? 48 : 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

/// What a new entry being drawn overlaps, such as "Overlaps Push
/// notifications from 14:15 to 14:30.", for the first entry it does.
struct NewEntryOverlap: View {
    let model: AppModel
    let week: WeekModel
    let draft: NewEntryDraft
    var compact = false

    var body: some View {
        if let text = Self.text(for: draft, model: model, week: week) {
            Text(text)
                .font(.system(size: compact ? 13 : 12.5))
                .foregroundStyle(Theme.amberText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func text(for draft: NewEntryDraft, model: AppModel, week: WeekModel) -> String? {
        let blocks = DayLayout.blocks(on: draft.day, entries: week.entries(on: draft.day), now: model.now)
        for block in blocks {
            let from = max(draft.startSecond, block.startSecond)
            let to = min(draft.endSecond, block.endSecond)
            if from < to {
                return "Overlaps \(model.ledger.title(of: block.entry.entry)) from \(Format.time(secondOfDay: from)) to \(Format.time(secondOfDay: to))."
            }
        }
        return nil
    }
}
