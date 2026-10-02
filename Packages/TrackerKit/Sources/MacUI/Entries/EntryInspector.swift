#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Edits the entry selected on the timeline.
struct EntryInspector: View {
    let model: AppModel
    let id: UUID?
    /// Selects another entry, such as a copy just made.
    let select: (UUID) -> Void

    var body: some View {
        Group {
            if let entry = model.resolved.first(where: { $0.id == id }) {
                EntryEditor(model: model, entry: entry, select: select)
                    .id(entry.id)
            } else {
                ContentUnavailableView("No Selection", systemImage: "clock", description: Text("Select an entry to edit it."))
            }
        }
        .inspectorWidth()
    }
}

/// One entry's project, tags, note and times. Times are shown and edited in
/// the entry's own time zone.
struct EntryEditor: View {
    let model: AppModel
    let entry: ResolvedEntry
    /// Selects another entry, such as the copy "Duplicate Entry" makes.
    let select: (UUID) -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var splitting = false

    private var zone: String { entry.entry.timeZone }

    var body: some View {
        Form {
            Section {
                ProjectPicker(ledger: model.ledger, selection: Binding(
                    get: { entry.entry.projectID },
                    set: { projectID in update("Change Project") { $0.projectID = projectID } }
                ))
                LabeledContent("Tags") {
                    TagField(tags: entry.entry.tags, suggestions: model.projectTags[entry.entry.projectID] ?? []) { tags in
                        update("Change Tags") { $0.tags = tags }
                    }
                }
                let links = model.ledger.issueLinks(tags: entry.entry.tags, projectID: entry.entry.projectID)
                if !links.isEmpty {
                    LabeledContent("GitHub") {
                        TagList(tags: entry.entry.tags.filter { links[$0] != nil }, links: links, wraps: true)
                    }
                }
                CommitField(title: "Note", value: entry.entry.note, axis: .vertical) { note in
                    update("Change Note") { $0.note = note }
                }
            }

            Section {
                DatePicker(
                    "Start",
                    selection: Binding(
                        get: { entry.start.date },
                        set: { date in update("Change Start") { $0.start = Timestamp(date) } }
                    ),
                    in: ...(entry.end ?? model.now).date,
                    displayedComponents: [.date, .hourAndMinute]
                )
                if let end = entry.end {
                    DatePicker(
                        "End",
                        selection: Binding(
                            get: { end.date },
                            set: { date in update("Change End") { $0.end = Timestamp(date) } }
                        ),
                        in: entry.start.date...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    CommitField(title: "Duration", value: Format.duration(entry.start.distance(to: end))) { text in
                        guard let duration = Format.parseDuration(text) else { return }
                        update("Change Duration") { $0.end = $0.start.adding(milliseconds: duration) }
                    }
                } else {
                    LabeledContent("End") {
                        Button("Stop Timer") {
                            model.stopTimer(undoManager: undoManager)
                        }
                    }
                    LabeledContent("Duration", value: Format.duration(model.duration(of: entry)))
                }
                if let label = Format.zoneLabel(zone, at: entry.start) {
                    LabeledContent("Time Zone", value: "\(label) (\(zone))")
                }
            } footer: {
                if entry.endedByLaterTimer {
                    Text("This timer was still running on another device when a later one started there, so it ends when that one started.")
                        .foregroundStyle(.secondary)
                }
            }
            .environment(\.timeZone, Zones.zone(zone))

            OverlapSection(model: model, entry: entry)

            Section {
                Button("Duplicate Entry") {
                    if let copy = model.duplicateEntries([entry.id], undoManager: undoManager).first {
                        select(copy)
                    }
                }
                .disabled(entry.isRunning)
                Button("Split Entry…") {
                    splitting = true
                }
                .disabled(EntrySplit.range(of: entry, now: model.now) == nil)
                Button("Delete Entry", role: .destructive) {
                    model.deleteEntries([entry.id], undoManager: undoManager)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
        .sheet(isPresented: $splitting) {
            SplitEntrySheet(model: model, entry: entry, undoManager: undoManager)
        }
    }

    private func update(_ actionName: String, _ change: (inout TimeEntry) -> Void) {
        model.updateEntries([entry.id], actionName: actionName, undoManager: undoManager, change)
    }
}

/// The entries an entry overlaps, with a one-click fix for each where there
/// is one.
struct OverlapSection: View {
    let model: AppModel
    let entry: ResolvedEntry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let overlaps = model.overlaps.overlaps.filter { $0.earlier == entry.id || $0.later == entry.id }
        if !overlaps.isEmpty {
            Section("Overlaps") {
                ForEach(overlaps, id: \.self) { overlap in
                    VStack(alignment: .leading, spacing: 6) {
                        Label {
                            Text(model.overlapDescription(overlap, from: entry.id))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if let fix = overlap.fix {
                            Button(fix.title) {
                                model.apply(fix, undoManager: undoManager)
                            }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Entry") {
    EntryInspector(model: PreviewData.model(), id: PreviewData.entry("Wireframe review, round 2")) { _ in }
        .frame(width: 300, height: 640)
}

#Preview("Overlap") {
    EntryInspector(model: PreviewData.model(), id: PreviewData.entry("Call with Globex")) { _ in }
        .frame(width: 300, height: 640)
}

#Preview("Running Timer") {
    EntryInspector(model: PreviewData.model(), id: PreviewData.entry("Landing page copy")) { _ in }
        .frame(width: 300, height: 640)
}

#Preview("Recorded in New York") {
    EntryInspector(model: PreviewData.model(), id: PreviewData.entry("Client visit")) { _ in }
        .frame(width: 300, height: 640)
}

#Preview("No Selection") {
    EntryInspector(model: PreviewData.model(), id: nil) { _ in }
        .frame(width: 300, height: 640)
}
#endif
#endif
