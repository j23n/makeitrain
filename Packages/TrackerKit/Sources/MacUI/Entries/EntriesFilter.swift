#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// The bar over the entries table: the period, clients and projects, and
/// tags shown, overlaps only, how many entries that leaves and their time,
/// and a button that clears it all.
struct EntriesFilterBar: View {
    let model: AppModel
    @Binding var filter: EntriesFilter
    /// The rows the filter and search leave.
    let rows: [EntryRow]

    var body: some View {
        HStack(spacing: 8) {
            periodPicker
            if filter.period == .custom, let range = filter.range {
                DatePicker("From", selection: fromBinding(range), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Text("to")
                    .foregroundStyle(.secondary)
                DatePicker("To", selection: toBinding(range), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            projectsMenu
            tagsMenu
            Toggle(isOn: $filter.overlapsOnly) {
                Label("Overlaps", systemImage: "exclamationmark.triangle")
            }
            .toggleStyle(.button)
            .help("Show only entries that overlap another")

            Spacer(minLength: 8)

            EntriesSummary(model: model, rows: rows)
            if filter.isActive {
                Button("Clear") {
                    filter = EntriesFilter()
                }
                .help("Show every entry")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .onChange(of: model.today) { _, today in
            filter.refresh(today: today, firstWeekday: model.firstWeekday)
        }
        .onChange(of: model.firstWeekday) { _, firstWeekday in
            filter.refresh(today: model.today, firstWeekday: firstWeekday)
        }
    }

    // MARK: Period

    private var periodPicker: some View {
        Picker("Period", selection: Binding(
            get: { filter.period },
            set: { filter.choose($0, today: model.today, firstWeekday: model.firstWeekday) }
        )) {
            Text(EntriesPeriod.all.title).tag(EntriesPeriod.all)
            Divider()
            ForEach([EntriesPeriod.today, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .thisYear], id: \.self) { period in
                Text(period.title).tag(period)
            }
            Divider()
            Text(EntriesPeriod.custom.title).tag(EntriesPeriod.custom)
        }
        .labelsHidden()
        .fixedSize()
        .help("Show the entries of a day, week, month or year")
    }

    private func fromBinding(_ range: ClosedRange<LocalDate>) -> Binding<Date> {
        Binding(
            get: { range.lowerBound.pickerDate },
            set: { date in
                let from = LocalDate(pickerDate: date)
                filter.range = from...max(from, range.upperBound)
            }
        )
    }

    private func toBinding(_ range: ClosedRange<LocalDate>) -> Binding<Date> {
        Binding(
            get: { range.upperBound.pickerDate },
            set: { date in
                let to = LocalDate(pickerDate: date)
                filter.range = min(to, range.lowerBound)...to
            }
        )
    }

    // MARK: Clients and projects

    private var projectsMenu: some View {
        Menu {
            Section("Clients") {
                Toggle("No client", isOn: member(nil, of: $filter.clients))
                ForEach(model.ledger.liveClients()) { client in
                    Toggle(client.name, isOn: member(client.id, of: $filter.clients))
                }
            }
            Section("Projects") {
                Toggle("Unassigned", isOn: member(nil, of: $filter.projects))
                ForEach(projects) { project in
                    Toggle(model.ledger.projectTitle(project.id), isOn: member(project.id, of: $filter.projects))
                }
            }
        } label: {
            Text(projectsTitle)
        }
        .fixedSize()
        .help("Show only some clients' and projects' entries")
    }

    /// Projects that aren't deleted, archived ones included, since the table
    /// covers the past.
    private var projects: [Project] {
        model.ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
    }

    private var projectsTitle: String {
        switch (filter.clients.count, filter.projects.count) {
        case (0, 0):
            return "All Projects"
        case (1, 0):
            guard let chosen = filter.clients.first, let clientID = chosen else { return "No client" }
            return model.ledger.clients[clientID]?.name ?? "Unknown client"
        case (0, 1):
            return filter.projects.first.map { model.ledger.projectTitle($0) } ?? ""
        case (let count, 0):
            return "\(count) Clients"
        case (0, let count):
            return "\(count) Projects"
        case (let clientCount, let projectCount):
            return "\(clientCount + projectCount) Clients and Projects"
        }
    }

    // MARK: Tags

    private var tagsMenu: some View {
        Menu {
            let offered = offeredTags
            if offered.isEmpty {
                Text("No Tags")
            }
            ForEach(offered, id: \.self) { tag in
                Toggle(tag, isOn: Binding(
                    get: { filter.tags.contains(tag) },
                    set: { on in
                        if on {
                            filter.tags.insert(tag)
                        } else {
                            filter.tags.remove(tag)
                        }
                    }
                ))
            }
        } label: {
            Text(tagsTitle)
        }
        .fixedSize()
        .help("Show only entries with some tags")
    }

    /// The tags of the projects chosen, or of every project, and the tags
    /// chosen already, once each, ignoring case.
    private var offeredTags: [String] {
        let byProject = model.projectTags
        let lists = filter.projects.isEmpty ? Array(byProject.values) : filter.projects.compactMap { byProject[$0] }
        var seen: Set<String> = []
        var result: [String] = []
        for tag in lists.joined() where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        for tag in filter.tags where seen.insert(tag.lowercased()).inserted {
            result.append(tag)
        }
        return result.sorted(by: Tags.order)
    }

    private var tagsTitle: String {
        switch filter.tags.count {
        case 0: "All Tags"
        case 1: filter.tags.first ?? ""
        case let count: "\(count) Tags"
        }
    }

    private func member(_ id: UUID?, of set: Binding<Set<UUID?>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { on in
                if on {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }
}

/// How many entries are shown and their time. Only a running timer's time
/// follows the clock.
struct EntriesSummary: View {
    let model: AppModel
    let rows: [EntryRow]

    var body: some View {
        let total = rows.reduce(Int64(0)) { sum, row in
            sum + (row.entry.end.map { max(0, row.start.distance(to: $0)) } ?? model.duration(of: row.entry))
        }
        Text("\(rows.count == 1 ? "1 entry" : "\(rows.count.formatted()) entries") · \(Format.duration(total))")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help("The entries shown and their time")
    }
}

#if DEBUG
#Preview("Filter Bar") {
    let model = PreviewData.model()
    EntriesFilterBar(
        model: model,
        filter: .constant(EntriesFilter()),
        rows: model.resolved.map { EntryRow($0, projectTitle: model.ledger.projectTitle($0.entry.projectID), flagged: false) }
    )
    .frame(width: 900)
}

#Preview("Filter Bar, Filtered") {
    let model = PreviewData.model()
    EntriesFilterBar(
        model: model,
        filter: .constant(EntriesFilter(period: .custom, range: model.today.adding(days: -6)...model.today, tags: ["design"], overlapsOnly: true)),
        rows: []
    )
    .frame(width: 900)
}
#endif
#endif
