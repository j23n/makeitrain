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
    /// When it's saved or dropped, so the screen takes the keyboard back.
    let done: () -> Void
    @State private var line: EntryLineModel
    @State private var focusRequest = 0
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, week: WeekModel, done: @escaping () -> Void) {
        self.model = model
        self.week = week
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
                            EntryLineSuggestions(model: model, line: line)
                        }
                    }
                    EntryLineReading(model: model, line: line)
                    NewEntryOverlap(model: model, week: week, draft: draft)
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
            focusRequest += 1
        }
    }

    /// "Thu 19 · 2:15": the day and how long.
    private func detail(_ draft: NewEntryDraft) -> String {
        "\(Format.weekday(draft.day)) \(draft.day.day) · \(Format.duration(Int64(draft.endSecond - draft.startSecond) * 1000))"
    }

    private var field: some View {
        CommandField(
            entryLine: line,
            fontSize: 13,
            focusRequest: focusRequest,
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
    return NewEntryPanel(model: model, week: week) {}
        .frame(height: 560)
}
#endif
