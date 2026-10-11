#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import WideUI

/// What an entry's line reads as, part by part: its day, times, project,
/// tags and note. A part the line leaves out shows as what could go there,
/// and a line that isn't an entry says why.
struct EntryLineGuide: View {
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

/// An entry as a line to change by typing, such as "2 oct 13:30-16:30
/// web #12 Fix login", and what else can be done with it.
struct PhoneEntrySheet: View {
    let model: AppModel
    let entryID: UUID
    @State private var line: EntryLineModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel, entryID: UUID) {
        self.model = model
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
            .navigationBarTitleDisplayMode(.inline)
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
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        CommandField(
                            entryLine: line,
                            fontSize: 15,
                            focusesWithWindow: true,
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
                        SuggestionStrip(suggestions: line.suggestions, ledger: model.ledger, showsKeys: false) { index in
                            line.acceptSuggestion(at: index)
                        }
                    }
                    EntryLineGuide(model: model, line: line)
                }
                actions(entry)
            }
            .padding(16)
        }
    }

    private func actions(_ entry: ResolvedEntry) -> some View {
        VStack(spacing: 0) {
            if entry.isRunning {
                row("Stop", systemImage: "stop.fill") {
                    model.stopTimer(undoManager: undoManager)
                    dismiss()
                }
            } else {
                row("Continue it now", systemImage: "play.fill") {
                    model.continueEntry(entry, undoManager: undoManager)
                    dismiss()
                }
                row("Duplicate", systemImage: "plus.square.on.square") {
                    model.duplicateEntry(entry.id, undoManager: undoManager)
                    dismiss()
                }
            }
            if EntrySplit.time(for: entry, now: model.now) != nil {
                row("Split in the middle", systemImage: "scissors") {
                    model.splitInMiddle(entry, undoManager: undoManager)
                    dismiss()
                }
            }
            row("Delete", systemImage: "trash", destructive: true) {
                model.deleteEntry(entry.id, undoManager: undoManager)
                dismiss()
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        .disabled(model.isReadOnly)
    }

    private func row(_ title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                Spacer()
            }
            .font(.system(size: 15))
            .foregroundStyle(destructive ? Theme.now : Theme.text)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func apply() {
        guard entry != nil else { return }
        if line.apply(undoManager: undoManager) {
            dismiss()
        }
    }
}
#endif
