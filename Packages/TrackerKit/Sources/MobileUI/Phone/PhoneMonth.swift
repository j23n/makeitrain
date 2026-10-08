#if os(iOS)
import SwiftUI
import TrackerCore
import TrackerKit
import UIKit
import UniformTypeIdentifiers

/// A month as a report: what it covers as choices, the days with their
/// time, its figures, what to check before sending it, and the time by
/// client, project or tag. Tapping a day shows just it; holding and
/// dragging across days shows them.
struct PhoneMonth: View {
    let model: AppModel
    let router: PhoneRouter
    @State private var showsAll = false
    @State private var csv: CSVDocument?
    @State private var savingCSV = false
    @State private var pdf: PDFDocumentFile?
    @State private var savingPDF = false

    private var state: ReportState { router.month }
    private var report: Report { state.report }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                choices
                PhoneMonthGrid(model: model, state: state, month: shownMonth)
                    .padding(.horizontal, 12)
                figures
                    .padding(.horizontal, 12)
                if report.doubleCounted > 0 {
                    overlapWarning
                        .padding(.horizontal, 12)
                }
                breakdown
                    .padding(.horizontal, 20)
            }
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            PhoneCommandBar(model: model, placeholder: state.typed, open: { router.openCommandLine(mode: .report) })
        }
        .fileExporter(isPresented: $savingCSV, document: csv, contentType: .commaSeparatedText, defaultFilename: state.csvFileName) { _ in }
    }

    /// The month the grid shows: the range's, or its last's for a range
    /// over several months.
    private var shownMonth: LocalDate {
        state.range.lowerBound.monthKey == state.range.upperBound.monthKey ? state.range.lowerBound : state.range.upperBound
    }

    // MARK: Header

    private var title: String {
        let range = state.range
        let month = ReportPeriod.month.range(containing: range.lowerBound, firstWeekday: model.firstWeekday)
        guard month == range else { return Format.days(range) }
        return range.lowerBound.year == model.today.year ? Format.monthName(range.lowerBound) : Format.month(range.lowerBound)
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            stepButton("chevron.left", "Previous", -1)
            stepButton("chevron.right", "Next", 1)
            Menu {
                Button("Save CSV…", systemImage: "tablecells") {
                    csv = CSVDocument(data: CSVExport.data(for: report.entries, ledger: model.ledger))
                    savingCSV = true
                }
                Button("Save PDF…", systemImage: "doc.richtext") {
                    pdf = PDFDocumentFile(data: StatementPDF.data(for: report, ledger: model.ledger, title: state.title, now: model.now))
                    savingPDF = true
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .disabled(report.entries.isEmpty)
            .accessibilityLabel(Text("Export"))
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 6)
        .fileExporter(isPresented: $savingPDF, document: pdf, contentType: .pdf, defaultFilename: StatementPDF.fileName(for: report, title: state.title)) { _ in }
    }

    private func stepButton(_ systemImage: String, _ title: String, _ direction: Int) -> some View {
        Button {
            state.step(direction)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(title))
    }

    // MARK: Choices

    /// Who it's for and how it's grouped, as chips.
    private var choices: some View {
        HStack(spacing: 8) {
            Menu {
                ReportFilterItems(state: state)
            } label: {
                chip(state.title)
            }
            Menu {
                ForEach(ReportRequest.Grouping.allCases, id: \.self) { grouping in
                    Button("By \(grouping.rawValue)") { state.grouping = grouping }
                }
            } label: {
                chip("by \(state.grouping.rawValue)")
            }
            Menu {
                if !state.tags.isEmpty {
                    Button("Any tag") { state.tags = [] }
                }
                ForEach(tagChoices, id: \.self) { tag in
                    Toggle(tag, isOn: Binding(
                        get: { state.tags.contains(tag) },
                        set: { on in
                            if on { state.tags.insert(tag) } else { state.tags.remove(tag) }
                        }
                    ))
                }
            } label: {
                Text(state.tags.isEmpty ? "+ tag" : state.tags.sorted().joined(separator: " "))
                    .font(.system(size: 13))
                    .foregroundStyle(state.tags.isEmpty ? Theme.text2 : Theme.tag)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .overlay(Capsule().strokeBorder(Theme.strongLine, style: StrokeStyle(lineWidth: 1, dash: state.tags.isEmpty ? [3, 2] : [])))
            }
            .disabled(tagChoices.isEmpty)
        }
        .padding(.horizontal, 16)
    }

    private func chip(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundStyle(Theme.tag)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Capsule().fill(Theme.accentFill))
        .overlay(Capsule().strokeBorder(Theme.accentLine))
    }

    /// The tags of the entries in the range, the most used first.
    private var tagChoices: [String] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for entry in report.entries {
            for tag in entry.entry.tags {
                counts[tag.lowercased(), default: 0] += 1
                spelling[tag.lowercased()] = tag
            }
        }
        for tag in state.tags {
            spelling[tag.lowercased()] = spelling[tag.lowercased()] ?? tag
            counts[tag.lowercased(), default: 0] += 0
        }
        return counts.keys
            .sorted { a, b in counts[a, default: 0] != counts[b, default: 0] ? counts[a, default: 0] > counts[b, default: 0] : a < b }
            .prefix(20)
            .compactMap { spelling[$0] }
    }

    // MARK: Figures

    private var figures: some View {
        let comparison = state.comparison
        let change = comparison.total - comparison.previousTotal
        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                figure("Total", Text(Format.duration(report.total)))
                figure("Average day", Text(Format.duration(report.averagePerDayWorked)))
            }
            GridRow {
                figure("Days worked", Text("\(report.daysWorked) ") + Text("of \(state.weekdays)").font(.system(size: 12)).foregroundColor(Theme.text3))
                figure(comparisonTitle, Text((change >= 0 ? "+" : "−") + Format.duration(abs(change))))
            }
        }
        .background(Theme.line)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
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

    private func figure(_ label: String, _ value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text2)
            value
                .font(.system(size: 19, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
    }

    // MARK: Checks

    private var overlapWarning: some View {
        let days = state.overlapDaysInRange
        return HStack(spacing: 10) {
            OverlapSwatch(size: 12)
            (Text(Format.duration(report.doubleCounted)).fontWeight(.semibold).foregroundColor(Theme.amberText)
                + Text(" counted twice on \(days.map { Format.monthDay($0) }.formatted(.list(type: .and)))"))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let first = days.first {
                Button("Fix ›") {
                    router.showWeek(first, firstWeekday: model.firstWeekday)
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(minHeight: 44)
                .padding(.horizontal, 8)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.amberFill))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.amberLine))
    }

    // MARK: Breakdown

    private var breakdown: some View {
        let rows = report.groups
        let shown = showsAll ? rows : Array(rows.prefix(8))
        return VStack(alignment: .leading, spacing: 8) {
            Text("By \(state.grouping.rawValue)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text2)
            if rows.isEmpty {
                Text("Nothing logged.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
            }
            ForEach(shown) { group in
                HStack(spacing: 10) {
                    ReportGroupTitle(group, in: state, spacing: 7)
                    Spacer(minLength: 8)
                    Text(Format.duration(group.milliseconds))
                        .monospacedDigit()
                    Text(Format.percent(group.milliseconds, of: report.total))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text3)
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 14))
                .frame(minHeight: 28)
            }
            if rows.count > 8 {
                Button(showsAll ? "Show fewer" : "\(rows.count - 8) more") {
                    showsAll.toggle()
                }
                .font(.system(size: 14))
            }
        }
    }
}

/// A month's days in weeks, each with its date, a bar of its time and a
/// mark where entries overlap, the days of the report outlined.
struct PhoneMonthGrid: View {
    let model: AppModel
    let state: ReportState
    let month: LocalDate
    /// The day a hold-and-drag started on.
    @State private var dragStart: LocalDate?

    private static let cellHeight: CGFloat = 50
    private static let spacing: CGFloat = 4

    var body: some View {
        let weeks = MonthGrid.weeks(of: month, firstWeekday: model.firstWeekday)
        VStack(spacing: Self.spacing) {
            HStack(spacing: Self.spacing) {
                ForEach(weeks.first ?? [], id: \.self) { day in
                    Text(Format.weekday(day).prefix(1))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
            GeometryReader { geometry in
                let width = (geometry.size.width - Self.spacing * 6) / 7
                VStack(spacing: Self.spacing) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: Self.spacing) {
                            ForEach(week, id: \.self) { day in
                                cell(day)
                                    .frame(width: width)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onChanged { value in
                            guard case let .second(true, drag?) = value else { return }
                            let day = self.day(at: drag.location, width: width, weeks: weeks)
                            let start = dragStart ?? self.day(at: drag.startLocation, width: width, weeks: weeks)
                            dragStart = start
                            if let start, let day {
                                state.show(min(start, day)...max(start, day), period: start == day ? .day : .custom)
                            }
                        }
                        .onEnded { _ in
                            dragStart = nil
                        }
                )
            }
            .frame(height: CGFloat(weeks.count) * (Self.cellHeight + Self.spacing) - Self.spacing)
        }
    }

    private func day(at point: CGPoint, width: CGFloat, weeks: [[LocalDate]]) -> LocalDate? {
        let column = Int(point.x / (width + Self.spacing))
        let row = Int(point.y / (Self.cellHeight + Self.spacing))
        guard weeks.indices.contains(row), weeks[row].indices.contains(column) else { return nil }
        return weeks[row][column]
    }

    private func cell(_ day: LocalDate) -> some View {
        let total = state.dayTotals.total(on: day)
        let inMonth = day.month == month.month && day.year == month.year
        let weekend = day.weekday == 1 || day.weekday == 7
        let selected = state.range.contains(day) && state.range != monthRange
        let bar = total > 0 ? max(2, CGFloat(min(total, ChartScale.fullDay)) / CGFloat(ChartScale.fullDay) * 26) : 0
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(inMonth ? (weekend ? Theme.weekendCell : Theme.cell) : Theme.outsideCell)
            Text("\(day.day)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(day == model.today ? Theme.accent : (weekend ? Theme.text3 : Theme.text))
                .padding(.top, 4)
                .padding(.leading, 6)
            if state.overlapDays.contains(day) {
                OverlapSwatch(size: 8)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
            if bar > 0 {
                RoundedRectangle(cornerRadius: 3)
                    .fill(total > Corrections.longest ? Theme.amber : Theme.accent.opacity(0.75))
                    .frame(height: bar)
                    .padding(.horizontal, 5)
                    .padding(.bottom, 5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(height: Self.cellHeight)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .opacity(inMonth ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture {
            if state.range == day...day {
                state.show(monthRange, period: .month)
            } else {
                state.show(day...day, period: .day)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Format.longDay(day)), \(total > 0 ? Format.duration(total) : "no time")\(state.overlapDays.contains(day) ? ", with an overlap" : "")"))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var monthRange: ClosedRange<LocalDate> {
        ReportPeriod.month.range(containing: month, firstWeekday: model.firstWeekday)
    }
}
#endif
