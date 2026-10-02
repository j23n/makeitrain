#if os(macOS)
import SwiftUI
import TrackerCore
import TrackerKit

/// A month as a calendar: a row for each week, each day with its total and
/// its entries. Click an entry to select it; double-click a day, or its
/// "more", to show the day on the timeline.
struct MonthCalendar: View {
    let model: AppModel
    /// Any day in the month shown.
    let month: LocalDate
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    let openDay: (LocalDate) -> Void
    @Environment(\.undoManager) private var undoManager

    static let lineHeight: CGFloat = 17

    var body: some View {
        let weeks = MonthGrid.weeks(of: month, firstWeekday: model.firstWeekday)
        let monthDays = ReportPeriod.month.range(containing: month, firstWeekday: model.firstWeekday)
        let shown = (weeks.first?.first ?? month)...(weeks.last?.last ?? month)
        let byDay = Dictionary(grouping: model.resolved.filter { shown.contains($0.entry.day) }) { $0.entry.day }
        let today = model.today
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weeks.first ?? [], id: \.self) { day in
                    Text(Format.weekday(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            Divider()
            GeometryReader { geometry in
                let rowHeight = geometry.size.height / CGFloat(max(weeks.count, 1))
                VStack(spacing: 0) {
                    ForEach(weeks, id: \.self) { week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { day in
                                MonthDayCell(
                                    model: model,
                                    day: day,
                                    entries: byDay[day] ?? [],
                                    inMonth: monthDays.contains(day),
                                    isToday: day == today,
                                    height: rowHeight,
                                    selection: $selection,
                                    sheet: $sheet,
                                    openDay: openDay
                                )
                                if day != week.last {
                                    Divider()
                                }
                            }
                        }
                        .frame(height: rowHeight - 1)
                        Divider()
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onDeleteCommand {
            guard let selection, !model.isReadOnly else { return }
            model.deleteEntries([selection], undoManager: undoManager)
        }
        .onExitCommand {
            selection = nil
        }
    }
}

/// A day in the month calendar: its number, its total, and as many of its
/// entries as fit.
struct MonthDayCell: View {
    let model: AppModel
    let day: LocalDate
    /// The day's entries, by start.
    let entries: [ResolvedEntry]
    let inMonth: Bool
    let isToday: Bool
    let height: CGFloat
    @Binding var selection: UUID?
    @Binding var sheet: EntriesSheet?
    let openDay: (LocalDate) -> Void
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        let total = entries.reduce(Int64(0)) { $0 + model.duration(of: $1) }
        let flagged = model.overlaps.flagged
        // The lines under the day's number, one of them for "more" when not
        // every entry fits.
        let lines = max(0, Int((height - 30) / MonthCalendar.lineHeight))
        let shownCount = entries.count > lines ? max(lines - 1, 0) : entries.count
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                DayNumber(day, font: .callout, isToday: isToday, dimmed: !inMonth)
                Spacer(minLength: 2)
                if total > 0 {
                    Text(Format.duration(total))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 3)
            ForEach(entries.prefix(shownCount)) { entry in
                MonthEntryRow(
                    model: model,
                    entry: entry,
                    flagged: flagged.contains(entry.id),
                    selected: selection == entry.id,
                    height: MonthCalendar.lineHeight
                )
                .onTapGesture {
                    selection = entry.id
                }
                .contextMenu {
                    EntriesMenu(model: model, ids: [entry.id], undoManager: undoManager, sheet: $sheet) { copies in
                        selection = copies.first
                    }
                }
            }
            if shownCount < entries.count {
                Button("\(entries.count - shownCount) more") {
                    openDay(day)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 3)
                .help("Show \(Format.longDay(day))")
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Color.clear : Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            openDay(day)
        }
        // Back to the inspector's summary of the month.
        .onTapGesture {
            selection = nil
        }
    }
}

#if DEBUG
#Preview("September") {
    MonthCalendar(
        model: PreviewData.model(),
        month: LocalDate(year: 2026, month: 9, day: 23),
        selection: .constant(PreviewData.entry("Call with Globex")),
        sheet: .constant(nil),
        openDay: { _ in }
    )
    .frame(width: 1000, height: 640)
}

#Preview("Small") {
    MonthCalendar(
        model: PreviewData.model(),
        month: LocalDate(year: 2026, month: 9, day: 23),
        selection: .constant(nil),
        sheet: .constant(nil),
        openDay: { _ in }
    )
    .frame(width: 640, height: 420)
}
#endif
#endif
