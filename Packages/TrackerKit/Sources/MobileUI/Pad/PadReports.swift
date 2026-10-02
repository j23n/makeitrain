#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Totals on iPad for a day, a week, a month or days of your choice,
/// grouped and filtered as on the Mac, with a chart, and the CSV to share.
struct PadReportsScreen: View {
    let model: AppModel
    @State private var period = ReportPeriod.week
    /// The days shown, or nil for the period containing today.
    @State private var range: ClosedRange<LocalDate>?
    @State private var grouping = ReportRequest.Grouping.client
    @State private var clients: Set<UUID?> = []
    @State private var projects: Set<UUID?> = []
    @State private var tags: Set<String> = []

    var body: some View {
        let report = Report(request, ledger: model.ledger, resolved: model.resolved, now: model.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                controls
                ReportSummary(report: report, now: model.now, incomplete: model.missingFiles > 0 || !model.issues.isEmpty)
                ReportChart(report: report, ledger: model.ledger)
                    .frame(height: 260)
                Picker("Group by", selection: $grouping) {
                    Text("Client").tag(ReportRequest.Grouping.client)
                    Text("Project").tag(ReportRequest.Grouping.project)
                    Text("Tag").tag(ReportRequest.Grouping.tag)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                ReportGroupList(report: report)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                filterMenu
                ShareLink(
                    item: CSVFile(data: CSVExport.data(for: report, ledger: model.ledger)),
                    preview: SharePreview("Time Report \(currentRange.lowerBound) to \(currentRange.upperBound)")
                ) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .help("Share the entries behind this report as a CSV file")
                .disabled(report.entries.isEmpty)
            }
        }
        .onChange(of: model.firstWeekday) { _, firstWeekday in
            if period == .week, let shown = range {
                range = ReportPeriod.week.range(containing: shown.lowerBound, firstWeekday: firstWeekday)
            }
        }
    }

    private var currentRange: ClosedRange<LocalDate> {
        range ?? period.range(containing: model.today, firstWeekday: model.firstWeekday)
    }

    private var request: ReportRequest {
        ReportRequest(
            range: currentRange,
            grouping: grouping,
            clients: clients.isEmpty ? nil : clients,
            projects: projects.isEmpty ? nil : projects,
            tags: tags.isEmpty ? nil : tags
        )
    }

    private var isFiltered: Bool {
        !clients.isEmpty || !projects.isEmpty || !tags.isEmpty
    }

    // MARK: Period

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: periodBinding) {
                Text("Day").tag(ReportPeriod.day)
                Text("Week").tag(ReportPeriod.week)
                Text("Month").tag(ReportPeriod.month)
                Text("Custom").tag(ReportPeriod.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)

            if period == .custom {
                HStack(spacing: 8) {
                    DatePicker("From", selection: fromBinding, displayedComponents: .date)
                        .labelsHidden()
                    Text("to")
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: toBinding, displayedComponents: .date)
                        .labelsHidden()
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        step(-1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .help("Previous \(period.rawValue)")
                    Text(Format.days(currentRange))
                        .font(.headline)
                        .lineLimit(1)
                    Button {
                        step(1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .help("Next \(period.rawValue)")
                    if !currentRange.contains(model.today) {
                        Button(currentTitle) {
                            range = nil
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var currentTitle: String {
        switch period {
        case .day: "Today"
        case .week: "This Week"
        case .month, .custom: "This Month"
        }
    }

    private var periodBinding: Binding<ReportPeriod> {
        Binding(
            get: { period },
            set: { newPeriod in
                let shown = currentRange
                period = newPeriod
                if newPeriod == .custom {
                    range = shown
                } else if shown.contains(model.today) {
                    range = nil
                } else {
                    range = newPeriod.range(containing: shown.lowerBound, firstWeekday: model.firstWeekday)
                }
            }
        )
    }

    private var fromBinding: Binding<Date> {
        Binding(
            get: { currentRange.lowerBound.pickerDate },
            set: { date in
                let from = LocalDate(pickerDate: date)
                range = from...max(from, currentRange.upperBound)
            }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { currentRange.upperBound.pickerDate },
            set: { date in
                let to = LocalDate(pickerDate: date)
                range = min(to, currentRange.lowerBound)...to
            }
        )
    }

    private func step(_ steps: Int) {
        range = period.shift(currentRange, by: steps, firstWeekday: model.firstWeekday)
    }

    // MARK: Filters

    private var filterMenu: some View {
        Menu {
            Section("Clients") {
                Toggle("No client", isOn: member(nil, of: $clients))
                ForEach(model.ledger.liveClients()) { client in
                    Toggle(client.name, isOn: member(client.id, of: $clients))
                }
            }
            Section("Projects") {
                Toggle("Unassigned", isOn: member(nil, of: $projects))
                ForEach(filterProjects) { project in
                    Toggle(model.ledger.projectTitle(project.id), isOn: member(project.id, of: $projects))
                }
            }
            let allTags = model.ledger.allTags()
            if !allTags.isEmpty {
                Section("Tags") {
                    ForEach(allTags, id: \.self) { tag in
                        Toggle(tag, isOn: Binding(
                            get: { tags.contains(tag) },
                            set: { on in
                                if on { tags.insert(tag) } else { tags.remove(tag) }
                            }
                        ))
                    }
                }
            }
            Section {
                Button("Clear Filters") {
                    clients = []
                    projects = []
                    tags = []
                }
                .disabled(!isFiltered)
            }
        } label: {
            Label(
                isFiltered ? "Filtered" : "Filter",
                systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .help("Show only some clients, projects or tags")
    }

    /// Projects that aren't deleted, archived ones included, since reports
    /// cover the past.
    private var filterProjects: [Project] {
        model.ledger.projects.values
            .filter { !$0.isDeleted }
            .sorted { model.ledger.projectTitle($0.id).lowercased() < model.ledger.projectTitle($1.id).lowercased() }
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

#if DEBUG
#Preview("This Week") {
    NavigationStack {
        PadReportsScreen(model: PreviewData.model())
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("No Entries") {
    NavigationStack {
        PadReportsScreen(model: PreviewData.model(Ledger()))
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
#endif
