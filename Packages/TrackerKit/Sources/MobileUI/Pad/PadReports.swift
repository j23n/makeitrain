#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// Totals on iPad for a day, a week, a month or days of your choice,
/// filtered as on the Mac: the figures across the top, the time of each
/// day on a chart, and the time by client, project or tag with a bar for
/// each, and the CSV to share.
struct PadReportsScreen: View {
    let model: AppModel
    @State private var period = ReportPeriod.week
    /// The days shown, or nil for the period containing today.
    @State private var range: ClosedRange<LocalDate>?
    @State private var grouping = ReportRequest.Grouping.client
    @State private var clients: Set<UUID?> = []
    @State private var projects: Set<UUID?> = []
    @State private var tags: Set<String> = []
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let report = Report(request, ledger: model.ledger, resolved: model.resolved, now: model.now)
        content(report)
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

    @ViewBuilder
    private func content(_ report: Report) -> some View {
        if model.resolved.isEmpty {
            ContentUnavailableView(
                "No Time Logged Yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Start a timer, and the time you log adds up here.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    ReportSummary(
                        report: report,
                        comparison: ReportComparison(
                            report,
                            period: period,
                            today: model.today,
                            firstWeekday: model.firstWeekday,
                            ledger: model.ledger,
                            resolved: model.resolved,
                            now: model.now
                        ),
                        period: period,
                        now: model.now,
                        incomplete: model.missingFiles > 0 || !model.issues.isEmpty
                    )
                    // A day's time is in its figures and breakdown; a chart
                    // of one bar adds nothing.
                    if report.days.count > 1 {
                        ReportChart(report: report, ledger: model.ledger, today: model.today, firstWeekday: model.firstWeekday, height: 190)
                            .card()
                    }
                    breakdown(report)
                        .card()
                }
                .padding(24)
                .frame(maxWidth: 1200, alignment: .leading)
                .frame(maxWidth: .infinity)
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

    /// The time by client, project or tag, with the grouping beside its
    /// heading; in a narrow window the bars go under the names.
    private func breakdown(_ report: Report) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Breakdown")
                    .font(.headline)
                Spacer(minLength: 12)
                Picker("Group by", selection: $grouping) {
                    Text("Client").tag(ReportRequest.Grouping.client)
                    Text("Project").tag(ReportRequest.Grouping.project)
                    Text("Tag").tag(ReportRequest.Grouping.tag)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Group the time by client, project or tag")
            }
            if report.groups.isEmpty {
                Text(isFiltered ? "No time logged on these days matches the filters." : "No time logged on these days.")
                    .foregroundStyle(.secondary)
            } else {
                ReportBreakdown(report: report, style: sizeClass == .compact ? .stacked : .inline)
            }
        }
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
            .help("Show a day, a week, a month or days of your choice")

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
                    .help("Show the previous \(period.rawValue)")
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
                    .help("Show the next \(period.rawValue)")
                    if !currentRange.contains(model.today) {
                        Button(currentTitle) {
                            range = nil
                        }
                        .keyboardShortcut("t", modifiers: .command)
                        .help("Show \(currentTitle.lowercased())")
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

#Preview("A Freelancer's Week") {
    NavigationStack {
        PadReportsScreen(model: PreviewData.model(PreviewData.ownerLedger))
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Narrow Window") {
    NavigationStack {
        PadReportsScreen(model: PreviewData.model(PreviewData.ownerLedger))
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
    }
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 420)
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
