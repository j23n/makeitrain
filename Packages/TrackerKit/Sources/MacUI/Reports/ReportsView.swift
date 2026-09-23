#if os(macOS)
import Charts
import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// Totals for a day, week, month or custom range, grouped and filtered,
/// with a chart and CSV export.
struct ReportsView: View {
    let model: AppModel
    @State private var period = ReportPeriod.week
    /// The days shown, or nil for the period containing today.
    @State private var range: ClosedRange<LocalDate>?
    @State private var grouping = ReportRequest.Grouping.client
    @State private var clients: Set<UUID?> = []
    @State private var projects: Set<UUID?> = []
    @State private var tags: Set<String> = []
    @State private var exportDocument: CSVDocument?
    @State private var exporting = false
    @State private var exportError: String?

    var body: some View {
        let report = Report(request, ledger: model.ledger, resolved: model.resolved, now: model.now)
        VStack(spacing: 0) {
            controls
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ReportSummary(report: report, now: model.now)
                    ReportChart(report: report, ledger: model.ledger)
                        .frame(height: 240)
                    ReportGroupList(report: report)
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportDocument = CSVDocument(data: CSVExport.data(for: report, ledger: model.ledger))
                    exporting = true
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                .help("Save the entries behind this report as a CSV file")
                .disabled(report.entries.isEmpty)
            }
        }
        .fileExporter(
            isPresented: $exporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Time Report \(currentRange.lowerBound) to \(currentRange.upperBound)"
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Couldn't Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
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

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Period", selection: periodBinding) {
                Text("Day").tag(ReportPeriod.day)
                Text("Week").tag(ReportPeriod.week)
                Text("Month").tag(ReportPeriod.month)
                Text("Custom").tag(ReportPeriod.custom)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if period == .custom {
                DatePicker("From", selection: fromBinding, displayedComponents: .date)
                    .labelsHidden()
                Text("to")
                DatePicker("To", selection: toBinding, displayedComponents: .date)
                    .labelsHidden()
            } else {
                ControlGroup {
                    Button {
                        step(-1)
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                    }
                    .help("Previous \(period.rawValue)")
                    Button(currentTitle) {
                        range = nil
                    }
                    .help("Go to today")
                    Button {
                        step(1)
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .help("Next \(period.rawValue)")
                }
                .fixedSize()
                Text(Format.days(currentRange))
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            Picker("Group by", selection: $grouping) {
                Text("Client").tag(ReportRequest.Grouping.client)
                Text("Project").tag(ReportRequest.Grouping.project)
                Text("Tag").tag(ReportRequest.Grouping.tag)
            }
            .fixedSize()

            filterMenu
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
            Divider()
            Button("Clear Filters") {
                clients = []
                projects = []
                tags = []
            }
            .disabled(!isFiltered)
        } label: {
            Label(
                isFiltered ? "Filtered" : "Filter",
                systemImage: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
        .fixedSize()
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

/// The total, the time overlaps count twice, and the running timer.
struct ReportSummary: View {
    let report: Report
    let now: Timestamp

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Format.duration(report.total))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            if report.doubleCounted > 0 {
                Label(
                    "Includes \(Format.duration(report.doubleCounted)) counted twice where entries overlap.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            if let running = report.running {
                Label(
                    "Running: \(Format.duration(running.duration(now: now))), not included",
                    systemImage: "record.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        let entries = report.entries.count == 1 ? "1 entry" : "\(report.entries.count) entries"
        return "\(Format.hours(report.total)) hours in \(entries)"
    }
}

/// Hours per day, stacked by project in the projects' colors.
struct ReportChart: View {
    let report: Report
    let ledger: Ledger

    struct Bar: Identifiable {
        var date: Date
        var project: String
        var hours: Double

        var id: String { "\(date.timeIntervalSince1970) \(project)" }
    }

    var body: some View {
        let data = chartData
        Chart(data.bars) { bar in
            BarMark(
                x: .value("Day", bar.date, unit: .day),
                y: .value("Hours", bar.hours)
            )
            .foregroundStyle(by: .value("Project", bar.project))
        }
        .chartForegroundStyleScale(domain: data.titles, range: data.colors)
        .chartYAxisLabel("Hours")
        .overlay {
            if data.bars.isEmpty {
                Text("No time logged")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The bars, and the projects' titles and colors, busiest first.
    private var chartData: (bars: [Bar], titles: [String], colors: [Color]) {
        var totals: [UUID?: Int64] = [:]
        for day in report.days {
            for (projectID, milliseconds) in day.projects {
                totals[projectID, default: 0] += milliseconds
            }
        }
        let order = totals.keys.sorted { a, b in
            totals[a, default: 0] != totals[b, default: 0]
                ? totals[a, default: 0] > totals[b, default: 0]
                : ledger.projectTitle(a) < ledger.projectTitle(b)
        }
        var titles: [String] = []
        var colors: [Color] = []
        for projectID in order where !titles.contains(ledger.projectTitle(projectID)) {
            titles.append(ledger.projectTitle(projectID))
            colors.append(ledger.color(ofProject: projectID))
        }
        var bars: [Bar] = []
        for day in report.days {
            for projectID in order {
                if let milliseconds = day.projects[projectID], milliseconds > 0 {
                    bars.append(Bar(
                        date: day.date.pickerDate,
                        project: ledger.projectTitle(projectID),
                        hours: Double(milliseconds) / 3_600_000
                    ))
                }
            }
        }
        return (bars, titles, colors)
    }
}

/// The report's groups, with a client's projects indented under it.
struct ReportGroupList: View {
    let report: Report

    var body: some View {
        VStack(spacing: 0) {
            ForEach(report.groups) { group in
                ReportGroupRow(group: group, total: report.total, indented: false)
                ForEach(group.children) { child in
                    ReportGroupRow(group: child, total: report.total, indented: true)
                }
            }
        }
    }
}

struct ReportGroupRow: View {
    let group: ReportGroup
    let total: Int64
    let indented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let color = group.color {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 8, height: 8)
                }
                Text(group.title)
                    .fontWeight(indented ? .regular : .medium)
                Spacer()
                Text(Format.duration(group.milliseconds))
                    .monospacedDigit()
                Text(Format.percent(group.milliseconds, of: total))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.leading, indented ? 22 : 0)
            .padding(.vertical, 7)
            Divider()
        }
    }
}

/// A CSV file to save.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
#endif
