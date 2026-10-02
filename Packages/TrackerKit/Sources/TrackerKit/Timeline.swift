import SwiftUI
import TrackerCore

// The timeline's calendar arithmetic, the hour grid's measurements and the
// blocks on it, shared by the Mac's and the iPad's timelines.

/// How much of the calendar the timeline shows.
public enum TimelineSpan: String, CaseIterable, Identifiable {
    case day, week, month

    public var id: Self { self }

    public var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// The days shown around `day`: the day itself, its week, or its month.
    /// Weeks start on `firstWeekday`, 1 for Sunday through 7 for Saturday.
    public func range(around day: LocalDate, firstWeekday: Int) -> ClosedRange<LocalDate> {
        switch self {
        case .day: day...day
        case .week: ReportPeriod.week.range(containing: day, firstWeekday: firstWeekday)
        case .month: ReportPeriod.month.range(containing: day, firstWeekday: firstWeekday)
        }
    }

    /// The day to show after moving `steps` days, weeks or months on from
    /// `day`. A month keeps the day of the month, or takes the month's last
    /// day if it's shorter.
    public func day(_ day: LocalDate, movedBy steps: Int, firstWeekday: Int) -> LocalDate {
        switch self {
        case .day:
            return day.adding(days: steps)
        case .week:
            return day.adding(days: 7 * steps)
        case .month:
            let month = ReportPeriod.month.shift(range(around: day, firstWeekday: firstWeekday), by: steps, firstWeekday: firstWeekday)
            return LocalDate(year: month.lowerBound.year, month: month.lowerBound.month, day: min(day.day, month.upperBound.day))
        }
    }
}

/// The weeks of a month calendar.
public enum MonthGrid {
    /// Every week with a day in the month of `month`, each starting on
    /// `firstWeekday`.
    public static func weeks(of month: LocalDate, firstWeekday: Int) -> [[LocalDate]] {
        let days = ReportPeriod.month.range(containing: month, firstWeekday: firstWeekday)
        var start = days.lowerBound.startOfWeek(firstWeekday: firstWeekday)
        var weeks: [[LocalDate]] = []
        while start <= days.upperBound {
            weeks.append((0..<7).map { start.adding(days: $0) })
            start = start.adding(days: 7)
        }
        return weeks
    }
}

/// The hour grid of a day or week: its measurements, and the arithmetic of
/// dragging blocks on it. Times snap to five minutes.
public enum HourGrid {
    public static let hourHeight: CGFloat = 60
    /// The width of the hours on the left.
    public static let gutter: CGFloat = 58
    public static let trailing: CGFloat = 12
    /// Five minutes, in seconds.
    public static let snap = 300
    /// The hour shown at the top unless an entry starts earlier.
    public static let morning = 7

    /// What dragging a block changes: where it is, or its start or end.
    public enum DragKind: Hashable, Sendable {
        case move, start, end
    }

    /// The width of each day's column in a grid `width` points wide.
    public static func dayWidth(_ width: CGFloat, days: Int) -> CGFloat {
        max((width - gutter - trailing) / CGFloat(max(days, 1)), 40)
    }

    /// How far down the grid a second of the day is.
    public static func y(_ second: Int) -> CGFloat {
        CGFloat(second) / 3600 * hourHeight
    }

    /// The hour to scroll to: 7:00, or the hour of an entry that starts
    /// earlier.
    public static func firstHour(_ columns: [[DayBlock]]) -> Int {
        min(columns.joined().map { $0.startSecond / 3600 }.min() ?? morning, morning)
    }

    /// A block's start and end after dragging by `delta` seconds, snapped to
    /// five minutes and kept within the day.
    public static func adjusted(_ block: DayBlock, kind: DragKind, by delta: Int) -> (Int, Int) {
        func snapped(_ second: Int) -> Int {
            Int((Double(second) / Double(snap)).rounded()) * snap
        }
        let length = block.endSecond - block.startSecond
        switch kind {
        case .move:
            let start = min(max(snapped(block.startSecond + delta), 0), max(86400 - length, 0))
            return (start, start + length)
        case .start:
            let start = min(max(snapped(block.startSecond + delta), 0), max(block.endSecond - snap, 0))
            return (start, block.endSecond)
        case .end:
            let end = max(min(snapped(block.endSecond + delta), 86400), block.startSecond + snap)
            return (block.startSecond, end)
        }
    }

    /// How many days a block dragged `width` points sideways moves: to the
    /// nearest day's column, within the days shown.
    public static func dayShift(_ width: CGFloat, dayWidth: CGFloat, from index: Int, days: Int) -> Int {
        guard dayWidth > 0 else { return 0 }
        let shift = Int((width / dayWidth).rounded())
        return min(max(shift, -index), days - 1 - index)
    }

    /// Where an hour added at `y` points down the grid starts: on five
    /// minutes, and early enough to end by midnight.
    public static func newEntrySecond(atY y: CGFloat) -> Int {
        min(max(Int(y / hourHeight * 3600) / snap * snap, 0), 86400 - 3600)
    }
}

extension AppModel {
    /// Applies a block dragged on the timeline. A move puts its entry at
    /// `startSecond` on the day `dayShift` days after `day`, keeping its
    /// length; dragging its start or end changes that to `startSecond` or
    /// `endSecond` on `day`. Times are in the entry's own time zone.
    public func applyDrag(
        _ kind: HourGrid.DragKind,
        to block: DayBlock,
        on day: LocalDate,
        startSecond: Int,
        endSecond: Int,
        dayShift: Int = 0,
        undoManager: UndoManager?
    ) {
        let resolved = block.entry
        let zone = resolved.entry.timeZone
        func time(_ second: Int, on date: LocalDate) -> Timestamp {
            Timestamp(date: date, secondOfDay: second, zone: zone)
        }
        switch kind {
        case .move:
            guard startSecond != block.startSecond || dayShift != 0 else { return }
            let shift = resolved.start.distance(to: time(startSecond, on: day.adding(days: dayShift)))
            updateEntries([block.id], actionName: "Move Entry", undoManager: undoManager) { entry in
                entry.start = entry.start.adding(milliseconds: shift)
                entry.end = entry.end.map { $0.adding(milliseconds: shift) }
            }
        case .start:
            guard startSecond != block.startSecond else { return }
            if resolved.isRunning {
                setRunningStart(time(startSecond, on: day), undoManager: undoManager)
            } else {
                updateEntries([block.id], actionName: "Change Start", undoManager: undoManager) {
                    $0.start = time(startSecond, on: day)
                }
            }
        case .end:
            guard endSecond != block.endSecond else { return }
            updateEntries([block.id], actionName: "Change End", undoManager: undoManager) {
                $0.end = time(endSecond, on: day)
            }
        }
    }

    /// Adds an hour starting `second` seconds into `day`, in this device's
    /// time zone, and returns its id; nil while the data is read-only.
    @discardableResult
    public func addHour(on day: LocalDate, at second: Int, undoManager: UndoManager?) -> UUID? {
        guard !isReadOnly else { return nil }
        let zone = environment.timeZone()
        let entry = TimeEntry(
            start: Timestamp(date: day, secondOfDay: second, zone: zone),
            end: Timestamp(date: day, secondOfDay: second + 3600, zone: zone),
            timeZone: zone,
            updated: environment.now()
        )
        addEntry(entry, undoManager: undoManager)
        return entry.id
    }
}

/// One entry's block: its project, times, note and tags, in the project's
/// color, with an orange edge when it overlaps another entry. Tags show when
/// the block has room for them; ones that refer to issues are tinted.
public struct TimelineBlock: View {
    let title: String
    let detail: String
    let tags: [String]
    let links: [String: URL]
    let color: Color
    let flagged: Bool
    let selected: Bool
    let running: Bool

    public init(
        title: String,
        detail: String,
        tags: [String] = [],
        links: [String: URL] = [:],
        color: Color,
        flagged: Bool,
        selected: Bool,
        running: Bool
    ) {
        self.title = title
        self.detail = detail
        self.tags = tags
        self.links = links
        self.color = color
        self.flagged = flagged
        self.selected = selected
        self.running = running
    }

    public var body: some View {
        ViewThatFits(in: .vertical) {
            content(detailLines: 3, showsTags: true)
            content(detailLines: 1, showsTags: true)
            content(detailLines: 3, showsTags: false)
        }
        .font(.caption)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(selected ? 0.42 : 0.22))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(flagged ? Color.orange : color)
                .frame(width: flagged ? 4 : 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(selected ? color : Color.clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func content(detailLines: Int, showsTags: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                if flagged {
                    OverlapIcon()
                        .help("Overlaps another entry")
                }
                if running {
                    RunningIcon()
                }
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(detailLines)
            if showsTags, !tags.isEmpty {
                TagList(tags: tags, links: links, interactive: false, wraps: true)
                    .padding(.top, 2)
            }
        }
    }
}

extension TimelineBlock {
    /// A block's times, or while it's dragged the times it would get, and
    /// its note, such as "09:00 – 10:30  Wireframe review".
    public static func detail(_ resolved: ResolvedEntry, startSecond: Int, endSecond: Int, dragging: Bool) -> String {
        let times: String
        if dragging {
            times = "\(Format.time(secondOfDay: startSecond)) – \(Format.time(secondOfDay: endSecond))"
        } else {
            let zone = resolved.entry.timeZone
            let end = resolved.end.map { Format.time($0, zone: zone) } ?? "now"
            times = "\(Format.time(resolved.start, zone: zone)) – \(end)"
        }
        return resolved.entry.note.isEmpty ? times : "\(times)  \(resolved.entry.note)"
    }
}

// MARK: - Grid and calendar parts

/// The hours down an hour grid's left side, each with a line across the
/// grid. Each hour's row has the hour as its id, to scroll to.
public struct HourLines: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(Format.hour(hour))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: HourGrid.gutter - 10, alignment: .trailing)
                        .offset(y: -7)
                    VStack(spacing: 0) {
                        Divider()
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: HourGrid.hourHeight)
                .id(hour)
            }
        }
    }
}

/// The time now on an hour grid: a red line across today's column, with a
/// dot where it starts, as Calendar draws it.
public struct NowLine: View {
    let width: CGFloat

    /// The dot's radius, which is also how far the line's middle is below
    /// the view's top.
    public static let radius: CGFloat = 4

    public init(width: CGFloat) {
        self.width = width
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.red)
                .frame(width: width, height: 1.5)
            Circle()
                .fill(Color.red)
                .frame(width: 2 * Self.radius, height: 2 * Self.radius)
                .offset(x: -Self.radius)
        }
        .frame(width: width, height: 2 * Self.radius, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A day's number in a calendar: white on an accent capsule when it's
/// today, as Calendar marks it, and dimmed when it's outside the month
/// shown.
public struct DayNumber: View {
    let day: LocalDate
    let font: Font
    let isToday: Bool
    let dimmed: Bool

    public init(_ day: LocalDate, font: Font, isToday: Bool, dimmed: Bool = false) {
        self.day = day
        self.font = font
        self.isToday = isToday
        self.dimmed = dimmed
    }

    public var body: some View {
        Text("\(day.day)")
            .font(font.weight(isToday ? .semibold : .regular))
            .foregroundStyle(isToday ? Color.white : dimmed ? Color.secondary : Color.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background {
                if isToday {
                    Capsule()
                        .fill(Color.accentColor)
                }
            }
    }
}

/// A day's heading over its column in the week view: its weekday, its
/// number, and the time logged on it.
public struct WeekDayHeading: View {
    let day: LocalDate
    let isToday: Bool
    let total: Int64

    public init(day: LocalDate, isToday: Bool, total: Int64) {
        self.day = day
        self.isToday = isToday
        self.total = total
    }

    public var body: some View {
        VStack(spacing: 1) {
            Text(Format.weekday(day))
                .font(.caption)
                .foregroundStyle(.secondary)
            DayNumber(day, font: .title3, isToday: isToday)
            Text(total > 0 ? Format.duration(total) : " ")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// An entry in a month calendar: its project's color and title, the
/// warning or the running mark the entries list shows, and how long it
/// ran. Its tooltip has its times and note.
public struct MonthEntryRow: View {
    let model: AppModel
    let entry: ResolvedEntry
    let flagged: Bool
    let selected: Bool
    let height: CGFloat

    public init(model: AppModel, entry: ResolvedEntry, flagged: Bool, selected: Bool, height: CGFloat) {
        self.model = model
        self.entry = entry
        self.flagged = flagged
        self.selected = selected
        self.height = height
    }

    public var body: some View {
        let zone = entry.entry.timeZone
        let times = "\(Format.time(entry.start, zone: zone)) – \(entry.end.map { Format.time($0, zone: zone) } ?? "now")"
        HStack(spacing: 4) {
            ProjectDot(ledger: model.ledger, projectID: entry.entry.projectID, size: 7, relativeTo: .caption)
            Text(model.ledger.projectTitle(entry.entry.projectID))
                .lineLimit(1)
                .foregroundStyle(entry.entry.projectID == nil ? .secondary : .primary)
            Spacer(minLength: 2)
            if flagged {
                OverlapIcon()
                    .imageScale(.small)
            } else if entry.isRunning {
                RunningIcon()
                    .imageScale(.small)
            }
            Text(Format.duration(model.duration(of: entry)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 3)
        .frame(height: height)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(selected ? Color.accentColor.opacity(0.25) : Color.clear)
        }
        .contentShape(Rectangle())
        .help(entry.entry.note.isEmpty ? times : "\(times)\n\(entry.entry.note)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Blocks") {
    let links = ["#42": URL(string: "https://github.com/acme/website/issues/42")!]
    return HStack(alignment: .top, spacing: 8) {
        TimelineBlock(
            title: "Acme › Website redesign",
            detail: "10:00 – 12:30  Hero section",
            tags: ["design", "#42"],
            links: links,
            color: Color(hex: "#4F7CAC"),
            flagged: false,
            selected: false,
            running: false
        )
        .frame(width: 170, height: 110)
        TimelineBlock(
            title: "Globex › Brand refresh",
            detail: "15:30 – 16:30  Call with Globex",
            tags: ["client-call"],
            color: Color(hex: "#9BBB59"),
            flagged: true,
            selected: true,
            running: false
        )
        .frame(width: 170, height: 60)
        TimelineBlock(
            title: "Unassigned",
            detail: "14:45 – now  Landing page copy",
            color: .gray,
            flagged: false,
            selected: false,
            running: true
        )
        .frame(width: 170, height: 40)
    }
    .padding()
}

#Preview("Calendar Parts") {
    let model = PreviewData.model()
    let today = model.today
    let entries = model.resolved.filter { $0.entry.day >= today.adding(days: -1) }
    return VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 0) {
            WeekDayHeading(day: today.adding(days: -1), isToday: false, total: 27_900_000)
            WeekDayHeading(day: today, isToday: true, total: 20_400_000)
            WeekDayHeading(day: today.adding(days: 1), isToday: false, total: 0)
        }
        HStack {
            DayNumber(today.adding(days: -1), font: .callout, isToday: false)
            DayNumber(today, font: .callout, isToday: true)
            DayNumber(today.adding(days: 9), font: .callout, isToday: false, dimmed: true)
        }
        NowLine(width: 220)
            .padding(.leading, NowLine.radius)
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                MonthEntryRow(
                    model: model,
                    entry: entry,
                    flagged: model.overlaps.flagged.contains(entry.id),
                    selected: entry.id == PreviewData.entry("Kickoff with the new team"),
                    height: 18
                )
            }
        }
        .frame(width: 220)
        ScrollView {
            HourLines()
        }
        .frame(height: 160)
    }
    .padding()
    .frame(width: 320)
}
#endif
