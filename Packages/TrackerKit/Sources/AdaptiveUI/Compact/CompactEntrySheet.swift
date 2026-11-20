import SwiftUI
import TrackerCore
import TrackerKit

/// An entry as a line to change by typing, such as "2 oct 13:30-16:30
/// web #12 Fix login", and what else can be done with it. Over the line
/// are the corrections about the entry, such as an overlap, with their
/// fixes.
struct CompactEntrySheet: View {
    let model: AppModel
    let week: WeekModel
    let entryID: UUID
    @State private var line: EntryLineModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, week: WeekModel, entryID: UUID) {
        self.model = model
        self.week = week
        self.entryID = entryID
        _line = State(initialValue: EntryLineModel(model: model))
    }

    private var entry: ResolvedEntry? {
        model.resolved.first { $0.id == entryID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                } else {
                    Text("This entry was deleted.")
                        .foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.background)
            .navigationTitle(entry.map { Format.day($0.entry.day) } ?? "Entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: apply)
                        .disabled(model.isReadOnly || line.isUnchanged)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            line.show(entryID)
        }
    }

    private func content(_ entry: ResolvedEntry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(week.previews(involving: entryID)) { preview in
                    CompactEntryCorrection(model: model, week: week, preview: preview) {
                        line.revert()
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CommandField(
                            entryLine: line,
                            fontSize: 15,
                            focusesWithWindow: week.previews(involving: entryID).isEmpty,
                            onSubmit: { apply() },
                            onCancel: { dismiss() }
                        )
                        .frame(height: 44)
                        Text(Format.duration(model.duration(of: entry)))
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text2)
                    }
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line.refused ? Theme.amber : Theme.strongLine))
                    if !line.suggestions.isEmpty {
                        EntryLineSuggestions(model: model, line: line, compact: true)
                    }
                    EntryLineReading(model: model, line: line, compact: true)
                }
                EntryActions(model: model, entry: entry, compact: true) { _ in
                    dismiss()
                }
            }
            .padding(16)
        }
    }

    private func apply() {
        guard entry != nil else { return }
        if line.apply(undoManager: undoManager) {
            dismiss()
        }
    }
}

/// A correction about an entry, in the entry's sheet: what's wrong, such as
/// an overlap, and its fixes, the likeliest first.
struct CompactEntryCorrection: View {
    let model: AppModel
    let week: WeekModel
    let preview: CorrectionPreview
    /// After a fix, so the sheet's line shows the entry as it is now.
    let applied: () -> Void
    @Environment(\.undoManager) private var undoManager

    private var correction: Correction { preview.correction }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                CorrectionMarker(preview.number)
                Text(CorrectionText.label(correction, model: model))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.amberText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Skip") {
                    week.skip(preview.id)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.text2)
            }
            Text(CorrectionText.title(correction, model: model))
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(correction.fixes.enumerated()), id: \.offset) { index, fix in
                Button {
                    apply(fix)
                } label: {
                    Text(CorrectionText.fixTitle(fix, in: correction, model: model))
                        .font(.system(size: 15, weight: index == 0 ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(index == 0 ? Theme.inverseText : Theme.text)
                        .background(RoundedRectangle(cornerRadius: 12).fill(index == 0 ? Theme.inverse : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(index == 0 ? Color.clear : Theme.strongLine))
                }
                .buttonStyle(.plain)
            }
            if case let .noProject(id) = correction.kind {
                Menu("Choose a project") {
                    ForEach(model.ledger.pickerProjects()) { project in
                        Button(model.ledger.projectTitle(project.id)) {
                            apply(.assign(id: id, projectID: project.id))
                        }
                    }
                }
                .font(.system(size: 15))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.amberWash))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.amber, lineWidth: 1.5))
        .disabled(model.isReadOnly)
    }

    private func apply(_ fix: CorrectionFix) {
        week.apply(fix, undoManager: undoManager)
        applied()
    }
}

/// A new entry drawn on the day's grid, as a line to finish by typing, such
/// as "19 nov 15:00-16:30 " and then its project, tags and note. It opens
/// at half height, so the entry stays in sight above it and its handles can
/// still be dragged, which changes the times in the line. Save adds it;
/// Cancel, or closing the sheet, drops it.
struct CompactNewEntrySheet: View {
    let model: AppModel
    let week: WeekModel
    @State private var line: EntryLineModel
    @Environment(\.undoManager) private var undoManager

    init(model: AppModel, week: WeekModel) {
        self.model = model
        self.week = week
        _line = State(initialValue: EntryLineModel(model: model))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    CommandField(
                        entryLine: line,
                        fontSize: 15,
                        focusesWithWindow: true,
                        onSubmit: { save() },
                        onCancel: { week.newEntry = nil }
                    )
                    .frame(height: 44)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.field))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line.refused ? Theme.amber : Theme.accent, lineWidth: 1.5))
                    if !line.suggestions.isEmpty {
                        EntryLineSuggestions(model: model, line: line, compact: true)
                    }
                    EntryLineReading(model: model, line: line, compact: true)
                    if let draft = week.newEntry {
                        NewEntryOverlap(model: model, draft: draft, compact: true)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("New entry")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        week.newEntry = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.isReadOnly || line.parts == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onChange(of: week.newEntry, initial: true) { _, draft in
            guard let draft else { return }
            if line.newEntry?.id == draft.id {
                line.retime(draft)
            } else {
                line.showNew(draft)
            }
        }
    }

    /// Adds the entry as its line says; the sheet closes as the drawn
    /// entry goes.
    private func save() {
        guard week.newEntry != nil, line.apply(undoManager: undoManager) else { return }
        week.newEntry = nil
    }
}

#if DEBUG
#Preview("New entry") {
    let model = PreviewData.model()
    let week = WeekModel(model: model, days: ReportPeriod.week.range(containing: model.today, firstWeekday: model.firstWeekday))
    week.newEntry = model.newEntryDraft(on: model.today, startSecond: 9 * 3600, endSecond: 10 * 3600)
    return Color.clear
        .sheet(isPresented: .constant(true)) {
            CompactNewEntrySheet(model: model, week: week)
        }
}
#endif
