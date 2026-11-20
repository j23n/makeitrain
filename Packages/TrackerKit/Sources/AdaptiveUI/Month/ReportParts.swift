import SwiftUI
import TrackerCore
import TrackerKit
import UniformTypeIdentifiers

/// A report's page: its header, the year's weeks over the screen's own
/// content, and the statement beside them. The report's clients and
/// projects are the window's filter, so they carry over to the week.
struct ReportPage<Header: View, Content: View>: View {
    let model: AppModel
    let state: ReportState
    let navigator: Navigator
    let header: Header
    let content: Content

    init(
        model: AppModel,
        state: ReportState,
        navigator: Navigator,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.model = model
        self.state = state
        self.navigator = navigator
        self.header = header()
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header
                    .padding(.horizontal, 24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        YearRibbon(state: state)
                        content
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
            .padding(.top, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            StatementPanel(model: model, state: state, navigator: navigator)
        }
        .onChange(of: state.clients) { _, clients in
            navigator.clients = clients
        }
        .onChange(of: state.projects) { _, projects in
            navigator.projects = projects
        }
    }
}

/// What the report covers, typed, which ⌘L focuses: "acme sep 2026 by
/// tag".
struct ReportTypeField: View {
    let model: AppModel
    let state: ReportState
    @State private var typed = ""
    @State private var focusRequest = 0

    var body: some View {
        HStack(spacing: 8) {
            CommandField(
                text: $typed,
                placeholder: state.typed,
                reading: query.reading,
                ledger: model.ledger,
                fontSize: 12.5,
                focusRequest: focusRequest,
                onSubmit: { _ in
                    state.apply(query)
                    typed = ""
                    endTextEditing()
                },
                onCancel: {
                    typed = ""
                    endTextEditing()
                }
            )
            .frame(width: 200, height: 18)
            KeyCap("⌘L")
        }
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.fill))
        .background {
            Button("Type a Report") { focusRequest += 1 }
                .keyboardShortcut("l")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var query: ReportQuery {
        ReportQuery.read(typed, ledger: model.ledger, today: model.today, firstWeekday: model.firstWeekday)
    }
}

/// The projects in a report, what the overlap mark means, and how many
/// projects the filter leaves out.
struct ReportLegend: View {
    let model: AppModel
    let state: ReportState

    var body: some View {
        let projects = Set(state.report.entries.compactMap(\.entry.projectID))
        let shown = projects.sorted { model.ledger.projectTitle($0) < model.ledger.projectTitle($1) }.prefix(3)
        let filteredOut = model.ledger.pickerProjects().filter { !projects.contains($0.id) }.count
        HStack(spacing: 12) {
            ForEach(Array(shown), id: \.self) { projectID in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(model.ledger.tint(ofProject: projectID).bar).frame(width: 8, height: 8)
                    Text(model.ledger.projects[projectID]?.name ?? "")
                }
            }
            if !state.overlapDaysInRange.isEmpty {
                HStack(spacing: 5) {
                    OverlapSwatch(size: 10)
                    Text("overlap")
                }
            }
            if !state.clients.isEmpty || !state.projects.isEmpty, filteredOut > 0 {
                Text("\(filteredOut) \(filteredOut == 1 ? "project" : "projects") filtered out")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.text2)
        .lineLimit(1)
    }
}

/// The year as a bar per week, the weeks in the range in the accent color.
/// Clicking a week shows it; dragging across weeks shows them all.
struct YearRibbon: View {
    let state: ReportState
    @State private var dragging: ClosedRange<Int>?

    var body: some View {
        let weeks = state.weeks
        let highest = max(weeks.map(\.total).max() ?? 0, ChartScale.fullWeek)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(String(state.range.lowerBound.year))")
                    .fontWeight(.semibold)
                + Text(" · hours per week")
                    .foregroundColor(Theme.text3)
                Spacer()
                Text("Drag to select weeks")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
            }
            .font(.system(size: 13))
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(max(weeks.count, 1))
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(weeks.indices, id: \.self) { index in
                        let week = weeks[index]
                        let selected = dragging.map { $0.contains(index) } ?? overlapsRange(week.start)
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(selected ? Theme.accent : (week.total > 0 ? Theme.accent.opacity(0.42) : Theme.emptyBar))
                            .frame(height: week.total > 0 ? max(3, CGFloat(week.total) / CGFloat(highest) * 64) : 2)
                            .help("Week of \(Format.monthDay(week.start)), \(week.total > 0 ? Format.duration(week.total) : "no time")")
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let first = index(at: value.startLocation.x, width: width, count: weeks.count)
                            let last = index(at: value.location.x, width: width, count: weeks.count)
                            dragging = min(first, last)...max(first, last)
                        }
                        .onEnded { _ in
                            if let range = dragging {
                                let start = weeks[range.lowerBound].start
                                let end = weeks[range.upperBound].start.adding(days: 6)
                                state.show(start...end, period: range.count == 1 ? .week : .custom)
                            }
                            dragging = nil
                        }
                )
            }
            .frame(height: 64)
            HStack(spacing: 0) {
                ForEach(1...12, id: \.self) { month in
                    Text(Format.shortMonth(LocalDate(year: 2000, month: month, day: 1)))
                        .font(.system(size: 10.5, weight: state.range.lowerBound.month == month ? .semibold : .regular))
                        .foregroundStyle(state.range.lowerBound.month == month ? Theme.text : Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(state.title)'s hours per week in \(String(state.range.lowerBound.year))"))
    }

    private func index(at x: CGFloat, width: CGFloat, count: Int) -> Int {
        min(max(Int(x / max(width, 1)), 0), max(count - 1, 0))
    }

    private func overlapsRange(_ start: LocalDate) -> Bool {
        start <= state.range.upperBound && start.adding(days: 6) >= state.range.lowerBound
    }
}

/// The report's totals, breakdown, what to check before sending it, and
/// saving it as CSV or as a PDF statement.
struct StatementPanel: View {
    let model: AppModel
    let state: ReportState
    let navigator: Navigator
    @State private var csv: ExportDocument?
    @State private var savingCSV = false
    @State private var pdf: ExportDocument?
    @State private var savingPDF = false

    private var report: Report { state.report }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(size: 22, weight: .semibold))
                    Text(subtitle)
                        .foregroundStyle(Theme.text2)
                }
                ReportFigures(model: model, state: state)
                ReportBreakdown(state: state)
                checks
                csvPreview
                buttons
            }
            .padding(22)
        }
        .sidebarColumn(width: 400)
    }

    private var subtitle: String {
        let projects = Set(report.entries.compactMap(\.entry.projectID))
        let names = projects.compactMap { model.ledger.projects[$0]?.name }.sorted()
        let who = names.count == 1 && state.projects.isEmpty ? "\(names[0]) · " : ""
        return who + Format.days(state.range)
    }

    /// What to check before sending the report.
    private var checks: some View {
        let overlapDays = state.overlapDaysInRange
        let notDownloaded = model.missingFiles + model.issues.filter { $0.problem == .notDownloaded }.count
        return VStack(alignment: .leading, spacing: 10) {
            Text("Before sending")
                .font(.system(size: 13, weight: .semibold))
            if report.doubleCounted > 0 {
                HStack(alignment: .top, spacing: 10) {
                    OverlapSwatch(size: 14)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        (Text(Format.duration(report.doubleCounted)).fontWeight(.semibold).foregroundColor(Theme.amberText)
                            + Text(" is counted twice: entries overlap on \(overlapDays.map { Format.monthDay($0) }.formatted(.list(type: .and)))."))
                            .fixedSize(horizontal: false, vertical: true)
                        if let first = overlapDays.first {
                            Button("Fix in Week ›") {
                                navigator.go(.week(first))
                            }
                            .linkButton()
                        }
                    }
                }
            }
            if report.running != nil {
                Label("The running timer isn't included until it stops.", systemImage: "record.circle")
                    .foregroundStyle(Theme.text2)
            }
            Label(
                notDownloaded == 0 ? "All data downloaded." : "\(notDownloaded) files not downloaded yet. Time may be missing.",
                systemImage: notDownloaded == 0 ? "checkmark.circle" : "icloud.and.arrow.down"
            )
            .foregroundStyle(notDownloaded == 0 ? Theme.text2 : Theme.amberText)
        }
        .font(.system(size: 12.5))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.amberWash))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.amberLine))
    }

    private var csvPreview: some View {
        // The heading and the first two rows.
        let text = String(CSVExport.text(for: Array(report.entries.prefix(2)), ledger: model.ledger).dropFirst())
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("CSV · \(report.entries.count) rows")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Total hours: ") + Text(CSVExport.totalHours(report.entries)).foregroundColor(Theme.text)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            Text((lines + (report.entries.count > 2 ? ["…"] : [])).joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.text4)
                .lineLimit(4)
                .lineSpacing(6)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button {
                csv = ExportDocument(data: CSVExport.data(for: report.entries, ledger: model.ledger))
                savingCSV = true
            } label: {
                HStack {
                    Text("Save CSV…")
                    Spacer()
                    KeyCap("⌘E", onInverse: true)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChoiceButtonStyle(suggested: true))
            .keyboardShortcut("e")
            .disabled(report.entries.isEmpty)
            .fileExporter(isPresented: $savingCSV, document: csv, contentType: .commaSeparatedText, defaultFilename: state.csvFileName) { _ in }
            Button {
                pdf = ExportDocument(data: StatementPDF.data(for: report, ledger: model.ledger, title: state.title))
                savingPDF = true
            } label: {
                HStack {
                    Text("Save PDF…")
                    Spacer()
                    KeyCap("⌘P")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChoiceButtonStyle())
            .keyboardShortcut("p")
            .disabled(report.entries.isEmpty)
            .fileExporter(isPresented: $savingPDF, document: pdf, contentType: .pdf, defaultFilename: StatementPDF.fileName(for: report, title: state.title)) { _ in }
        }
    }
}

/// A report's figures, in a grid of four: its total, the average day
/// worked, the days worked, and the change from the days before. The month
/// shows them on its statement in the wide layout, and under its days in
/// the narrow one, smaller.
struct ReportFigures: View {
    let model: AppModel
    let state: ReportState
    var compact = false

    private var report: Report { state.report }

    var body: some View {
        let comparison = state.comparison
        let change = comparison.total - comparison.previousTotal
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                FigureTile("Total", Format.duration(report.total), "\(report.entries.count) \(report.entries.count == 1 ? "entry" : "entries")", compact: compact)
                FigureTile("Average day", Format.duration(report.averagePerDayWorked), "on days worked", compact: compact)
            }
            GridRow {
                FigureTile("Days worked", "\(report.daysWorked)", "of \(state.weekdays) weekdays", compact: compact)
                FigureTile(
                    comparisonTitle,
                    (change >= 0 ? "+" : "−") + Format.duration(abs(change)),
                    comparison.percent.map { "\($0 >= 0 ? "+" : "")\($0)% from \(Format.duration(comparison.previousTotal))" } ?? "nothing before",
                    compact: compact
                )
            }
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 14 : 12))
        .overlay(RoundedRectangle(cornerRadius: compact ? 14 : 12).strokeBorder(Theme.line))
    }

    /// "vs. August", or "vs. previous week".
    private var comparisonTitle: String {
        switch state.period {
        case .month:
            "vs. \(Format.monthName(state.comparison.previousRange.lowerBound))"
        case .week:
            "vs. previous week"
        case .day:
            "vs. previous day"
        case .custom:
            "vs. previous days"
        }
    }
}

/// A report's time by client, project or tag, the most first, each with
/// its share as a bar. The wide layout picks the grouping beside the
/// title; the narrow one has it in a chip over the month.
struct ReportBreakdown: View {
    let state: ReportState
    var compact = false
    @State private var showsAll = false

    private var report: Report { state.report }
    /// How many rows show before "more".
    private var shownCount: Int { compact ? 8 : 6 }

    var body: some View {
        let rows = report.groups
        let shown = showsAll ? rows : Array(rows.prefix(shownCount))
        let highest = rows.map(\.milliseconds).max() ?? 1
        VStack(alignment: .leading, spacing: compact ? 8 : 9) {
            HStack {
                Text("By \(state.grouping.rawValue)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(compact ? Theme.text2 : Theme.text)
                Spacer()
                if !compact {
                    SegmentPicker(
                        ReportRequest.Grouping.allCases.map { (value: $0, title: $0.rawValue.capitalized) },
                        selection: Bindable(state).grouping
                    )
                    .scaleEffect(0.9)
                }
            }
            if rows.isEmpty {
                Text("Nothing logged.")
                    .font(.system(size: compact ? 13 : 12))
                    .foregroundStyle(Theme.text3)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shown) { group in
                    VStack(spacing: 4) {
                        HStack(spacing: 10) {
                            ReportGroupTitle(group, in: state, spacing: compact ? 7 : 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.duration(group.milliseconds))
                                .frame(width: 78, alignment: .trailing)
                            Text(Format.percent(group.milliseconds, of: report.total))
                                .foregroundStyle(Theme.text3)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .font(.system(size: compact ? 14 : 12))
                        .monospacedDigit()
                        .frame(minHeight: compact ? 24 : nil)
                        ShareBar(group.milliseconds, of: highest, color: group.color.map { ProjectTint(hex: $0).bar } ?? Theme.accent.opacity(0.7), height: 4)
                    }
                    .padding(.bottom, 4)
                }
            }
            if rows.count > shownCount {
                Button(showsAll ? "Show fewer" : "\(rows.count - shownCount) more · \(Format.duration(rows.dropFirst(shownCount).reduce(0) { $0 + $1.milliseconds }))") {
                    showsAll.toggle()
                }
                .linkButton()
                .font(.system(size: compact ? 14 : 12.5))
            }
        }
    }
}

/// A figure in a grid of them, as on a statement or a project's page:
/// what it is, its value, and a line about it. In the narrow layout it's
/// smaller, two to a row on an iPhone.
struct FigureTile<Detail: View>: View {
    let label: String
    let value: String
    let detail: Detail
    let compact: Bool

    init(_ label: String, _ value: String, compact: Bool = false, @ViewBuilder detail: () -> Detail) {
        self.label = label
        self.value = value
        self.compact = compact
        self.detail = detail()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            Text(label)
                .font(.system(size: compact ? 11.5 : 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
            Text(value)
                .font(.system(size: compact ? 19 : 24, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            detail
                .font(.system(size: compact ? 11 : 12))
                .foregroundStyle(Theme.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 9 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
    }
}

extension FigureTile where Detail == Text {
    /// A figure with a line of text about it.
    init(_ label: String, _ value: String, _ detail: String, compact: Bool = false) {
        self.label = label
        self.value = value
        self.compact = compact
        self.detail = Text(detail)
    }
}
