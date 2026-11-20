import SwiftUI
import TrackerCore
import TrackerKit

/// The selected entry at the side of the week, as the iPhone's entry sheet
/// has it: the corrections about it, such as an overlap, with their fixes,
/// its line to change by typing, what the line reads as, and what else can
/// be done with it. Return applies the line, Escape puts it back, and
/// Escape again closes the panel. Over it, a button goes back to the
/// week's corrections.
struct EntryPanel: View {
    let model: AppModel
    let week: WeekModel
    let entryID: UUID
    /// Changes when the keyboard should go to the line.
    let focusRequest: Int
    /// Selects another entry, as a copy just made.
    let select: (UUID) -> Void
    let close: () -> Void
    @State private var line: EntryLineModel
    @State private var editing = false
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, week: WeekModel, entryID: UUID, focusRequest: Int, select: @escaping (UUID) -> Void, close: @escaping () -> Void) {
        self.model = model
        self.week = week
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
                    if !week.previews.isEmpty {
                        backToCorrections
                    }
                    SidebarTitle(title: Format.fullDay(entry.entry.day), detail: Format.duration(model.duration(of: entry)), close: close)
                    ForEach(week.previews(involving: entryID)) { preview in
                        CorrectionCard(model: model, week: week, preview: preview, selected: true, showsKeys: false)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        field
                        if editing || !line.isUnchanged, !line.suggestions.isEmpty {
                            EntryLineSuggestions(model: model, line: line)
                        }
                    }
                    EntryLineReading(model: model, line: line)
                    if !line.isUnchanged {
                        changeButtons
                    }
                    EntryActions(model: model, entry: entry) { action in
                        switch action {
                        case let .duplicated(copy):
                            select(copy)
                        case .deleted:
                            close()
                        case .stopped, .continued, .split:
                            break
                        }
                    }
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

    /// Back to the week's corrections, with how many there are.
    private var backToCorrections: some View {
        Button(action: close) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                Text("Corrections")
                Text("\(week.previews.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.markerText)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(Theme.marker))
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show the week's corrections (J, K)")
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

    private func apply() {
        if line.apply(undoManager: undoManager) {
            line.revert()
        }
    }
}
