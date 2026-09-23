#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Edits the selected entries: one in detail, or several at once.
struct EntryInspector: View {
    let model: AppModel
    let ids: Set<UUID>

    var body: some View {
        let entries = model.resolved.filter { ids.contains($0.id) }
        Group {
            if entries.count == 1, let entry = entries.first {
                EntryEditor(model: model, entry: entry)
                    .id(entry.id)
            } else if entries.count > 1 {
                EntriesEditor(model: model, entries: entries)
            } else {
                ContentUnavailableView("No Selection", systemImage: "clock", description: Text("Select an entry to edit it."))
            }
        }
        .inspectorColumnWidth(min: 260, ideal: 290, max: 440)
    }
}

/// One entry's project, tags, note and times. Times are shown and edited in
/// the entry's own time zone.
struct EntryEditor: View {
    let model: AppModel
    let entry: ResolvedEntry
    @Environment(\.undoManager) private var undoManager

    private var zone: String { entry.entry.timeZone }

    var body: some View {
        Form {
            Section {
                ProjectPicker(ledger: model.ledger, selection: Binding(
                    get: { entry.entry.projectID },
                    set: { projectID in update("Change Project") { $0.projectID = projectID } }
                ))
                LabeledContent("Tags") {
                    TagField(tags: entry.entry.tags, suggestions: model.ledger.allTags()) { tags in
                        update("Change Tags") { $0.tags = tags }
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
                Button("Delete Entry", role: .destructive) {
                    model.deleteEntries([entry.id], undoManager: undoManager)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
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
                            Text("\(Format.duration(overlap.duration)) with \(title(of: overlap.earlier == entry.id ? overlap.later : overlap.earlier))")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        if let fix = overlap.fix {
                            Button(fixTitle(fix)) {
                                model.apply(fix, undoManager: undoManager)
                            }
                        }
                    }
                }
            }
        }
    }

    private func title(of id: UUID) -> String {
        guard let other = model.resolved.first(where: { $0.id == id }) else { return "another entry" }
        return "\(model.ledger.projectTitle(other.entry.projectID)) at \(Format.time(other.start, zone: other.entry.timeZone))"
    }

    private func fixTitle(_ fix: OverlapFix) -> String {
        switch fix {
        case .trimEarlier: "Trim Earlier Entry"
        case .split: "Split Entry Around It"
        }
    }
}

/// Changes several entries at once: their project, adding and removing
/// tags, or deleting them.
struct EntriesEditor: View {
    let model: AppModel
    let entries: [ResolvedEntry]
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let ids = entries.map(\.id)
        let tags = Self.tags(in: entries)
        Form {
            Section {
                LabeledContent("Selected", value: "\(entries.count) entries")
                LabeledContent("Total", value: Format.duration(entries.reduce(0) { $0 + model.duration(of: $1) }))
            }
            Section {
                ProjectChooserButton(ledger: model.ledger, title: "Set Project…") { projectID in
                    model.updateEntries(ids, actionName: "Change Project", undoManager: undoManager) { $0.projectID = projectID }
                }
                LabeledContent("Add Tags") {
                    TagField(tags: [], suggestions: model.ledger.allTags()) { added in
                        guard !added.isEmpty else { return }
                        model.updateEntries(ids, actionName: "Add Tags", undoManager: undoManager) { $0.tags += added }
                    }
                }
                if !tags.isEmpty {
                    Menu("Remove Tag") {
                        ForEach(tags, id: \.self) { tag in
                            Button(tag) {
                                model.updateEntries(ids, actionName: "Remove Tag", undoManager: undoManager) { entry in
                                    entry.tags.removeAll { Tags.same($0, tag) }
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button("Delete \(entries.count) Entries", role: .destructive) {
                    model.deleteEntries(ids, undoManager: undoManager)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.isReadOnly)
    }

    /// The tags on any of the entries, once each, ignoring case.
    static func tags(in entries: [ResolvedEntry]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in entries {
            for tag in entry.entry.tags where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
        }
        return result.sorted { $0.lowercased() < $1.lowercased() }
    }
}
#endif
