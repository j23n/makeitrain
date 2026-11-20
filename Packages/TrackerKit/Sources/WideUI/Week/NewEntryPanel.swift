import SwiftUI
import TrackerCore
import TrackerKit

/// A new entry drawn on the week, at the week's side once the drag ends:
/// its line, which starts with the day and times it was drawn with, to
/// finish by typing its project, tags and note, what the line reads as,
/// what it overlaps, and Save and Discard. Return saves it and Escape drops
/// it; nothing is saved until then. Dragging the entry's handles on the
/// grid changes the times in the line.
struct NewEntryPanel: View {
    let model: AppModel
    let week: WeekModel
    /// Bumped by the screen when Return asks for the line again.
    let focusRequest: Int
    /// When it's saved or dropped, so the screen takes the keyboard back.
    let done: () -> Void
    @State private var line: EntryLineModel
    /// Bumped when the panel opens, to give the line the keyboard.
    @State private var opened = 0
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, week: WeekModel, focusRequest: Int, done: @escaping () -> Void) {
        self.model = model
        self.week = week
        self.focusRequest = focusRequest
        self.done = done
        _line = State(initialValue: EntryLineModel(model: model))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let draft = week.newEntry {
                    SidebarTitle(title: "New entry", detail: detail(draft), close: discard)
                    VStack(alignment: .leading, spacing: 10) {
                        field
                        if !line.suggestions.isEmpty {
                            suggestions
                        }
                    }
                    EntryLineReading(model: model, line: line)
                    if let overlap = overlap(draft) {
                        Text(overlap)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    buttons
                }
            }
            .padding(20)
        }
        .sidebarColumn()
        .onChange(of: week.newEntry, initial: true) { _, draft in
            guard let draft else { return }
            if line.newEntry?.id == draft.id {
                line.retime(draft)
            } else {
                line.showNew(draft)
            }
        }
        .task {
            opened += 1
        }
    }

    /// "Thu 19 · 2:15": the day and how long.
    private func detail(_ draft: NewEntryDraft) -> String {
        "\(Format.weekday(draft.day)) \(draft.day.day) · \(Format.duration(Int64(draft.endSecond - draft.startSecond) * 1000))"
    }

    /// What the new entry overlaps, such as "Overlaps Push notifications
    /// from 14:15 to 14:30.", for the first entry it does.
    private func overlap(_ draft: NewEntryDraft) -> String? {
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

    private var field: some View {
        CommandField(
            entryLine: line,
            fontSize: 13,
            focusRequest: focusRequest + opened,
            onSubmit: { save() },
            onCancel: { discard() }
        )
        .frame(height: 20)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(line.refused ? Theme.amber : Theme.accent, lineWidth: 1.5)
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

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: save) {
                HStack(spacing: 8) {
                    Text("Save")
                    KeyCap("⏎", onInverse: true)
                }
            }
            .buttonStyle(ChoiceButtonStyle(suggested: true))
            .disabled(model.isReadOnly || line.parts == nil)
            Button(action: discard) {
                HStack(spacing: 8) {
                    Text("Discard")
                    KeyCap("esc")
                }
            }
            .buttonStyle(ChoiceButtonStyle())
            Spacer(minLength: 0)
        }
    }

    /// Saves the entry as its line says and shows it, chosen.
    private func save() {
        guard let draft = week.newEntry, line.apply(undoManager: undoManager) else { return }
        week.selectedEntry = draft.id
        done()
    }

    private func discard() {
        week.newEntry = nil
        done()
    }
}

#if DEBUG
#Preview("New entry") {
    let model = PreviewData.model()
    let week = WeekModel(model: model, days: ReportPeriod.week.range(containing: model.today, firstWeekday: model.firstWeekday))
    week.newEntry = model.newEntryDraft(on: model.today, startSecond: 9 * 3600, endSecond: 10 * 3600 + 1800)
    return NewEntryPanel(model: model, week: week, focusRequest: 0) {}
        .frame(height: 560)
}
#endif
