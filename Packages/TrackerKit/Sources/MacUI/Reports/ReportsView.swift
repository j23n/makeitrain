#if os(macOS)
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
                    ReportSummary(report: report, now: model.now, incomplete: model.missingFiles > 0 || !model.issues.isEmpty)
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

#if DEBUG
#Preview("This Week") {
    ReportsView(model: PreviewData.model())
        .frame(width: 1000, height: 720)
}

#Preview("Files Missing") {
    ReportsView(model: PreviewData.model(missingFiles: 3))
        .frame(width: 1000, height: 720)
}

#Preview("No Entries") {
    ReportsView(model: PreviewData.model(Ledger()))
        .frame(width: 1000, height: 720)
}
#endif
#endif
