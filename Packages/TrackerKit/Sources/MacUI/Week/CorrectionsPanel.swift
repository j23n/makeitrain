#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// What needs correcting on the days shown, beside them: a card for each,
/// the selected one with what its suggestion changes, and accepting every
/// suggestion at once.
struct CorrectionsPanel: View {
    let model: AppModel
    let week: WeekModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Corrections")
                        .font(.system(size: 14, weight: .semibold))
                    if !week.previews.isEmpty {
                        Text("\(week.previews.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.markerText)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(Capsule().fill(Theme.marker))
                    }
                }
                Text(week.previews.isEmpty
                    ? "Overlaps, timers left running, entries without a project and calendar events you haven't logged show up here."
                    : "Shown in place on the week. Nothing changes until you accept one.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if week.previews.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.ok)
                    Text("Nothing to correct")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(week.previews) { preview in
                                CorrectionCard(model: model, week: week, preview: preview, selected: preview.id == week.selectedPreview?.id)
                                    .id(preview.id)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .onChange(of: week.selectedCorrection) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                footer
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .overlay(alignment: .leading) {
            Rectangle().fill(Theme.line).frame(width: 1)
        }
    }

    private var footer: some View {
        let suggested = week.corrections.filter { $0.suggestion != nil }.count
        let months = week.monthsChanged.map { "entries/\($0.fileName)" }
        return VStack(alignment: .leading, spacing: 10) {
            if suggested > 0 {
                Button {
                    week.acceptAll(undoManager: undoManager)
                } label: {
                    Text(suggested == week.corrections.count && suggested > 1
                        ? "Accept all \(CorrectionText.number(suggested))"
                        : "Accept the \(CorrectionText.number(suggested)) with a suggestion")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ChoiceButtonStyle())
                .disabled(model.isReadOnly)
                if !months.isEmpty {
                    Text("They change \(months.formatted(.list(type: .and))). One step to undo.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    KeyCap("J")
                    KeyCap("K")
                    Text("move")
                }
                HStack(spacing: 5) {
                    KeyCap("⏎")
                    Text("accept")
                }
                HStack(spacing: 5) {
                    KeyCap("⇥")
                    Text("skip")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }
}

/// One correction: what and when, what's wrong, what the suggestion
/// changes when it's selected, and the fixes to choose from.
struct CorrectionCard: View {
    let model: AppModel
    let week: WeekModel
    let preview: CorrectionPreview
    let selected: Bool
    @Environment(\.undoManager) private var undoManager

    private var correction: Correction { preview.correction }

    var body: some View {
        VStack(alignment: .leading, spacing: selected ? 10 : 8) {
            HStack(spacing: 8) {
                CorrectionMarker(preview.number)
                Text(CorrectionText.label(correction, model: model))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                Spacer(minLength: 4)
            }
            Text(CorrectionText.title(correction, model: model))
                .font(.system(size: selected ? 14 : 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let explanation = CorrectionText.explanation(correction, model: model) {
                Text(explanation)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if selected, !preview.diff.entries.isEmpty {
                ChangeTable(model: model, diff: preview.diff)
            }
            fixes
        }
        .padding(selected ? 14 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.amberWash : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.amber : Theme.line, lineWidth: selected ? 1.5 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            week.selectedCorrection = preview.id
            if let id = correction.entryIDs.first {
                week.selectedEntry = id
            }
        }
    }

    private var fixes: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(correction.fixes.enumerated()), id: \.offset) { index, fix in
                Button {
                    model.apply(fix, undoManager: undoManager)
                    week.reload()
                } label: {
                    HStack(spacing: 9) {
                        Text(CorrectionText.fixTitle(fix, in: correction, model: model))
                        if index == 0, selected {
                            KeyCap("⏎", onInverse: true)
                        }
                    }
                }
                .buttonStyle(ChoiceButtonStyle(suggested: index == 0 && selected, compact: !selected))
                .disabled(model.isReadOnly)
            }
            if case let .noProject(id) = correction.kind {
                Menu("Choose a project…") {
                    ForEach(model.ledger.pickerProjects()) { project in
                        Button(model.ledger.projectTitle(project.id)) {
                            model.apply(.assign(id: id, projectID: project.id), undoManager: undoManager)
                            week.reload()
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isReadOnly)
            }
            Button {
                week.selectedCorrection = preview.id
                week.skipSelected()
            } label: {
                Text("Skip ⇥")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 6)
                    .frame(minHeight: selected ? 32 : 28)
            }
            .buttonStyle(.plain)
            .help("Skipped corrections aren't offered again on this Mac.")
        }
    }
}

/// What a fix changes, entry by entry: "~" for a changed one with its old
/// times struck through, "+" for a new one.
struct ChangeTable: View {
    let model: AppModel
    let diff: LedgerDiff

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 7) {
            ForEach(Array(diff.entries.enumerated()), id: \.offset) { _, change in
                if let after = change.after {
                    GridRow {
                        Text(change.isNew ? "+" : "~")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amberText)
                        Text(after.note.isEmpty ? model.ledger.projectTitle(after.projectID) : after.note)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let before = change.before {
                            Text(span(before))
                                .strikethrough(true, color: Theme.amber)
                                .foregroundStyle(Theme.text3)
                        } else {
                            Text("—").foregroundStyle(Theme.text3)
                        }
                        Text(span(after))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amberText)
                    }
                }
            }
        }
        .font(.system(size: 11.5))
        .monospacedDigit()
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
    }

    private func span(_ entry: TimeEntry) -> String {
        let zone = entry.timeZone
        return "\(Format.time(entry.start, zone: zone))–\(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
    }
}
#endif
